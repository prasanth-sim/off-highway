#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Inputs ===
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/qwertyu}"
CONFIG="${3:-development}"

REPO="dvm_visualization_tool"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")

# === Derived Paths ===
REPO_DIR="$BASE_DIR/repos/$REPO"
BUILD_DIR="$BASE_DIR/builds/$REPO/${BRANCH//\//_}_$DATE_TAG"
LATEST_LINK="$BASE_DIR/builds/$REPO/latest"
LOG_DIR="$BASE_DIR/automationlogs"
LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"
GIT_URL="https://github.com/simaiserver/dvm_visualization_tool.git"

# --- Setup Directories ---
mkdir -p "$LOG_DIR" "$BUILD_DIR"

# --- Redirect Output to Log File ---
exec &> >(tee -a "$LOG_FILE")

echo "🔧 Starting build for [$REPO] on branch [$BRANCH] with configuration [$CONFIG]..."
echo "📅 Timestamp: $DATE_TAG"

# === Git Clone or Pull ===
if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "🚀 Cloning repository from $GIT_URL..."
    git clone "$GIT_URL" "$REPO_DIR"
else
    echo "🔄 Repository already exists. Fetching latest changes..."
    cd "$REPO_DIR"
    git fetch origin
fi

# === Branch Checkout and Update ===
cd "$REPO_DIR"
echo "🌐 Attempting to checkout branch [$BRANCH]..."

if ! git ls-remote --exit-code origin "$BRANCH" > /dev/null; then
    echo "[❌ ERROR] Remote branch 'origin/$BRANCH' does not exist."
    exit 1
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git checkout "$BRANCH"
    echo "⬇️ Pulling latest changes from origin/$BRANCH..."
    git pull origin "$BRANCH"
else
    echo "🆕 Branch '$BRANCH' not found locally. Creating and checking out from 'origin/$BRANCH'..."
    git checkout -b "$BRANCH" "origin/$BRANCH"
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "$BRANCH" ]]; then
    echo "✅ Successfully checked out branch: $BRANCH"
else
    echo "⚠️ Warning: The branch checkout may have failed. Current branch is '$CURRENT_BRANCH', but expected '$BRANCH'."
fi

# === Build Process ===
echo "🔨 Building project in: $REPO_DIR"
echo "📦 Installing npm dependencies..."
npm install

echo "🛠️ Starting Angular build for project 'my-app'..."
# The --project flag specifies which project to build in a multi-project workspace
ng build my-app --output-path="$BUILD_DIR" --configuration="$CONFIG"

# === Create/Update Symlink ===
echo "🔗 Updating 'latest' symlink to point to the new build..."
ln -snf "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build complete for [$REPO] on branch [$BRANCH] with configuration [$CONFIG]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
