# 05 — Évolutions et pistes pour l'entretien 2

> Ce document est un **guide de préparation** pour l'entretien 2 du MSPR MEDISOL. Il liste les axes d'évolution identifiés lors de la mise en œuvre, les questions techniques et réglementaires à approfondir, les points forts à mettre en avant, et les ressources bibliographiques associées.

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

### A — Questions techniques (jury challengeant)

**A1 — Quorum Proxmox avec exactement 2 nœuds**

> Avec seulement SRV1 et SRV2, le cluster Proxmox ne peut pas atteindre un quorum majoritaire (2/2 = split-brain si lien inter-nœuds tombe). Comment adresser ce risque structurel ?

**Réponse préparée :** Déploiement d'un **QDevice Corosync** sur une VM légère (ou Raspberry Pi hors cluster) faisant office de 3e votant. En production, la solution définitive reste l'ajout d'un 3e nœud Proxmox. Sans QDevice, le comportement par défaut est le blocage des migrations HA — aucune donnée patient n'est perdue mais le basculement automatique est désactivé.

---

**A2 — OPNsense en VM = SPOF si la VM tombe**

> Tout le trafic inter-VLAN et le NAT passent par VM-FW (OPNsense virtualisé sur SRV1). Si SRV1 tombe ou si la VM-FW plante, MEDISOL perd l'accès internet, le VPN WireGuard et l'accès au portail patient. Une appliance physique dédiée serait-elle préférable ?

**Réponse préparée :** Dans un contexte PME 32 utilisateurs, le choix OPNsense en VM est acceptable à court terme (coût, simplicité). L'évolution cible est une **appliance physique dédiée** (Protectli VP2420, PC Engines APU4) afin d'isoler le point de contrôle réseau de l'hyperviseur. Alternative immédiate : déplacer VM-FW sur SRV2 avec HA Proxmox activé.

---

**A3 — Révocation rapide de l'accès WireGuard d'un praticien**

> Un praticien quitte MEDISOL. Comment révoquer son accès WireGuard en moins de 5 minutes, sans redémarrer le service, et s'assurer qu'il ne peut plus accéder aux données patients ?

**Réponse préparée :** WireGuard identifie les pairs par clé publique. La révocation consiste à : (1) supprimer la ligne `[Peer]` correspondante dans `/etc/wireguard/wg0.conf` sur le serveur, (2) recharger la config via `wg syncconf wg0 <(wg-quick strip wg0)` — sans interruption de service. Côté Entra ID : désactiver le compte immédiatement pour bloquer aussi l'authentification MFA. La clé privée client devient inutilisable car la clé publique n'est plus dans le peering. Procédure < 2 min.

---

**A4 — RDS RemoteApp et RGPD : résidus de session**

> Les sessions RDS RemoteApp peuvent laisser des données en cache local (profils itinérants, fichiers temporaires, clipboard). En cas d'accès depuis un poste personnel d'un praticien, des données patients pourraient-elles rester sur le terminal ?

**Réponse préparée :** Par défaut, RDS en mode RemoteApp n'affiche que l'application — le bureau local reste le bureau de l'hôte RDS. Cependant, le **presse-papier bidirectionnel** est activé par défaut et constitue un vecteur de fuite. Mesures RGPD : (1) GPO `Disable clipboard redirection`, (2) interdiction de redirection d'imprimante et de lecteurs locaux, (3) profils RDS temporaires supprimés à la déconnexion (`DeleteTempDirsOnExit`). Ces réglages sont documentés dans le dossier MEDISOL section 3.

---

**A5 — PBS : vérification d'intégrité des sauvegardes immuables**

> PBS chiffre et déduplique les backups. Comment s'assurer automatiquement que les sauvegardes sont lisibles et non corrompues sans restauration complète ?

**Réponse préparée :** PBS inclut `proxmox-backup-client verify` et la tâche planifiée **Verify Job** dans l'interface web. La vérification lit tous les chunks, recalcule les hachages SHA-256 et signale toute corruption. Fréquence recommandée : hebdomadaire. De plus, les **Garbage Collection** régulières nettoient les chunks orphelins. Pour une vérification fonctionnelle complète : restauration test mensuelle sur une VM de recette isolée (VM-TEST), tracée dans le registre RGPD.

---

**A6 — Capacité stockage : calcul de croissance sur 3 ans**

> MEDISOL dispose de 5 TB utilisables (après déduplication PBS). La croissance est estimée à 10 GB/mois. À quel horizon faut-il planifier un 3e nœud ou étendre le stockage ?

**Réponse préparée :**
- Stock actuel utilisé : ≈ 2 TB (VMs + backups initiaux)
- Disponible : 3 TB
- Croissance : 10 GB/mois = 120 GB/an
- Saturation à 80 % : 3 TB × 0,8 = 2,4 TB libres → **20 ans** au rythme actuel

Le vrai déclencheur sera l'**imagerie médicale** : un scanner produit 1–2 GB/examen. À 5 examens/semaine : 40 GB/mois, soit saturation en **5 ans**. Recommandation : prévoir le 3e nœud ou un NAS dédié imagerie dès que MEDISOL ouvre à l'imagerie réglementée.

---

**A7 — Licences Windows Server 2022 : expiration**

> Les licences Windows Server 2022 (datacenter, standard) sont achetées perpétuellement mais requièrent un Software Assurance pour les mises à jour de version. Que se passe-t-il si les licences ne sont pas renouvelées ?

**Réponse préparée :** Une licence perpétuelle Windows Server ne « expire » pas — le serveur continue de fonctionner indéfiniment. Ce qui expire, c'est le **Software Assurance** (droit de mise à niveau vers Windows Server 2025/2026). Sans renouvellement : (1) la version installée reste fonctionnelle et reçoit les patchs de sécurité jusqu'à la fin de vie (WS2022 : octobre 2031), (2) aucun droit de montée de version. Risque réel : en 2031, si MEDISOL n'a pas migré, le système entre en **fin de support étendu** — plus aucun patch de sécurité.

---

### B — Questions organisationnelles

**B1 — Formation du prestataire externe à Proxmox**

> MEDISOL n'a pas d'équipe IT interne. Toute la connaissance Proxmox repose sur un prestataire unique. Comment éviter cette dépendance critique tout en restant dans un budget PME ?

**Réponse préparée :** Stratégie à deux niveaux : (1) **documentation opérationnelle** exhaustive dans le dossier MSPR (procédures runbooks : snapshot, restauration, ajout de VM) que n'importe quel prestataire peut suivre ; (2) **contrat avec clause de formation** : le prestataire principal forme un prestataire secondaire ou un référent interne désigné. À moyen terme : abonnement à la formation Proxmox officielle (Proxmox Training) pour deux personnes côté client.

---

**B2 — Validation des tests de PRA sans équipe IT**

> Le Plan de Reprise d'Activité prévoit un RTO < 4h et un RPO < 30 min. Qui, chez MEDISOL, est compétent pour valider qu'un test de PRA est concluant ?

**Réponse préparée :** La validation est **fonctionnelle, pas technique** : le référent désigné (ex. praticien référent ou gestionnaire) vérifie que le logiciel patient répond, que les dossiers sont accessibles, et que les appareils de mesure communiquent. Le prestataire certifie la partie technique. Procédure formalisée : **PV de test PRA** signé par les deux parties, archivé dans le registre RGPD de MEDISOL. Fréquence recommandée : test semestriel.

---

**B3 — Contrôle des accès prestataire aux données patients**

> Comment MEDISOL peut-il s'assurer que le prestataire n'accède pas aux données patients lors d'interventions de maintenance, sans pour autant bloquer l'administration système ?

**Réponse préparée :** Séparation des rôles via **RBAC Proxmox** : le prestataire reçoit un rôle `PVEAdmin` limité aux ressources infra (nœuds, stockage, réseau) sans accès aux VMs contenant les données patients (VM-PATIENT, VM-IMAGERIE) en mode lecture disque. Pour les interventions nécessitant l'accès à ces VMs : procédure de **double autorisation** (le praticien référent ouvre un ticket, l'accès est activé pour une fenêtre de temps limitée, puis révoqué). Logs d'accès PBS + Proxmox conservés 12 mois.

---

**B4 — Procédure d'urgence si le prestataire est indisponible**

> MEDISOL dépend du prestataire pour toute intervention critique. Que se passe-t-il si ce prestataire est indisponible un vendredi soir lors d'une panne du cluster ?

**Réponse préparée :** Le contrat de prestation doit inclure une clause **d'astreinte** (délai de réponse < 4h, intervention < 8h) avec un **prestataire de substitution** identifié et pré-qualifié. La documentation runbook permet à tout intégrateur Proxmox d'intervenir. En parallèle : Azure Backup garantit que les données sont récupérables indépendamment du prestataire. Mesure immédiate documentée : procédure de **boot d'urgence** depuis le PBS (Proxmox Backup Server) sans accès réseau au cluster principal.

---

### C — Questions réglementaires et conformité

**C1 — Portail patient et certification HDS**

> Le portail patient de MEDISOL est en cours de développement. Il permettra aux patients d'accéder à leurs comptes rendus et résultats. Relève-t-il de la certification HDS (Hébergeur de Données de Santé) ?

**Réponse préparée :** Oui, dès lors que le portail **héberge ou donne accès à des données de santé à caractère personnel** au sens de l'article L. 1111-8 du Code de la santé publique. L'hébergeur (ou l'infrastructure) doit être certifié HDS. Options : (1) migrer VM-WEB vers un cloud certifié HDS (OVHcloud HDS, Outscale) ; (2) faire certifier l'hébergement on-prem — coûteux pour une structure de 32 personnes ; (3) choisir un éditeur SaaS portail patient déjà certifié HDS. Recommandation MEDISOL : option 3 (SaaS HDS) dès l'ouverture du portail.

---

**C2 — RGPD : durée de conservation des backups PBS**

> PBS conserve les sauvegardes 30 jours par défaut. Est-ce cohérent avec les obligations RGPD de MEDISOL sur la durée de conservation des données patients ?

**Réponse préparée :** Les backups PBS sont des copies techniques, pas des archives primaires. La **durée de conservation des données de santé** est réglementée : dossier médical conservé **20 ans minimum** (article R. 1112-7 CSP). La rétention PBS à 30 jours couvre uniquement la **restauration en cas d'incident** et ne se substitue pas à l'archivage long terme. MEDISOL doit : (1) conserver le logiciel patient et ses données sur une durée réglementaire de 20 ans ; (2) documenter dans le **registre des traitements** la distinction entre backup opérationnel (30 jours PBS) et archivage légal (20 ans dans le logiciel). Azure Backup peut servir d'archive longue durée à moindre coût (cold tier Azure).

---

**C3 — Logs d'accès au logiciel patient et audit RGPD**

> En cas d'audit CNIL ou d'incident de sécurité, MEDISOL doit prouver qui a accédé à quels dossiers patients, depuis quand et depuis où. Les logs actuels (RDS + éditeur) sont-ils suffisants ?

**Réponse préparée :** L'**article 32 RGPD** impose des mesures techniques garantissant la confidentialité, l'intégrité et la traçabilité. Les logs nécessaires sont : (1) **logs Windows Event** (connexions RDS, ouverture/fermeture de session) ; (2) **logs applicatifs** de l'éditeur du logiciel patient (accès dossier par dossier) ; (3) **logs OPNsense** (connexions VPN WireGuard horodatées). Ces trois couches centralisées dans VM-MON/Grafana constituent une piste d'audit conforme. Point de vigilance : si l'éditeur ne produit pas de logs d'accès dossier, c'est un risque RGPD — à négocier contractuellement comme exigence minimale.

---

**C4 — Assurance cyber : prérequis pour couvrir un ransomware sur données de santé**

> MEDISOL traite des données de santé à risque élevé. Les assureurs cyber exigent des prérequis techniques précis avant de couvrir les ransomwares. Quels sont-ils ?

**Réponse préparée :** Les prérequis typiques des assureurs cyber (2024) pour données de santé :
- **MFA obligatoire** sur tous les comptes d'accès distant → ✅ WireGuard + Entra ID MFA
- **Sauvegardes immuables hors ligne** → ✅ PBS avec tâches de vérification + Azure Backup
- **Segmentation réseau** (VLANs isolés) → ✅ VLAN 10/20/30/40/50
- **EDR sur les endpoints** → à déployer (Microsoft Defender for Business via M365)
- **Plan de réponse à incident documenté** → à formaliser (runbook PRA)
- **Chiffrement des données au repos** → PBS chiffré, à vérifier sur VM-PATIENT

Points restants avant couverture complète : EDR + runbook incident formalisé.

---

**C5 — Azure Backup France Central et souveraineté des données de santé**

> La copie hors site des backups est réalisée via Azure Backup en région France Central. Est-ce conforme aux exigences de souveraineté pour les données de santé ?

**Réponse préparée :** Azure France Central (datacenter Paris/Marseille) est opéré par Microsoft et est éligible aux exigences RGPD (données en France). Cependant, pour les **données de santé au sens HDS**, Azure propose une offre spécifique (**Azure HDS**) avec un avenant contractuel dédié (DPA santé). L'hébergement standard Azure (même en France) ne suffit pas pour des données HDS sans cet avenant. Action : vérifier que le contrat Azure de MEDISOL inclut l'avenant HDS, ou basculer vers un fournisseur certifié HDS natif (OVHcloud HDS, 3DS Outscale). Si les backups PBS contiennent des VMs avec données patients → avenant HDS obligatoire.

---

### D — Questions financières

**D1 — TCO 5 ans : on-prem 2 nœuds Proxmox vs cloud HDS pour l'imagerie**

> Si MEDISOL développe une activité d'imagerie médicale, faut-il rester on-prem ou migrer vers un cloud certifié HDS ? Quel est le TCO comparatif sur 5 ans ?

**Réponse préparée :**

| Poste | On-prem (extension 3e nœud) | Cloud HDS (OVHcloud) |
|---|---|---|
| CAPEX initial | 8 000 € (3e nœud + stockage NAS imagerie) | 0 € |
| OPEX mensuel | 200 €/mois (électricité, maintenance) | 800–1 200 €/mois (VM + stockage DICOM) |
| Certification HDS | Coût de certification élevé (inaccessible PME) | Incluse chez l'hébergeur |
| TCO 5 ans estimé | **20 000 €** | **60 000 €** |
| Risque | Conformité HDS on-prem difficile | Dépendance cloud, latence DICOM |

**Recommandation** : si volume imagerie < 50 examens/semaine, on-prem reste pertinent financièrement mais nécessite un partenariat avec un hébergeur HDS pour la conformité. Au-delà : cloud HDS justifié.

---

**D2 — Coût de la certification HDS si extension à l'imagerie réglementée**

> Si MEDISOL obtient la certification HDS pour son infrastructure on-prem, quel est le coût réel ?

**Réponse préparée :** La certification HDS (arrêté du 26 février 2018) est délivrée par des organismes accrédités COFRAC (BSI, Bureau Veritas, etc.). Coûts indicatifs :
- **Audit initial** : 15 000–30 000 € selon la taille de l'infrastructure
- **Certification annuelle** (surveillance) : 8 000–15 000 €/an
- **Mise en conformité préalable** (documentation, SMSI, procédures) : 20 000–50 000 € en accompagnement conseil

**Conclusion** : pour 32 utilisateurs et une PME santé, la certification HDS directe est économiquement disproportionnée. La voie recommandée est l'hébergement dans un cloud ou datacenter déjà certifié HDS.

---

**D3 — Abonnement PBS Support Proxmox : justification pour MEDISOL**

> Proxmox Backup Server est open-source et gratuit. L'abonnement support (Enterprise Repository) coûte environ 300–600 €/an par nœud. Est-il justifié pour MEDISOL ?

**Réponse préparée :** L'abonnement PBS Support donne accès au **dépôt Enterprise** (patchs de sécurité stables avant le dépôt No-Subscription), au **support technique officiel Proxmox**, et est requis pour certains organismes d'audit. Pour MEDISOL :
- **Argument pour** : données de santé → obligation de patchs de sécurité rapides ; support officiel en cas d'incident PBS critique.
- **Argument contre** : le dépôt No-Subscription reçoit les mêmes patchs avec un délai de quelques jours, acceptable pour une structure sans équipe IT dédiée.
- **Recommandation** : abonnement **Community** (150 €/an/nœud) ou au minimum mise en place d'une procédure de surveillance des CVE PBS (flux RSS advisories Proxmox). Pour 2 nœuds : 300 €/an, ROI positif face au risque d'un incident non supporté sur des données patients.

---

## 5.4 Points forts à valoriser à l'entretien

- **Élimination du SPOF imagerie** : migration VM-IMAGERIE sur SRV2 avec HA Proxmox — RTO imagerie passe de 48h à < 5 min, garanti par le runbook de bascule
- **RGPD by design** : segmentation VLAN dès la conception (VLAN 10 praticiens isolé de VLAN 30 serveurs), logs multi-couches (RDS + OPNsense + PBS), pas de données patients sur les postes locaux
- **Hybride pragmatique M365 + on-prem** : messagerie et productivité dans le cloud Microsoft, données patients et imagerie sur infrastructure physique maîtrisée — séparation claire des périmètres RGPD
- **3-2-1 complet adapté santé** : PBS local (rétention 30 jours, déduplication), Azure Backup hors site (région France), rotation mensuelle disque externe hors site — résilience prouvée contre ransomware
- **WireGuard + MFA Entra ID** : accès distant praticiens sécurisé sans VPN legacy (OpenVPN/IPSec) — révocation d'accès en < 2 min, authentification forte systématique, aligné prérequis assureurs cyber
- **Évolutivité cabinet secondaire sans refonte** : architecture prévoit dès le départ un 3e nœud Proxmox sur site secondaire + tunnel WireGuard site-à-site — l'ouverture d'un 2e cabinet est une opération de 2 semaines, pas un projet de 6 mois

---

## 5.5 Bibliographie et ressources complémentaires

| Ressource | Référence |
|---|---|
| Documentation officielle Proxmox VE | https://pve.proxmox.com/wiki/Main_Page |
| Proxmox Backup Server — Guide administrateur | https://pbs.proxmox.com/docs/index.html |
| Proxmox — Corosync QDevice | https://pve.proxmox.com/wiki/Cluster_Manager#_corosync_external_vote_support |
| WireGuard — Protocole et spécification | https://www.wireguard.com/papers/wireguard.pdf |
| OPNsense Documentation | https://docs.opnsense.org/ |
| CNIL — Guide pratique RGPD pour les professions de santé | https://www.cnil.fr/fr/les-bases-legales/les-conditions-du-traitement-des-donnees-de-sante |
| Certification HDS — Arrêté du 26 février 2018 | https://www.legifrance.gouv.fr/loda/id/JORFTEXT000036637587 |
| ANS — Référentiel HDS (Agence du Numérique en Santé) | https://esante.gouv.fr/produits-services/hds |
| ANSSI — Guide hygiène informatique v2 | ANSSI-GP-078 — https://www.ssi.gouv.fr/guide/guide-dhygiene-informatique/ |
| Code de la santé publique — Art. R. 1112-7 (conservation dossier médical) | https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000006912232 |
| Azure Backup — Documentation Microsoft | https://learn.microsoft.com/fr-fr/azure/backup/ |
| Microsoft — Avenant HDS Azure (Hébergeur de Données de Santé) | https://aka.ms/healthdataprotectionaddendum |
| NIST SP 800-34 — Guide PRA | https://csrc.nist.gov/publications/detail/sp/800-34/rev-1/final |
