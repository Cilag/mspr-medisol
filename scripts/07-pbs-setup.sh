#!/usr/bin/env bash
# 07-pbs-setup.sh — PBS : création datastore + installation agent Azure Backup
# Projet MSPR Virtualisation M1 INFRA — MEDISOL Clinique Bien-Être (données fictives)
# Prérequis : Proxmox Backup Server installé, accès Internet pour l'agent Azure
set -euo pipefail

# ─── Variables de configuration ───────────────────────────────────────────────
DATASTORE_NAME="medisol-backup"
DATASTORE_PATH="/var/backups/medisol"

# Planification PBS (format cron simplifié Proxmox)
BACKUP_SCHEDULE="23:00"    # heure de déclenchement quotidien
BACKUP_KEEP_DAILY=30       # rétention en jours

# Azure Backup (MARS agent) — données fictives
AZURE_VAULT_NAME="vault-medisol-backup"        # nom du coffre Recovery Services (fictif)
AZURE_PASSPHRASE_FILE="/root/.mars-passphrase" # stockée hors ligne, ne pas versionner

# ─── 1. Création du répertoire et du datastore PBS ────────────────────────────
echo "[1/4] Création du datastore PBS ($DATASTORE_NAME)..."
mkdir -p "$DATASTORE_PATH"
chmod 750 "$DATASTORE_PATH"

# Créer le datastore via l'API PBS
proxmox-backup-manager datastore create "$DATASTORE_NAME" "$DATASTORE_PATH"

# Configurer la rétention
proxmox-backup-manager datastore update "$DATASTORE_NAME" \
  --keep-daily "$BACKUP_KEEP_DAILY" \
  --gc-schedule "daily"

echo "  Datastore '$DATASTORE_NAME' créé dans $DATASTORE_PATH"
echo "  Rétention : $BACKUP_KEEP_DAILY jours"

# ─── 2. Vérification de l'état PBS ────────────────────────────────────────────
echo "[2/4] Vérification du service PBS..."
systemctl status proxmox-backup --no-pager || true
proxmox-backup-manager datastore list

# ─── 3. Installation de l'agent Azure Backup (MARS) ──────────────────────────
echo "[3/4] Téléchargement et installation de l'agent Azure Backup (MARS)..."
MARS_INSTALLER="/tmp/MARSagentinstaller.run"

wget -q "https://aka.ms/installazurebackupagentupdates" -O "$MARS_INSTALLER"
chmod +x "$MARS_INSTALLER"
"$MARS_INSTALLER" --quiet

echo "  Agent MARS installé."

# ─── 4. Instructions post-installation ───────────────────────────────────────
echo "[4/4] Configuration manuelle requise dans l'interface Azure :"
echo ""
echo "  1. Ouvrir le Recovery Services Vault '$AZURE_VAULT_NAME' dans le portail Azure."
echo "  2. Télécharger les credentials du coffre (fichier .VaultCredentials)."
echo "  3. Enregistrer ce serveur avec la commande :"
echo "       /usr/bin/MARSAgentInstaller --register -av /tmp/<vault-creds>.VaultCredentials"
echo "  4. Définir la passphrase de chiffrement (stocker dans $AZURE_PASSPHRASE_FILE, hors ligne)."
echo "  5. Configurer la politique :"
echo "       - Planification : mardi et vendredi à 02h00"
echo "       - Rétention : 12 mois"
echo "       - Chiffrement : passphrase choisie ci-dessus"
echo ""
echo "  ATTENTION : la passphrase ne peut pas être récupérée depuis Azure en cas de perte."
echo "  La stocker dans le gestionnaire de secrets hors ligne du projet MEDISOL."
echo ""
echo "✓ PBS prêt. Configurer ensuite les jobs de sauvegarde dans Proxmox UI :"
echo "  Datacenter → Backup → Add → Schedule: $BACKUP_SCHEDULE, Mode: Snapshot"
echo "  Storage: $DATASTORE_NAME, Compression: ZSTD, Keep-Daily: $BACKUP_KEEP_DAILY"
