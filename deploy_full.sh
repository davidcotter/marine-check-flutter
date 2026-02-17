#!/bin/bash
set -e

# Configuration
REMOTE_HOST="euro"
REMOTE_WEB_DIR="/var/www/dipreport.com"
REMOTE_APP_DIR="/opt/dipguide_backend"
LOCAL_BUILD_DIR="build/web"

echo "🚀 Starting full deployment to $REMOTE_HOST..."

# --- 1. Database Setup ---
echo "🗄️ Checking Database..."
ssh $REMOTE_HOST "sudo -u postgres psql -tc \"SELECT 1 FROM pg_database WHERE datname = 'dipguide_backend_prod'\" | grep -q 1 || sudo -u postgres psql -c \"CREATE DATABASE dipguide_backend_prod;\""
ssh $REMOTE_HOST "sudo -u postgres psql -tc \"SELECT 1 FROM pg_roles WHERE rolname = 'dipguide'\" | grep -q 1 || sudo -u postgres psql -c \"CREATE USER dipguide WITH PASSWORD 'dipguide_db_pass'; GRANT ALL PRIVILEGES ON DATABASE dipguide_backend_prod TO dipguide;\""
# Ensure the user has permission to connect
ssh $REMOTE_HOST "sudo -u postgres psql -c \"ALTER DATABASE dipguide_backend_prod OWNER TO dipguide;\""

# --- 2. Backend Build & Deploy ---
echo "🏗️ Building Phoenix Backend..."
cd dipguide_backend
# Generate secret key base if not present locally (though we'll set it on server)
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export MIX_ENV=prod

mix deps.get --only prod
mix compile
# mix assets.deploy # No assets since it's an API backend mostly, but if we had them...
yes | mix phx.gen.release
mix release --overwrite

echo "📤 Uploading Backend..."
ssh $REMOTE_HOST "sudo mkdir -p $REMOTE_APP_DIR"
rsync -avz --delete _build/prod/rel/dipguide_backend/ "$REMOTE_HOST:$REMOTE_APP_DIR/"

echo "⚙️ Configuring Service..."
# Use a stable secret key base (generate once and reuse)
# If you need to regenerate, delete this file and redeploy
SECRET_FILE=".deploy_secret"
if [ -f "$SECRET_FILE" ]; then
  SERVER_SECRET=$(cat "$SECRET_FILE")
else
  SERVER_SECRET=$(mix phx.gen.secret)
  echo "$SERVER_SECRET" > "$SECRET_FILE"
  echo "Generated new SERVER_SECRET and saved to $SECRET_FILE"
fi
DATABASE_URL="ecto://dipguide:dipguide_db_pass@localhost/dipguide_backend_prod"
UPLOAD_DIR="/var/lib/dipguide_backend/uploads"

# Upload service file
cd ..
# Inject secrets locally into a temp file
cp dipguide_backend.service dipguide_backend.service.tmp

# Robust insertion function
inject_env() {
  local key=$1
  local value=$2
  if grep -q "Environment=$key=" dipguide_backend.service.tmp; then
    sed -i "s|^Environment=$key=.*|Environment=$key=$value|" dipguide_backend.service.tmp
  else
    sed -i "/^\[Service\]/a Environment=$key=$value" dipguide_backend.service.tmp
  fi
}

# Load Google OAuth secrets from oauth_secrets.txt if available
if [ -f "oauth_secrets.txt" ]; then
  source oauth_secrets.txt
fi

# Load VAPID keys from vapid_keys.txt if available
if [ -f "vapid_keys.txt" ]; then
  source vapid_keys.txt
fi

# Verify Google OAuth credentials are set
if [ -z "$GOOGLE_CLIENT_ID" ] || [ -z "$GOOGLE_CLIENT_SECRET" ]; then
  echo "WARNING: GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET not set!"
  echo "Google login will not work. Set them in oauth_secrets.txt or environment."
fi

inject_env "SECRET_KEY_BASE" "$SERVER_SECRET"
inject_env "DATABASE_URL" "$DATABASE_URL"
inject_env "PHX_HOST" "dipreport.com"
inject_env "UPLOAD_DIR" "$UPLOAD_DIR"
inject_env "GOOGLE_CLIENT_ID" "$GOOGLE_CLIENT_ID"
inject_env "GOOGLE_CLIENT_SECRET" "$GOOGLE_CLIENT_SECRET"
inject_env "SMTP_SERVER" "$SMTP_SERVER"
inject_env "SMTP_USERNAME" "$SMTP_USERNAME"
inject_env "SMTP_PASSWORD" "$SMTP_PASSWORD"
inject_env "MAIL_FROM" "$MAIL_FROM"
inject_env "VAPID_PUBLIC_KEY" "$VAPID_PUBLIC_KEY"
inject_env "VAPID_PRIVATE_KEY" "$VAPID_PRIVATE_KEY"

scp dipguide_backend.service.tmp "$REMOTE_HOST:/tmp/dipguide_backend.service"
rm dipguide_backend.service.tmp

# Install service and env vars
ssh $REMOTE_HOST "
  sudo mkdir -p $UPLOAD_DIR
  sudo mkdir -p $UPLOAD_DIR/previews
  sudo chown -R root:root $UPLOAD_DIR
  sudo chmod -R 755 $UPLOAD_DIR
  sudo mv /tmp/dipguide_backend.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable dipguide_backend
  sudo systemctl restart dipguide_backend
"

# Run Migrations
echo "📦 Running Migrations..."
ssh $REMOTE_HOST "
  export SECRET_KEY_BASE=$SERVER_SECRET
  export DATABASE_URL=$DATABASE_URL
  export UPLOAD_DIR=$UPLOAD_DIR
  export GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID
  export GOOGLE_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET
  export SMTP_SERVER=$SMTP_SERVER
  export SMTP_USERNAME=$SMTP_USERNAME
  export SMTP_PASSWORD=$SMTP_PASSWORD
  export MAIL_FROM=$MAIL_FROM
  export VAPID_PUBLIC_KEY=$VAPID_PUBLIC_KEY
  export VAPID_PRIVATE_KEY=$VAPID_PRIVATE_KEY
  $REMOTE_APP_DIR/bin/dipguide_backend eval \"DipguideBackend.Release.migrate\"
"

# --- 3. Frontend Build & Deploy ---
echo "📱 Building Flutter Web..."
# Use flutter from PATH or fallback to specific location
if command -v flutter &> /dev/null; then
  flutter build web --release
else
  /home/david/flutter/bin/flutter build web --release
fi

echo "📤 Uploading Frontend..."
ssh $REMOTE_HOST "sudo mkdir -p $REMOTE_WEB_DIR"
rsync -avz --delete build/web/ "$REMOTE_HOST:$REMOTE_WEB_DIR/"

# --- 4. Nginx Configuration ---
echo "🌐 Configuring Nginx..."
scp dipreport.nginx "$REMOTE_HOST:/tmp/dipreport.nginx"
ssh $REMOTE_HOST "
  sudo mv /tmp/dipreport.nginx /etc/nginx/sites-available/dipreport.com
  sudo ln -sf /etc/nginx/sites-available/dipreport.com /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl reload nginx
"

echo "✅ Full Deployment Complete!"
echo "👉 Web: https://dipreport.com"
echo "👉 API: https://dipreport.com/api/auth/user"
