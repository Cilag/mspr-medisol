# Scripts d'installation — MEDISOL Clinique Bien-Être

Projet MSPR Virtualisation M1 INFRA — données fictives, usage pédagogique uniquement.

## Ordre d'exécution

| # | Script | Cible | Quand |
|---|--------|-------|-------|
| 1 | `01-proxmox-setup.sh` | SRV1 (bare-metal) | Après installation Proxmox VE 8.x depuis ISO |
| 2 | `02-proxmox-join-cluster.sh` | SRV2 (bare-metal) | Après `01-` validé sur SRV1 |
| 3 | `07-pbs-setup.sh` | PBS VM (SRV2) | Après déploiement de la VM PBS |
| 4 | `03-vm-mon-setup.sh` | VM-MON (Debian 12) | Après création de la VM dans Proxmox |
| 5 | `04-vm-web-setup.sh` | VM-WEB (Debian 12) | Après création de la VM dans Proxmox |
| 6 | `05-vm-patient-setup.ps1` | VM-PATIENT (Windows Server 2022) | Après installation Windows + licence RDS |
| 7 | `06-vm-imagerie-setup.ps1` | VM-IMAGERIE (Windows Server 2022) | Après installation Windows + volume D: formaté |
| 8 | `08-wireguard-peer-gen.sh` | Poste admin | Après configuration OPNsense WireGuard |

## Prérequis matériels

- **SRV1** : Dell PowerEdge R350 — 2× Xeon Silver, 64 GB RAM, 2× 1 TB NVMe + 4× 4 TB SAS
- **SRV2** : identique à SRV1
- Switch manageable L2/L3 24 ports PoE (Cisco CBS350 ou HP Aruba 1960)
- 2× Access Points Wi-Fi 6 (Ubiquiti UniFi U6-Pro ou équivalent)

## Prérequis réseau

| VLAN | Plage | Passerelle (OPNsense) |
|------|-------|-----------------------|
| 10 — Métier accueil | 10.0.10.0/24 | 10.0.10.1 |
| 20 — Administration | 10.0.20.0/24 | 10.0.20.1 |
| 30 — Serveurs | 10.0.30.0/24 | 10.0.30.1 |
| 40 — IoT / Caméras | 10.0.40.0/24 | 10.0.40.1 |
| 99 — Patients | 10.0.99.0/24 | 10.0.99.1 |

Adresses fixes des nœuds Proxmox : `10.0.30.11` (SRV1), `10.0.30.12` (SRV2).

## Variables à adapter

Chaque script expose ses variables de configuration en tête de fichier.
Les valeurs par défaut correspondent à l'architecture décrite dans
`medisol/02-architecture-proposee.md` et `medisol/03-mise-en-oeuvre.md`.

Variables couramment à modifier :
- `ZFS_DISKS` (01) — adapter au nombre et noms des disques SAS disponibles
- `SERVER_ENDPOINT` (08) — FQDN/IP publique de l'OPNsense
- `PRATICIENS` (08) — liste des praticiens nomades
- `AZURE_VAULT_NAME` (07) — nom du coffre Recovery Services Azure

## Sécurité

- Les scripts bash utilisent `set -euo pipefail` (interruption immédiate sur erreur).
- Les scripts PowerShell utilisent `Set-StrictMode -Version Latest`.
- Les clés et passphrases générées (BitLocker, WireGuard) **ne doivent pas être versionnées**.
- Conformité éthique du projet : aucune donnée patient réelle dans les démos ou jeux de test.
