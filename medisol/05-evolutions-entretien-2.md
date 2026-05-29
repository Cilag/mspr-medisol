# 05 — Évolutions et pistes pour l'entretien 2

> Ce document est un **placeholder structuré** pour préparer l'entretien 2 du MSPR. Il liste les axes d'évolution identifiés lors de la mise en œuvre et les questions ouvertes à approfondir.

---

## 5.1 Évolutions à court terme (0–12 mois)

### 5.1.1 Migration du portail patient vers une solution éprouvée

| Action | Détail | Priorité |
|---|---|---|
| Évaluation éditeur portail patient | Vérifier si l'éditeur propose une offre SaaS hébergée conforme RGPD | Haute |
| Durcissement VM-WEB | WAF applicatif, scan de vulnérabilités mensuel (OpenVAS) | Haute |
| Mise en conformité HDS | Si le portail stocke des données de santé : vérifier exigences hébergement de données de santé (HDS) | Haute |
| Automatisation TLS | Renouvellement automatique Let's Encrypt via ACME OPNsense | Moyenne |

### 5.1.2 Renforcement de la sécurité RGPD

- [ ] **Journalisation complète** des accès au logiciel patient (logs RDS + logs applicatifs éditeur)
- [ ] **DLP (Data Loss Prevention)** : empêcher la copie de données patients vers des supports amovibles (GPO Windows)
- [ ] **Chiffrement de bout en bout** des sauvegardes PBS (clé stockée dans coffre-fort hors site)
- [ ] **Audit trimestriel** des accès praticiens (qui a accédé à quels dossiers, depuis où)

### 5.1.3 Optimisation Wi-Fi

- [ ] Passage en **Wi-Fi 6E** (6 GHz) pour les cabinets si les équipements de mesure le supportent → réduction des interférences
- [ ] **Roaming 802.11r** (Fast BSS Transition) entre AP1 et AP2 pour les appareils mobiles praticiens
- [ ] **QoS DSCP** sur le switch : prioriser le trafic RDS/RemoteApp sur le Wi-Fi praticiens

---

## 5.2 Évolutions à moyen terme (12–36 mois)

### 5.2.1 Ouverture d'un cabinet secondaire

Si MEDISOL ouvre un deuxième site :

| Action | Détail |
|---|---|
| Extension cluster Proxmox | 3e nœud sur le site secondaire |
| VPN site-à-site | Tunnel WireGuard permanent entre les deux sites |
| Réplication PBS inter-sites | VM-PATIENT et VM-IMAGERIE répliquées sur le site secondaire |
| AD Sites and Services | Si Active Directory est déployé à terme |

### 5.2.2 Migration vers un logiciel patient SaaS

Le logiciel patient actuel (client lourd Windows) est vieillissant. Des alternatives SaaS certifiées HDS existent (Doctolib, Maiia, etc.) :

- **Avantage** : plus besoin de VM-PATIENT dédiée + RDS → économie CAPEX/OPEX
- **Inconvénient** : dépendance internet, coût d'abonnement, migration des données historiques
- **À arbitrer** lors de l'entretien 2 : TCO cloud vs on-prem sur 5 ans, délai de migration

### 5.2.3 Imagerie médicale avancée (évolution activité)

Si MEDISOL étend son activité à l'imagerie médicale réglementée (radiologie, scanner) :

- Obligation d'hébergement certifié **HDS** (Hébergeur de Données de Santé)
- Migration de VM-IMAGERIE vers un cloud HDS (OVHcloud Hosted Private Cloud HDS, ou Outscale)
- Intégration DICOM pour les équipements d'imagerie médicale

---

## 5.3 Questions ouvertes pour l'entretien 2

### Sur la conformité RGPD / HDS

1. Le portail patient (en développement) héberge-t-il des données de santé au sens de l'article 9 RGPD ? Si oui, l'hébergement on-prem est-il suffisant ou faut-il une certification HDS ?
2. Quelle est la politique de durée de conservation des données patients dans le logiciel métier ? PBS conserve les backups 30 jours — est-ce cohérent avec le registre de traitements MEDISOL ?
3. Les praticiens nomades accèdent au logiciel patient via VPN → les données transitent chiffrées. Faut-il également chiffrer les sessions RDS (déjà le cas avec RDS SSL) ?

### Sur l'architecture

4. Faut-il déployer un **Active Directory** dédié (VM-AD) pour centraliser l'authentification, ou s'appuyer uniquement sur Entra ID / M365 pour 32 utilisateurs ?
5. Le contrôleur Wi-Fi (VM-WIFI) pourrait-il être remplacé par un contrôleur cloud (Unifi Cloud Key, Omada Cloud) pour simplifier l'administration — est-ce acceptable pour la confidentialité ?
6. Avec 2 nœuds Proxmox et 7 VMs, la charge est-elle équilibrée ? Quelle VM serait la première à migrer si SRV1 est surchargé ?

### Sur la résilience

7. Les équipements IoT (mesures connectées, caméras) sont sur VLAN 40, isolés. Que se passe-t-il si l'OPNsense (VM) tombe ? → Explorer OPNsense sur appliance physique dédiée pour éviter ce SPOF.
8. Le Proxmox HA nécessite un quorum de 2 nœuds. Avec exactement 2 nœuds, un split-brain est possible. Comment l'adresser ? (QDevice Corosync tiers, ou appliance dédiée)

---

## 5.4 Points à intégrer après l'entretien 2 (16 juin)

| Section | Action attendue |
|---|---|
| `02-architecture-proposee.md` | Ajouter les évolutions annoncées (ex. AD, 3e nœud) |
| `03-mise-en-oeuvre.md` | Documenter les nouveaux composants implémentés |
| `04-objectifs-pedagogiques.md` | Mettre à jour les objectifs avec les nouvelles décisions |
| Ce fichier | Cocher les points traités, noter les décisions prises avec le client |
