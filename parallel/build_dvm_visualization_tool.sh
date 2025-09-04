#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# === Inputs ===
BRANCH="${1:-main}"
BASE_DIR="${2:-$HOME/build}"
CONFIG="${3:-development}"
# The URL is now dynamically generated based on the configuration name
# This makes the script more flexible and eliminates the need for a manual URL argument.
URL_TO_USE="https://${CONFIG}-off-highway.alpha.simadvisory.com"
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
echo "🔧 Starting build for [$REPO] on branch [$BRANCH]..."
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
echo "🔍 Verifying Node.js version..."
NODE_VERSION=$(node -v)
MIN_NODE_VERSION="18.15.0"
if [[ "$(printf '%s\n' "$MIN_NODE_VERSION" "$NODE_VERSION" | sort -V | head -n1)" != "$MIN_NODE_VERSION" ]]; then
    echo "[❌ ERROR] Node.js version is too old. The Angular CLI requires Node.js v18.15.0 or newer."
    echo "Detected Node.js version: $NODE_VERSION"
    echo "Please update your Node.js version and try again."
    exit 1
fi
echo "✅ Node.js version ($NODE_VERSION) is compatible."

# === Dynamic Configuration Creation ===
ENV_FILE="$REPO_DIR/projects/my-app/src/environments/environment.$CONFIG.ts"
ANGULAR_CONFIG_FILE="$REPO_DIR/angular.json"

echo "🆕 Creating/Updating environment file '$ENV_FILE'..."
cat > "$ENV_FILE" <<EOF
export const environment = {
    URL: '$URL_TO_USE',
    KEYCLOAK_URL: 'https://auth.dev.simadvisory.com/auth',
    KEYCLOAK_REALM: 'D_SPRICED',
    KEYCLOAK_CLIENT_ID: 'D_SPRICED_Client',
};
EOF
echo "✅ Environment file updated with the new URL."

if command -v jq &> /dev/null; then
    echo "Updating 'angular.json' to include the new configuration..."
    jq --arg config_name "$CONFIG" \
        --arg env_file "projects/my-app/src/environments/environment.$CONFIG.ts" \
        '
        .projects."my-app".architect.build.configurations |= (
            if (. == null) or (. == "") then {} else . end
        ) |
        .projects."my-app".architect.build.configurations[$config_name] = {
            "fileReplacements": [
                {
                    "replace": "projects/my-app/src/environments/environment.ts",
                    "with": $env_file
                }
            ],
            "budgets": [
                {
                    "type": "initial",
                    "maximumWarning": "3mb",
                    "maximumError": "3.5mb"
                },
                {
                    "type": "anyComponentStyle",
                    "maximumWarning": "8kb",
                    "maximumError": "10kb"
                }
            ]
        } |
        .projects."my-app".architect.build.options.allowedCommonJsDependencies |= (
            . + ["file-saver", "echarts-stat"] | unique
        )' "$ANGULAR_CONFIG_FILE" > temp.json && mv temp.json "$ANGULAR_CONFIG_FILE"
    echo "✅ 'angular.json' updated successfully."
else
    echo "⚠️ Warning: 'jq' is not installed. Skipping automatic configuration fixes."
fi

# --- END of Dynamic Configuration Creation ---

# --- Install Dependencies ---
echo "📦 Installing npm dependencies (engine warnings suppressed)..."
npm_config_loglevel=error npm install

# === Build Process ===
echo "🛠️ Starting Angular build for project 'my-app' with configuration: $CONFIG..."
ng build my-app --output-path="$BUILD_DIR" --configuration="$CONFIG"

# === Create/Update Symlink ---
echo "🔗 Updating 'latest' symlink to point to the new build..."
ln -snf "$BUILD_DIR" "$LATEST_LINK"
echo "✅ Build complete for [$REPO] on branch [$BRANCH] with configuration [$CONFIG]"
echo "📁 Artifacts stored at: $BUILD_DIR"
echo "📄 Log saved at: $LOG_FILE"
