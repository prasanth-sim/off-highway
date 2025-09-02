#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="[env-setup]"
ENV_FILE="$SCRIPT_DIR/.env"
GIT_CREDENTIALS_FILE="$SCRIPT_DIR/.git-credentials"

log() { echo "$LOG_PREFIX $(date +'%F %T') $*"; }

log "🔧 Updating package list..."
sudo apt-get update -y

log "📦 Installing Git, curl, unzip, and essential tools..."
sudo apt-get install -y git curl unzip software-properties-common jq

log "☕ Installing OpenJDK 17..."
sudo apt-get install -y openjdk-17-jdk

log "🛠️ Installing Maven..."
sudo apt-get install -y maven

log "🟩 Installing Node.js 18.x, npm 8.x, and Angular CLI 13.x..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g npm@8.19.4
sudo npm install -g @angular/cli@13.3.11

log "⚙️ Installing GNU Parallel..."
sudo apt-get install -y parallel

log "🔐 Clearing old Git credentials..."
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

log "🔍 Verifying tool versions..."

EXPECTED_JAVA="17"
EXPECTED_MAVEN="3.8.7"
EXPECTED_NODE="18"
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
NODE_VERSION_FULL=$(node -v | sed 's/^v//')
NODE_VERSION_MAJOR=$(echo "$NODE_VERSION_FULL" | cut -d. -f1)
NPM_VERSION=$(npm -v | cut -d. -f1)
NG_VERSION=$(ng version 2>&1 | awk '/Angular CLI/ {print $3}' | cut -d. -f1)
GIT_VERSION=$(git --version | awk '{print $3}' | cut -d. -f1)
PARALLEL_VERSION=$(parallel --version 2>&1 | head -n 1 | awk '{print $3}' || echo "Not Found")

check_version "Java" "$JAVA_VERSION" "$EXPECTED_JAVA"
check_version "Maven" "$MAVEN_VERSION" "$EXPECTED_MAVEN"
check_version "Node.js major" "$NODE_VERSION_MAJOR" "$EXPECTED_NODE"
check_version "npm" "$NPM_VERSION" "$EXPECTED_NPM"
check_version "Angular CLI" "$NG_VERSION" "$EXPECTED_NG"
check_version "Git" "$GIT_VERSION" "$EXPECTED_GIT"
check_version "GNU Parallel" "$PARALLEL_VERSION" "$EXPECTED_PARALLEL"

MIN_NODE_VERSION="18.15.0"
version_greater_equal() {
    printf '%s\n%s\n' "$1" "$2" | sort -C -V
}
if ! version_greater_equal "$NODE_VERSION_FULL" "$MIN_NODE_VERSION"; then
    log "[❌ ERROR] Node.js version too old. Require v$MIN_NODE_VERSION or newer."
    log "Detected version: $NODE_VERSION_FULL"
    exit 1
fi
log "✅ Node.js version $NODE_VERSION_FULL meets minimum requirement."

log "✅ Environment setup completed successfully."
