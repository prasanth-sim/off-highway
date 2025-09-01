#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Script Context ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[env-setup]"
ENV_FILE="$SCRIPT_DIR/.env"
GIT_CREDENTIALS_FILE="$SCRIPT_DIR/.git-credentials"

log() { echo "$LOG_PREFIX $(date +'%F %T') $*"; }

# === Install Tools ===
log "🔧 Updating package list..."
sudo apt-get update -y

log "📦 Installing Git, curl, unzip, and essential tools..."
sudo apt-get install -y git curl unzip software-properties-common jq

log "☕ Installing OpenJDK 17..."
sudo apt-get install -y openjdk-17-jdk

log "🛠️ Installing Maven..."
sudo apt-get install -y maven

# Changed back to Node.js 16.x
log "🟩 Installing Node.js 16.x, npm 8.x, and Angular CLI 13.x..."
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g npm@8.19.4
sudo npm install -g @angular/cli@13.3.11

log "⚙️ Installing GNU Parallel..."
sudo apt-get install -y parallel

# ---

### **Git and Environment Setup**

log "🔐 Clearing old Git credentials to prevent authentication failures..."
rm -f "$ENV_FILE" "$GIT_CREDENTIALS_FILE"
git config --global --unset-all credential.helper || true

log "📝 Setting up .env file for Git credentials..."
read -p "🔐 Enter GitHub username: " GIT_USERNAME
read -s -p "🔑 Enter GitHub personal access token (PAT): " GIT_TOKEN
echo
echo "GIT_USERNAME=$GIT_USERNAME" > "$ENV_FILE"
echo "GIT_TOKEN=$GIT_TOKEN" >> "$ENV_FILE"
chmod 600 "$ENV_FILE"
log "✅ .env file created at $ENV_FILE"

source "$ENV_FILE"

if [[ -z "${GIT_USERNAME:-}" || -z "${GIT_TOKEN:-}" ]]; then
  log "❌ Missing GitHub credentials. Please set GIT_USERNAME and GIT_TOKEN in $ENV_FILE."
  exit 1
fi

echo "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com" > "$GIT_CREDENTIALS_FILE"
chmod 600 "$GIT_CREDENTIALS_FILE"
git config --global credential.helper "store --file=$GIT_CREDENTIALS_FILE"
git config --global user.name "$GIT_USERNAME"
log "✅ Git configured with credential helper."

# ---

### **Version Checks**

log "🔍 Verifying tool versions..."

# Define expected versions
EXPECTED_JAVA="17"
EXPECTED_MAVEN="3.8.7"
EXPECTED_NODE="16"
EXPECTED_NPM="8"
EXPECTED_NG="13"
EXPECTED_GIT="2"
EXPECTED_PARALLEL="20231122"

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
NODE_VERSION=$(node -v 2>&1 | cut -d. -f1 | tr -d 'v' || echo "Not Found")
NPM_VERSION=$(npm -v 2>&1 | cut -d. -f1 || echo "Not Found")
NG_VERSION=$(ng version 2>&1 | awk '/Angular CLI/ {print $3}' | cut -d. -f1 || echo "Not Found")
GIT_VERSION=$(git --version | awk '{print $3}' | cut -d. -f1)
PARALLEL_VERSION=$(parallel --version 2>&1 | head -n 1 | awk '{print $3}' || echo "Not Found")

check_version "Java" "$JAVA_VERSION" "$EXPECTED_JAVA"
check_version "Maven" "$MAVEN_VERSION" "$EXPECTED_MAVEN"
check_version "Node.js" "$NODE_VERSION" "$EXPECTED_NODE"
check_version "npm" "$NPM_VERSION" "$EXPECTED_NPM"
check_version "Angular CLI" "$NG_VERSION" "$EXPECTED_NG"
check_version "Git" "$GIT_VERSION" "$EXPECTED_GIT"
check_version "GNU Parallel" "$PARALLEL_VERSION" "$EXPECTED_PARALLEL"

log "✅ Environment setup completed successfully."
