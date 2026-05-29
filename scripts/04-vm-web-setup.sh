#!/usr/bin/env bash
# 04-vm-web-setup.sh — VM-WEB : Nginx + Certbot + reverse proxy portail patient (DMZ)
# Projet MSPR Virtualisation M1 INFRA — MEDISOL Clinique Bien-Être (données fictives)
# Prérequis : Debian/Ubuntu, port 80/443 ouverts depuis Internet, DNS rdv.medisol.fr pointant sur cette VM
set -euo pipefail

# ─── Variables de configuration ───────────────────────────────────────────────
DOMAIN="rdv.medisol.fr"              # FQDN public du portail patient (données fictives)
ADMIN_EMAIL="it@medisol.fr"          # Email pour les alertes Let's Encrypt (fictif)
BACKEND_PORT="8080"                  # Port de l'application portail en backend local
APP_UPSTREAM="127.0.0.1"            # Adresse du backend (même VM ou modifier si distant)

# ─── 1. Mise à jour et installation des paquets ───────────────────────────────
echo "[1/4] Installation Nginx + Certbot..."
apt-get update -q && apt-get upgrade -y
apt-get install -y nginx certbot python3-certbot-nginx

# ─── 2. Vhost HTTP initial (nécessaire pour le challenge ACME) ────────────────
echo "[2/4] Création du vhost HTTP initial..."
cat > /etc/nginx/sites-available/"${DOMAIN}" << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    # Racine utilisée par certbot pour le challenge ACME
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

ln -sf /etc/nginx/sites-available/"${DOMAIN}" /etc/nginx/sites-enabled/"${DOMAIN}"
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

# ─── 3. Obtention du certificat TLS Let's Encrypt ────────────────────────────
echo "[3/4] Obtention du certificat TLS pour $DOMAIN..."
certbot certonly \
  --nginx \
  --non-interactive \
  --agree-tos \
  --email "$ADMIN_EMAIL" \
  -d "$DOMAIN"

# ─── 4. Vhost HTTPS final avec reverse proxy ──────────────────────────────────
echo "[4/4] Configuration du vhost HTTPS + reverse proxy..."
cat > /etc/nginx/sites-available/"${DOMAIN}" << EOF
# Redirection HTTP → HTTPS
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

# Portail patient — HTTPS avec reverse proxy
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    location / {
        proxy_pass         http://${APP_UPSTREAM}:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 60s;
    }
}
EOF

nginx -t && systemctl reload nginx

# Renouvellement automatique certbot (cron déjà mis en place par certbot, vérification)
systemctl list-timers | grep certbot || true
certbot renew --dry-run

echo ""
echo "✓ VM-WEB prête. Portail patient : https://${DOMAIN}"
