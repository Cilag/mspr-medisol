#!/usr/bin/env bash
# 01-proxmox-setup.sh — Configuration post-install Proxmox VE 8.x (SRV1, nœud primaire)
# Projet MSPR Virtualisation M1 INFRA — MEDISOL Clinique Bien-Être (données fictives)
set -euo pipefail

# ─── Variables de configuration ───────────────────────────────────────────────
HOSTNAME_SRV1="pve-medisol-01.local"
IP_SRV1="10.0.30.11"
NETMASK="24"
GATEWAY="10.0.30.1"
DNS="10.0.30.1"
CLUSTER_NAME="medisol-cluster"

# Disques ZFS (adapter selon inventaire matériel réel)
ZFS_DISKS="/dev/sdb /dev/sdc /dev/sdd /dev/sde"
ZFS_POOL="vmdata"

# ─── 1. Désactiver le repo entreprise, activer no-subscription ─────────────────
echo "[1/5] Configuration des dépôts APT Proxmox..."
sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-no-subscription.list

# Désactiver le repo ceph enterprise si présent
if [ -f /etc/apt/sources.list.d/ceph.list ]; then
  sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list
fi

apt-get update -q && apt-get dist-upgrade -y

# ─── 2. Création du pool ZFS RAIDZ ────────────────────────────────────────────
echo "[2/5] Création du pool ZFS RAIDZ ($ZFS_POOL)..."
# Vérifier que les disques existent
for disk in $ZFS_DISKS; do
  if [ ! -b "$disk" ]; then
    echo "ERREUR : disque $disk introuvable. Adapter la variable ZFS_DISKS." >&2
    exit 1
  fi
done

zpool create -f "$ZFS_POOL" raidz $ZFS_DISKS
zfs set compression=lz4 "$ZFS_POOL"
zfs set atime=off "$ZFS_POOL"

echo "[2/5] Pool ZFS créé :"
zpool status "$ZFS_POOL"

# ─── 3. Ajouter le stockage ZFS dans Proxmox ──────────────────────────────────
echo "[3/5] Enregistrement du stockage ZFS dans Proxmox..."
pvesm add zfspool vmdata-pool \
  --pool "$ZFS_POOL" \
  --content images,rootdir

# ─── 4. Création du cluster Proxmox (SRV1 uniquement) ─────────────────────────
echo "[4/5] Création du cluster Proxmox ($CLUSTER_NAME)..."
pvecm create "$CLUSTER_NAME"

echo "[4/5] Statut du cluster :"
pvecm status

# ─── 5. Vérifications finales ──────────────────────────────────────────────────
echo "[5/5] Vérifications..."
echo "  ZFS pool    : $(zpool list "$ZFS_POOL" | tail -1)"
echo "  Cluster     : $(pvecm status | grep 'Cluster name')"
echo "  Stockage PVE: $(pvesm status | grep vmdata-pool)"
echo ""
echo "✓ SRV1 prêt — exécuter 02-proxmox-join-cluster.sh sur SRV2."
