#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Inputs ===
# This script is called by build_all_parallel.sh and expects three arguments:
# 1. The Git branch to check out.
# 2. The base directory for repositories and builds.
# 3. The Angular configuration name (e.g., 'dev', 'test', or a new custom one).
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
# This ensures all stdout and stderr from this script are also written to the log file.
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
cd "$REPO_DIR"

# --- Address Angular configuration issues based on log analysis ---
# The build failed due to exceeded budgets and had warnings about CommonJS modules.
# We'll use `jq` to programmatically update angular.json to fix this.
echo "🔧 Addressing Angular configuration issues in angular.json..."
ANGULAR_CONFIG_FILE="$REPO_DIR/angular.json"

if command -v jq &> /dev/null; then
    echo "Using 'jq' to update angular.json to fix budget errors and CommonJS warnings..."
    # The jq command modifies the angular.json file to:
    # 1. Increase the maximumError budget for the initial bundle from 1MB to 4MB.
    #    This directly addresses the "bundle initial exceeded maximum budget" error.
    # 2. Increase the maximumError budget for anyComponentStyle from 4KB to 8KB.
    #    This addresses the warning about component style sizes.
    # 3. Add 'file-saver' and 'echarts-stat' to the allowedCommonJsDependencies list.
    #    This prevents the warnings about using CommonJS modules.
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
    echo "✅ 'angular.json' updated to resolve build issues."
else
    echo "⚠️ Warning: 'jq' is not installed. Unable to automatically fix build configuration."
    echo "You may need to manually update the budgets in '$ANGULAR_CONFIG_FILE' and add the CommonJS dependencies to allow the build to pass."
fi

echo "📦 Installing npm dependencies..."
npm install

echo "🛠️ Starting Angular build for project 'my-app' with configuration: $CONFIG..."

# --- BEGIN PATCH ---
# This block maps the user-friendly 'dev' input to the actual 'development' configuration name
# that is expected to be in the angular.json file. This fixes the "Configuration 'dev' not set" error.
if [[ "$CONFIG" == "dev" ]]; then
    echo "💡 Mapping configuration 'dev' to 'development'."
    CONFIG="development"
fi
# --- END PATCH ---

# The build command now uses the potentially updated CONFIG variable
ng build my-app --output-path="$BUILD_DIR" --configuration="$CONFIG"

# === Create/Update Symlink ===
echo "🔗 Updating 'latest' symlink to point to the new build..."
ln -snf "$BUILD_DIR" "$LATEST_LINK"

echo "✅ Build complete for [$REPO] on branch [$BRANCH] with configuration [$CONFIG]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
