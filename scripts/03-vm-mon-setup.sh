#!/usr/bin/env bash
# 03-vm-mon-setup.sh — VM-MON : Netdata + Grafana + Prometheus (supervision)
# Projet MSPR Virtualisation M1 INFRA — MEDISOL Clinique Bien-Être (données fictives)
# Prérequis : Debian/Ubuntu, accès Internet, VM sur VLAN 30
set -euo pipefail

# ─── Variables de configuration ───────────────────────────────────────────────
IP_SRV1="10.0.30.11"
IP_SRV2="10.0.30.12"
IP_VM_PATIENT="10.0.30.21"
IP_VM_IMAGERIE="10.0.30.22"

GRAFANA_ADMIN_PASS="ChangeMe_MEDISOL2024!"   # à remplacer avant déploiement

# ─── 1. Mise à jour système ────────────────────────────────────────────────────
echo "[1/5] Mise à jour système..."
apt-get update -q && apt-get upgrade -y
apt-get install -y curl wget apt-transport-https software-properties-common gnupg

# ─── 2. Installation Netdata ───────────────────────────────────────────────────
echo "[2/5] Installation Netdata..."
curl -fsSL https://my-netdata.io/kickstart.sh -o /tmp/netdata-install.sh
bash /tmp/netdata-install.sh --non-interactive --stable-channel
rm /tmp/netdata-install.sh

systemctl enable netdata
systemctl start netdata
echo "  Netdata écoute sur :19999"

# ─── 3. Installation Prometheus ───────────────────────────────────────────────
echo "[3/5] Installation Prometheus..."
apt-get install -y prometheus

# Configuration scrape : nœuds Proxmox + VMs
cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 30s
  evaluation_interval: 30s

rule_files: []

scrape_configs:
  - job_name: 'prometheus-self'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'proxmox-nodes'
    static_configs:
      - targets: ['${IP_SRV1}:9090', '${IP_SRV2}:9090']
    metrics_path: '/metrics'

  - job_name: 'netdata-vms'
    static_configs:
      - targets:
          - '${IP_VM_PATIENT}:19999'
          - '${IP_VM_IMAGERIE}:19999'
    metrics_path: '/api/v1/allmetrics'
    params:
      format: ['prometheus']
EOF

systemctl enable prometheus
systemctl restart prometheus
echo "  Prometheus écoute sur :9090"

# ─── 4. Installation Grafana ───────────────────────────────────────────────────
echo "[4/5] Installation Grafana..."
wget -qO- https://apt.grafana.com/gpg.key | gpg --dearmor > /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  > /etc/apt/sources.list.d/grafana.list
apt-get update -q && apt-get install -y grafana

# Définir le mot de passe admin
grafana-cli admin reset-admin-password "$GRAFANA_ADMIN_PASS" 2>/dev/null || true

systemctl enable grafana-server
systemctl start grafana-server
echo "  Grafana écoute sur :3000 (admin / $GRAFANA_ADMIN_PASS)"

# ─── 5. Configuration réception syslog IDS (Suricata/OPNsense) ───────────────
echo "[5/5] Configuration rsyslog pour réception logs IDS OPNsense..."
apt-get install -y rsyslog

cat > /etc/rsyslog.d/49-opnsense-ids.conf << 'EOF'
# Réception syslog IDS Suricata depuis OPNsense (UDP 514)
module(load="imudp")
input(type="imudp" port="514")

if $fromhost-ip startswith "10.0.30." then {
    action(type="omfile" file="/var/log/ids-opnsense.log")
    stop
}
EOF

systemctl restart rsyslog

echo ""
echo "✓ VM-MON prête. Accès Grafana : http://$(hostname -I | awk '{print $1}'):3000"
echo "  Configurer la datasource Prometheus (http://localhost:9090) dans Grafana UI."
