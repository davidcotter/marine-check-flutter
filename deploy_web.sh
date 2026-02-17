#!/bin/bash
set -e

# Configuration
REMOTE_HOST="euro"
REMOTE_DIR="/var/www/dipreport.com"
BUILD_DIR="build/web"

echo "🚀 Starting deployment to $REMOTE_HOST..."

# 1. Build Flutter Web
echo "📦 Building Flutter web..."
/home/david/flutter/bin/flutter build web --release

# 2. Deploy to Server
echo "📤 Transferring files to $REMOTE_HOST:$REMOTE_DIR..."
# Ensure remote directory exists
ssh $REMOTE_HOST "sudo mkdir -p $REMOTE_DIR && sudo chown -R \$USER $REMOTE_DIR"

# Using rsync to transfer and clean up old files
rsync -avz --delete "$BUILD_DIR/" "$REMOTE_HOST:$REMOTE_DIR/"

echo "✅ Deployment complete!"
echo "🌐 Visit https://dipreport.com"
