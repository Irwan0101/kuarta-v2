#!/bin/bash
set -e

DOMAIN="kuartabimbel.com"
REPO="https://github.com/Irwan0101/kuarta-v2.git"
DIR="/var/www/kuarta-v2"
BACKEND_PORT=5000

echo "=== 1. Update system & install dependencies ==="
apt update && apt install -y nginx git certbot python3-certbot-nginx
npm install -g pm2

echo "=== 2. Clone project ==="
mkdir -p /var/www
[ -d "$DIR" ] || git clone "$REPO" "$DIR"

echo "=== 3. Setup backend ==="
cd "$DIR/kuarta-backend"
cat > .env << 'ENVEOF'
DATABASE_URL=postgresql://neondb_owner:npg_BLImcl16hrZW@ep-lingering-recipe-aondnnyt-pooler.c-2.ap-southeast-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require
JWT_SECRET=cb853fc1b0994a10a6c695c585a38a2264b5a4f7566b3a80058f4aef483eed95672fa77c43c3a6637d818761f35fb40d
JWT_EXPIRES_IN=7d
JWT_REFRESH_SECRET=cb853fc1b0994a10a6c695c585a38a2264b5a4f7566b3a80058f4aef483eed95672fa77c43c3a6637d818761f35fb40d-refresh
JWT_REFRESH_EXPIRES_IN=30d
MIDTRANS_SERVER_KEY=SB-Mid-server-tGjLvQC3RKh_tzNfnTc_KboW
MIDTRANS_CLIENT_KEY=SB-Mid-client-UH38GU_wNZOj-ICK
MIDTRANS_IS_PRODUCTION=false
NODE_ENV=production
FRONTEND_URL=https://${DOMAIN}
SMTP_FROM=noreply@${DOMAIN}
GOOGLE_CLIENT_ID=429953284314-gld0boa59k8usekds2uqka308a9pbrsn.apps.googleusercontent.com
B2_KEY_ID=d2d0bd8d40b3
B2_APP_KEY=0051b08bcf11f9e50aa5d20697e064cf70c93b9cc4
B2_BUCKET=kuarta
BREVO_API_KEY=REPLACED_BREVO_KEY
ENVEOF

npm install
node db/migrate.js 2>/dev/null || true
node db/seed.js 2>/dev/null || true

echo "=== 4. Build frontend ==="
cd "$DIR/kuarta-frontend"
npm install
npm run build

echo "=== 5. Setup Nginx ==="
cat > /etc/nginx/sites-available/${DOMAIN} << NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${DIR}/kuarta-frontend/dist;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    location /uploads/ {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host \$host;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo "=== 6. Start backend with PM2 ==="
cd "$DIR/kuarta-backend"
pm2 delete kuarta-api 2>/dev/null || true
pm2 start server.js --name kuarta-api
pm2 save
pm2 startup

echo "=== 7. SSL Certificate ==="
certbot --nginx -d ${DOMAIN} -d www.${DOMAIN} --non-interactive --agree-tos -m admin@${DOMAIN} || true

echo "=== 8. Firewall ==="
ufw allow 80/tcp 2>/dev/null
ufw allow 443/tcp 2>/dev/null
ufw allow 22/tcp 2>/dev/null
ufw --force enable 2>/dev/null || true

echo ""
echo "=== DEPLOY SELESAI ==="
echo "Akses: https://${DOMAIN}"
