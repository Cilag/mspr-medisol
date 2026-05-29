#!/usr/bin/env bash
# 08-wireguard-peer-gen.sh — Génération des clés et profils WireGuard par praticien
# Projet MSPR Virtualisation M1 INFRA — MEDISOL Clinique Bien-Être (données fictives)
# Prérequis : wireguard-tools installé (apt install wireguard-tools)
set -euo pipefail

# ─── Variables de configuration ───────────────────────────────────────────────
SERVER_ENDPOINT="vpn.medisol.fr:51820"   # IP/FQDN public de l'OPNsense + port WireGuard
SERVER_PUBKEY_FILE="/etc/wireguard/server_pub.key"  # clé publique du serveur (présente sur OPNsense)
WG_NETWORK="10.200.0"                   # réseau WireGuard (CIDR /24)
WG_SERVER_IP="10.200.0.1"               # IP serveur WireGuard (OPNsense)
DNS_SERVER="10.0.30.1"                  # DNS interne (OPNsense VLAN Serveurs)
ALLOWED_IPS="10.0.10.0/24"             # accès limité à VLAN 10 (VM-PATIENT uniquement)
OUTPUT_DIR="./wg-peers"                 # dossier de sortie pour les profils

# Liste des praticiens (prénom.nom) — adapter selon l'effectif réel
PRATICIENS=(
  "dr.martin"
  "dr.leroy"
  "dr.bernard"
)

# ─── Vérification des prérequis ───────────────────────────────────────────────
if ! command -v wg &> /dev/null; then
  echo "ERREUR : wireguard-tools non installé. Exécuter : apt install wireguard-tools" >&2
  exit 1
fi

if [ ! -f "$SERVER_PUBKEY_FILE" ]; then
  echo "ERREUR : clé publique serveur introuvable : $SERVER_PUBKEY_FILE" >&2
  echo "  Copier la clé publique WireGuard de l'OPNsense dans ce fichier." >&2
  exit 1
fi

SERVER_PUBKEY=$(cat "$SERVER_PUBKEY_FILE")
mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

# ─── Génération des clés et profils ───────────────────────────────────────────
echo "Génération des profils WireGuard pour ${#PRATICIENS[@]} praticiens..."
echo ""

PEER_INDEX=10   # attribution des IPs : 10.200.0.10, .11, .12, ...

for PRATICIEN in "${PRATICIENS[@]}"; do
  IP_SUFFIX=$PEER_INDEX
  PEER_IP="${WG_NETWORK}.${IP_SUFFIX}"
  PRIVKEY_FILE="$OUTPUT_DIR/${PRATICIEN}.privkey"
  PUBKEY_FILE="$OUTPUT_DIR/${PRATICIEN}.pubkey"
  CONF_FILE="$OUTPUT_DIR/${PRATICIEN}.conf"
  QR_FILE="$OUTPUT_DIR/${PRATICIEN}.png"

  # Générer la paire de clés
  wg genkey | tee "$PRIVKEY_FILE" | wg pubkey > "$PUBKEY_FILE"
  chmod 600 "$PRIVKEY_FILE"

  PRIVKEY=$(cat "$PRIVKEY_FILE")
  PUBKEY=$(cat "$PUBKEY_FILE")

  # Générer le profil .conf pour l'import sur poste ou mobile
  cat > "$CONF_FILE" << EOF
[Interface]
# Praticien : ${PRATICIEN}
# Adresse WireGuard : ${PEER_IP}/32
PrivateKey = ${PRIVKEY}
Address = ${PEER_IP}/32
DNS = ${DNS_SERVER}

[Peer]
# Serveur WireGuard OPNsense — MEDISOL
PublicKey = ${SERVER_PUBKEY}
Endpoint = ${SERVER_ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = 25
EOF
  chmod 600 "$CONF_FILE"

  # Générer le QR code si qrencode est disponible
  if command -v qrencode &> /dev/null; then
    qrencode -t PNG -o "$QR_FILE" < "$CONF_FILE"
    echo "  [${PRATICIEN}] IP: ${PEER_IP} | Profil: $CONF_FILE | QR: $QR_FILE"
  else
    echo "  [${PRATICIEN}] IP: ${PEER_IP} | Profil: $CONF_FILE"
    echo "    (qrencode non disponible — installer avec : apt install qrencode)"
  fi

  # Afficher le bloc Peer à ajouter dans la config OPNsense
  echo ""
  echo "  ── Ajouter dans OPNsense (VPN → WireGuard → Peers) ──"
  echo "  [Peer]"
  echo "  PublicKey = ${PUBKEY}"
  echo "  AllowedIPs = ${PEER_IP}/32"
  echo "  ──────────────────────────────────────────────────────"
  echo ""

  PEER_INDEX=$(( PEER_INDEX + 1 ))
done

echo "✓ Profils générés dans : $OUTPUT_DIR"
echo ""
echo "Étapes suivantes :"
echo "  1. Ajouter chaque bloc [Peer] dans OPNsense (VPN → WireGuard → Peers)."
echo "  2. Activer l'interface wg0 sur OPNsense."
echo "  3. Configurer la règle OPNsense : WireGuard → VLAN 10, port TCP 3389 uniquement."
echo "  4. Remettre le fichier .conf ou QR au praticien concerné (canal sécurisé)."
echo "  5. Supprimer les fichiers .privkey du serveur une fois le profil remis."
echo "  6. Activer MFA Entra ID (Conditional Access) avant mise en production."
