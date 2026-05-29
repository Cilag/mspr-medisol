# 03 — Mise en œuvre

## 3.1 Phase 0 — Préparation (avant intervention)

### Inventaire et prérequis

- [ ] Inventaire complet du parc (postes, serveur Windows Server actuel, équipements connectés)
- [ ] Récupération des licences logicielles (éditeur logiciel patient, Windows Server actuel)
- [ ] Contact éditeur logiciel patient : vérification compatibilité RDS / Remote App (Windows Server 2022)
- [ ] Sauvegarde complète du serveur imagerie existant (image disque + exports données)
- [ ] Commande matériel : 2x Dell PowerEdge R350, switch 24 ports PoE, 2x AP Wi-Fi 6

### Configuration réseau préalable

- Schéma adressage IP validé (VLANs 10/20/30/40/99)
- Mot de passe et clés SSH de maintenance générés et stockés dans un gestionnaire de secrets

---

## 3.2 Phase 1 — Déploiement de l'hyperviseur Proxmox VE

### Installation SRV1 (nœud primaire)

```bash
# Installation Proxmox VE 8.x depuis ISO sur clé USB
# Paramètres d'installation :
# - Hostname : pve-medisol-01.local
# - IP management : 10.0.30.11/24
# - Gateway : 10.0.30.1 (OPNsense)
# - DNS : 10.0.30.1

# Post-installation — désactiver le repo entreprise, activer no-subscription
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list
apt update && apt dist-upgrade -y
```

### Installation SRV2 (nœud secondaire)

- Même procédure : hostname `pve-medisol-02.local`, IP `10.0.30.12/24`

### Création du cluster Proxmox

```bash
# Sur SRV1 — créer le cluster
pvecm create medisol-cluster

# Sur SRV2 — rejoindre le cluster
pvecm add 10.0.30.11
```

### Configuration ZFS

```bash
# Sur chaque nœud : créer le pool ZFS pour les VMs
zpool create -f vmdata raidz /dev/sdb /dev/sdc /dev/sdd /dev/sde

# Activer la compression
zfs set compression=lz4 vmdata

# Ajouter le stockage dans Proxmox
pvesm add zfspool vmdata-pool --pool vmdata --content images,rootdir
```

---

## 3.3 Phase 2 — Déploiement OPNsense (pare-feu)

### Création de la VM OPNsense

```
Ressources : 2 vCPU, 2 GB RAM, 20 GB disque
Interfaces réseau :
  - vtnet0 : WAN (vers box FAI)
  - vtnet1 : VLAN 10 (Métier accueil) — 10.0.10.1/24
  - vtnet2 : VLAN 20 (Administration) — 10.0.20.1/24
  - vtnet3 : VLAN 30 (Serveurs)       — 10.0.30.1/24
  - vtnet4 : VLAN 40 (IoT/Caméras)    — 10.0.40.1/24
  - vtnet5 : VLAN 99 (Patients)       — 10.0.99.1/24
```

### Règles de filtrage inter-VLAN

Configuration via l'interface OPNsense → Firewall → Rules :

| Source | Destination | Port | Action | Description |
|---|---|---|---|---|
| VLAN10 net | VLAN30 net | TCP 445, 3389 | Pass | Accueil → logiciel patient + imagerie |
| VLAN10 net | WAN | TCP 443, 80 | Pass | Accueil → M365 |
| VLAN20 net | VLAN30 net | TCP 445, 443 | Pass | Admin → serveurs |
| VLAN20 net | WAN | TCP 443, 80 | Pass | Admin → M365 |
| VLAN40 net | !VLAN40 net | * | Block | IoT isolé |
| VLAN99 net | WAN | TCP 443, 80 | Pass | Patients → Internet uniquement |
| VLAN99 net | !WAN | * | Block | Isolation patients |
| WireGuard | VLAN10 net | TCP 3389 | Pass | Nomades → RDS |

### Activation IDS Suricata

- Activer Suricata sur l'interface WAN
- Ensembles de règles : `ET Open` (trafic malveillant) + `Emerging Threats`
- Logs IDS exportés vers VM-MON (syslog)

---

## 3.4 Phase 3 — Déploiement des VMs

### VM-PATIENT — Logiciel patient (RDS)

```powershell
# Après installation Windows Server 2022
# Activer Remote Desktop Services
Install-WindowsFeature -Name RDS-RD-Server, RDS-Licensing -IncludeManagementTools

# Installer le logiciel patient selon les instructions de l'éditeur
# Configurer RemoteApp pour publication du logiciel patient
New-RDRemoteApp -CollectionName "Medisol" -DisplayName "Logiciel Patient" `
    -FilePath "C:\Program Files\LogicielPatient\patient.exe"

# Activer la journalisation des sessions RDS (conformité RGPD)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters" `
    -Name "EnableEventLogs" -Value 1
```

### VM-IMAGERIE — Stockage imagerie légère

```powershell
# Installation Windows Server 2022
# Activer le rôle File Services
Install-WindowsFeature -Name File-Services -IncludeManagementTools

# Créer le partage imagerie avec chiffrement SMB
New-SmbShare -Name "Imagerie" -Path "D:\Imagerie" `
    -EncryptData $true -ReadAccess "MEDISOL\Praticiens" `
    -FullAccess "MEDISOL\Admin-IT"

# Activer BitLocker sur le volume D:
Enable-BitLocker -MountPoint "D:" -EncryptionMethod XtsAes256 `
    -UsedSpaceOnly -RecoveryPasswordProtector
```

### VM-MON — Supervision

```bash
# Installation Netdata
curl https://my-netdata.io/kickstart.sh | bash

# Installation Grafana + Prometheus
apt install -y grafana prometheus

# Configuration Prometheus — scrape Proxmox et VMs
cat >> /etc/prometheus/prometheus.yml << 'EOF'
  - job_name: 'proxmox-nodes'
    static_configs:
      - targets: ['10.0.30.11:9090', '10.0.30.12:9090']
  - job_name: 'vms'
    static_configs:
      - targets: ['10.0.30.21:19999', '10.0.30.22:19999']
EOF
```

### VM-WEB — Portail patient (DMZ)

```bash
# Installation Nginx + Certbot
apt install -y nginx certbot python3-certbot-nginx

# Configuration reverse proxy vers l'application portail
cat > /etc/nginx/sites-available/portail-patient << 'EOF'
server {
    listen 80;
    server_name rdv.medisol.fr;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    server_name rdv.medisol.fr;
    ssl_certificate /etc/letsencrypt/live/rdv.medisol.fr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/rdv.medisol.fr/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        add_header Strict-Transport-Security "max-age=31536000" always;
    }
}
EOF
```

---

## 3.5 Phase 4 — Infrastructure Wi-Fi managée

### Déploiement des Access Points

```
AP1 (Salle d'attente / Accueil) — PoE sur port switch VLAN trunk
AP2 (Zone cabinets)              — PoE sur port switch VLAN trunk

SSIDs configurés :
  MEDISOL-Praticiens  → VLAN 10 (WPA3-Enterprise, auth M365)
  MEDISOL-Admin       → VLAN 20 (WPA3-Enterprise, auth M365)
  MEDISOL-Patients    → VLAN 99 (WPA3-Personal, portail captif)
```

### Configuration portail captif patients (VLAN 99)

- Portail captif OPNsense sur VLAN 99 : acceptation CGU avant accès Internet
- QoS : bande passante patients limitée à 10 Mb/s (up/down) pour ne pas saturer le lien pro
- Isolation client-à-client : les patients ne peuvent pas communiquer entre eux sur le Wi-Fi

---

## 3.6 Phase 5 — VPN nomades (praticiens itinérants)

```bash
# Sur OPNsense — configuration WireGuard
# Interface wg0 : 10.200.0.1/24

# Génération des clés pour chaque praticien (sur poste nomade)
wg genkey | tee privatekey | wg pubkey > publickey

# Configuration peer (un par praticien)
[Peer]
PublicKey = <clé publique praticien>
AllowedIPs = 10.200.0.X/32
```

- Chaque praticien reçoit un profil WireGuard (.conf) + QR code pour mobile
- Authentification renforcée : MFA Entra ID requis avant activation du tunnel (via Conditional Access)
- Accès limité à VM-PATIENT (10.0.30.21, port 3389) — règle OPNsense dédiée

---

## 3.7 Phase 6 — Sauvegardes (PBS + Azure)

### Proxmox Backup Server (PBS)

```bash
# Installation PBS sur SRV2 (VM dédiée ou bare-metal)
# Créer le datastore de sauvegarde
proxmox-backup-manager datastore create medisol-backup /var/backups/medisol

# Planification des sauvegardes depuis Proxmox
# Datacenter → Backup → Add :
# - Schedule : daily (23:00)
# - Mode : Snapshot
# - Compression : ZSTD
# - Retention : 30 days
# - Notification : email admin
```

### Azure Backup

```bash
# Installation de l'agent Azure Backup sur PBS
wget https://aka.ms/installazurebackupagentupdates -O MARSagentinstaller.run
./MARSagentinstaller.run

# Planification : mardi et vendredi à 02h00
# Rétention : 12 mois
# Chiffrement : passphrase stockée hors ligne
```

---

## 3.8 Migration des données imagerie existantes

```bash
# Depuis le serveur Windows Server existant vers VM-IMAGERIE
# Utiliser robocopy pour migration sans perte

robocopy \\ancienServeur\Imagerie \\vm-imagerie\Imagerie /MIR /COPYALL /LOG:migration.log

# Vérification intégrité après migration
# Comparer les checksums MD5 des fichiers source et destination
Get-ChildItem -Recurse \\ancienServeur\Imagerie |
    Get-FileHash -Algorithm MD5 | Export-Csv checksums_source.csv

Get-ChildItem -Recurse \\vm-imagerie\Imagerie |
    Get-FileHash -Algorithm MD5 | Export-Csv checksums_destination.csv
```

---

## 3.9 Checklist de mise en service

- [ ] Proxmox cluster 2 nœuds opérationnel, Corosync stable
- [ ] ZFS réplication inter-nœuds active (toutes les 15 min)
- [ ] OPNsense déployé, règles inter-VLAN en place, IDS Suricata actif
- [ ] VM-PATIENT accessible via RDS RemoteApp depuis VLAN 10 et VPN
- [ ] VM-IMAGERIE : partage SMB chiffré accessible, données migrées et vérifiées
- [ ] Wi-Fi : 3 SSIDs distincts, isolation patients validée (test ping inter-VLAN = échoue)
- [ ] VPN WireGuard : praticiens nomades connectés, accès VM-PATIENT uniquement
- [ ] PBS : première sauvegarde complète réussie, test de restauration d'une VM validé
- [ ] Azure Backup : première sauvegarde hors site réussie
- [ ] VM-MON : dashboards Grafana opérationnels, alertes email configurées
- [ ] VM-WEB : portail patient accessible en HTTPS, certificat TLS valide
- [ ] Documentation remise au prestataire IT de maintenance
