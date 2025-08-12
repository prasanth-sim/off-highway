#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === INPUT ARGUMENTS ===
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/qwertyu}"
REPO="spriced-platform-data-management-layer"

DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Dynamic Paths ===
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_BASE="$BASE_DIR/builds/$REPO"
LOG_DIR="$BASE_DIR/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"
GIT_URL="https://github.com/simaiserver/$REPO.git"

mkdir -p "$REPO_DIR" "$BUILD_BASE" "$LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "🚀 Starting build for [$REPO] on branch [$BRANCH]"

# === Clone or Update Repository ===
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "🔁 Updating existing repo at $REPO_DIR"
    cd "$REPO_DIR"
    git fetch origin
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
else
    echo "📥 Cloning repo to $REPO_DIR"
    git clone "$GIT_URL" "$REPO_DIR"
    cd "$REPO_DIR"
    git checkout "$BRANCH"
fi

# === Build Project ===
echo "🔨 Running Maven build..."
mvn clean install -Dmaven.test.skip=true

# === Artifact Copy ===
BUILD_DIR="$BUILD_BASE/${BRANCH//\//_}_${DATE_TAG}"
mkdir -p "$BUILD_DIR"

echo "📦 Searching for and copying built JARs to [$BUILD_DIR]..."
find "$REPO_DIR" -type f -path "*/target/transaction-management-0.0.1-SNAPSHOT.jar" -exec cp -v {} "$BUILD_DIR/" \;

# === Update 'latest' Symlink ===
echo "🔗 Updating 'latest' symlink..."
ln -sfn "$BUILD_DIR" "$BUILD_BASE/latest"

# === Done ===
echo "✅ Build complete for [$REPO] on branch [$BRANCH]"
echo "🗂️ Artifacts stored at: $BUILD_DIR"
echo "🔗 Latest symlink: $BUILD_BASE/latest"
