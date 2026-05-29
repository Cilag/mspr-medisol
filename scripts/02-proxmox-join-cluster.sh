#!/usr/bin/env bash
# 02-proxmox-join-cluster.sh — SRV2 : rejoindre le cluster Proxmox existant
# Projet MSPR Virtualisation M1 INFRA — MEDISOL Clinique Bien-Être (données fictives)
set -euo pipefail

# ─── Variables de configuration ───────────────────────────────────────────────
HOSTNAME_SRV2="pve-medisol-02.local"
IP_SRV2="10.0.30.12"
IP_SRV1="10.0.30.11"          # IP du nœud primaire à rejoindre

# Disques ZFS sur SRV2 (adapter selon inventaire matériel réel)
ZFS_DISKS="/dev/sdb /dev/sdc /dev/sdd /dev/sde"
ZFS_POOL="vmdata"

# ─── 1. Mise à jour et dépôts (même procédure que SRV1) ───────────────────────
echo "[1/4] Configuration des dépôts APT Proxmox..."
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list

if [ -f /etc/apt/sources.list.d/ceph.list ]; then
  sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list
fi

apt-get update -q && apt-get dist-upgrade -y

# ─── 2. Création du pool ZFS sur SRV2 ─────────────────────────────────────────
echo "[2/4] Création du pool ZFS RAIDZ sur SRV2 ($ZFS_POOL)..."
for disk in $ZFS_DISKS; do
  if [ ! -b "$disk" ]; then
    echo "ERREUR : disque $disk introuvable. Adapter la variable ZFS_DISKS." >&2
    exit 1
  fi
done

zpool create -f "$ZFS_POOL" raidz $ZFS_DISKS
zfs set compression=lz4 "$ZFS_POOL"
zfs set atime=off "$ZFS_POOL"

pvesm add zfspool vmdata-pool \
  --pool "$ZFS_POOL" \
  --content images,rootdir

# ─── 3. Rejoindre le cluster (SRV1 doit être en ligne) ────────────────────────
echo "[3/4] Jonction au cluster (SRV1 = $IP_SRV1)..."
echo "ATTENTION : le mot de passe root de SRV1 va être demandé."
pvecm add "$IP_SRV1"

# ─── 4. Vérification ──────────────────────────────────────────────────────────
echo "[4/4] Vérification du statut cluster..."
pvecm status
pvecm nodes

echo ""
echo "✓ SRV2 intégré au cluster — vérifier la réplication ZFS dans Proxmox UI."
