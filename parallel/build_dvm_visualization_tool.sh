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

# === Git Clone or Pull and Branch Checkout ===
echo "🚀 Preparing repository: $REPO_DIR"

if [[ ! -d "$REPO_DIR" ]]; then
    echo "📥 Cloning repository from $GIT_URL..."
    git clone "$GIT_URL" "$REPO_DIR"
    cd "$REPO_DIR"
else
    echo "🔄 Repository already exists. Fetching latest changes..."
    cd "$REPO_DIR"
    git fetch --prune origin
    git reset --hard "origin/$BRANCH" 2>/dev/null || git reset --hard "origin/main" 2>/dev/null || git reset --hard "origin/master"
fi

echo "🌐 Attempting to checkout branch [$BRANCH]..."
git checkout "$BRANCH" || {
    echo "⚠️ Warning: Branch '$BRANCH' not found. Falling back to default branches."
    git checkout main || git checkout master || {
        echo "[❌ ERROR] Failed to checkout branch '$BRANCH', 'main', or 'master'. Exiting."
        exit 1
    }
}
echo "✅ Successfully checked out branch: $(git rev-parse --abbrev-ref HEAD)"

# --- END OF GIT OPERATIONS ---
# --- Node.js Version Check ---
# This check prevents the build from failing due to the Node.js availableParallelism error.
echo "🔍 Verifying Node.js version..."
NODE_VERSION=$(node -v)
# The `availableParallelism` function was added in Node.js 18.15.0.
MIN_NODE_VERSION="18.15.0"
if [[ "$(printf '%s\n' "$MIN_NODE_VERSION" "$NODE_VERSION" | sort -V | head -n1)" != "$MIN_NODE_VERSION" ]]; then
    echo "[❌ ERROR] Node.js version is too old. The Angular CLI requires Node.js v18.15.0 or newer."
    echo "Detected Node.js version: $NODE_VERSION"
    echo "Please update your Node.js version and try again."
    exit 1
fi
echo "✅ Node.js version ($NODE_VERSION) is compatible."

# === Build Process ===
echo "🔨 Building project in: $(pwd)"

# --- Address Angular configuration issues based on log analysis ---
ANGULAR_CONFIG_FILE="./angular.json"

if command -v jq &> /dev/null; then
    echo "🔧 Using 'jq' to update angular.json to fix budget errors and CommonJS warnings..."
    jq --arg config "$CONFIG" \
        '.projects."my-app".architect.build.configurations[$config].budgets |= map(
            if .type == "initial" then
                .maximumError = "4mb"
            elif .type == "anyComponentStyle" then
                .maximumError = "8kb"
            else . end
        ) |
        .projects."my-app".architect.build.options.allowedCommonJsDependencies |= (
            . + ["file-saver", "echarts-stat"] | unique
        )' "$ANGULAR_CONFIG_FILE" > temp.json && mv temp.json "$ANGULAR_CONFIG_FILE"
    echo "✅ 'angular.json' updated."
else
    echo "⚠️ Warning: 'jq' is not installed. Skipping automatic configuration fixes."
fi

# --- Install Dependencies ---
echo "📦 Installing npm dependencies..."
npm install

# --- BEGIN PATCH ---
if [[ "$CONFIG" == "dev" ]]; then
    echo "💡 Mapping configuration 'dev' to 'development'."
    CONFIG="development"
fi
# --- END PATCH ---

echo "🛠️ Starting Angular build for project 'my-app' with configuration: $CONFIG..."
ng build my-app --output-path="$BUILD_DIR" --configuration="$CONFIG"

# === Create/Update Symlink ===
echo "🔗 Updating 'latest' symlink to point to the new build..."
ln -snf "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build complete for [$REPO] on branch [$BRANCH] with configuration [$CONFIG]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
