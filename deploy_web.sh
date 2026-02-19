#!/bin/bash
set -e

REMOTE_HOST="euro"
REMOTE_DIR="/var/www/dipreport.com"
BUILD_DIR="build/web"

echo "🚀 Starting deployment to $REMOTE_HOST..."

# 1. Build Flutter Web
echo "📦 Building Flutter web..."
/home/david/flutter/bin/flutter build web --release

# 2. Replace Flutter's generated service worker with ours
# Flutter's SW aggressively caches everything and causes stale deploys.
# We overwrite it with our own sw.js which never caches entry points.
echo "🔧 Replacing Flutter service worker..."
cp web/sw.js "$BUILD_DIR/flutter_service_worker.js"
cp web/sw.js "$BUILD_DIR/sw.js"

# 3. Deploy static files
echo "📤 Transferring files to $REMOTE_HOST:$REMOTE_DIR..."
ssh $REMOTE_HOST "sudo mkdir -p $REMOTE_DIR && sudo chown -R \$USER $REMOTE_DIR"
rsync -avz --delete "$BUILD_DIR/" "$REMOTE_HOST:$REMOTE_DIR/"

# 3. Push nginx config and reload
echo "🔧 Updating nginx config..."
scp dipreport.nginx $REMOTE_HOST:/tmp/dipreport.nginx
ssh $REMOTE_HOST "sudo cp /tmp/dipreport.nginx /etc/nginx/sites-available/dipreport.com && sudo nginx -t && sudo systemctl reload nginx"

echo "✅ Deployment complete!"
echo "🌐 Visit https://dipreport.com"
