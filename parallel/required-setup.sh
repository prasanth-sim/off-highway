#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[env-setup]"
ENV_FILE="$SCRIPT_DIR/.env"
GIT_CREDENTIALS_FILE="$SCRIPT_DIR/.git-credentials"

log() { echo "$LOG_PREFIX $(date +'%F %T') $*"; }

# === Install Tools ===
log "🔧 Updating package list..."
sudo apt-get update -y

log "📦 Installing Git, curl, unzip..."
sudo apt-get install -y git curl unzip software-properties-common

# Changed from OpenJDK 11 to OpenJDK 17
log "☕ Installing OpenJDK 17..."
sudo apt-get install -y openjdk-17-jdk

# Maven version remains the same
log "🛠️ Installing Maven 3.6.3..."
sudo apt-get install -y maven

# Changed from Node.js 16.x to Node.js 22.x and npm 8 to 10
log "🟩 Installing Node.js 22.18.0 and npm 10.9.3..."
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g npm@10.9.3

# Changed from Angular CLI 13.3.11 to 20.1.4
log "📦 Installing Angular CLI 20.1.4..."
sudo npm install -g @angular/cli@20.1.4

# Removed GNU Parallel installation as it was listed as 'Not installed' in the original request
# log "⚙️ Installing GNU Parallel..."
# sudo apt-get install -y parallel

# === .env setup ===
if [[ ! -f "$ENV_FILE" ]]; then
  read -p "🔐 Enter GitHub username: " GIT_USERNAME
  read -s -p "🔑 Enter GitHub token: " GIT_TOKEN
  echo
  echo "GIT_USERNAME=$GIT_USERNAME" > "$ENV_FILE"
  echo "GIT_TOKEN=$GIT_TOKEN" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
else
  log "ℹ️ .env file already exists."
fi
source "$ENV_FILE"

if [[ -z "${GIT_USERNAME:-}" || -z "${GIT_TOKEN:-}" ]]; then
  log "❌ Missing GitHub credentials."
  exit 1
fi

echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > "$GIT_CREDENTIALS_FILE"
chmod 600 "$GIT_CREDENTIALS_FILE"
git config --global credential.helper "store --file=$GIT_CREDENTIALS_FILE"
git config --global user.name "$GIT_USERNAME"
log "✅ Git configured."

# === Version Checks ===
# Updated expected versions to match the request
EXPECTED_JAVA="17"
EXPECTED_MAVEN="3.6.3"
EXPECTED_NODE="22.18.0"
EXPECTED_NPM="10.9.3"
EXPECTED_NG="20.1.4"
EXPECTED_GIT="2" # Git version 2.25.1 matches this check

check_version() {
  TOOL="$1"; ACTUAL="$2"; EXPECTED="$3"
  if [[ "$ACTUAL" == *"$EXPECTED"* ]]; then
    log "✅ $TOOL version OK: $ACTUAL"
  else
    log "❌ $TOOL version mismatch: found '$ACTUAL', expected '$EXPECTED'"
    exit 1
  fi
}

JAVA_VERSION=$(java -version 2>&1 | awk -F[\".] '/version/ {print $2}')
MAVEN_VERSION=$(mvn -v | awk '/Apache Maven/ {print $3}')
NODE_VERSION=$(node -v | tr -d 'v')
NPM_VERSION=$(npm -v)
NG_VERSION=$(ng version | awk '/Angular CLI/ {print $3}')
GIT_VERSION=$(git --version | awk '{print $3}' | cut -d. -f1)
# Removed GNU Parallel version check

check_version "Java" "$JAVA_VERSION" "$EXPECTED_JAVA"
check_version "Maven" "$MAVEN_VERSION" "$EXPECTED_MAVEN"
check_version "Node.js" "$NODE_VERSION" "$EXPECTED_NODE"
check_version "npm" "$NPM_VERSION" "$EXPECTED_NPM"
check_version "Angular CLI" "$NG_VERSION" "$EXPECTED_NG"
check_version "Git" "$GIT_VERSION" "$EXPECTED_GIT"

log "✅ Environment setup completed successfully."
