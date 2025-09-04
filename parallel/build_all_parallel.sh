#!/bin/bash
set -Eeuo pipefail
trap 'echo "[❌ ERROR] Line $LINENO: $BASH_COMMAND (exit $?)"' ERR

CONFIG_FILE="$HOME/.repo_builder_config"

# === Save config ===
save_config() {
    echo "Saving current configuration to $CONFIG_FILE..."
    {
        echo "BASE_INPUT='$BASE_INPUT'"
        IFS=' ' SELECTED_REPOS_STRING="${SELECTED[*]}"
        echo "SELECTED_REPOS_STRING='${SELECTED_REPOS_STRING}'"
        for repo in "${!BRANCH_CHOICES[@]}"; do
            echo "BRANCH_CHOICES__${repo}='${BRANCH_CHOICES[$repo]}'"
        done
        for repo in "${!CONFIG_CHOICES[@]}"; do
            echo "CONFIG_CHOICES__${repo}='${CONFIG_CHOICES[$repo]}'"
        done
    } > "$CONFIG_FILE"
    echo "Configuration saved."
}

# === Load config ===
load_config() {
    declare -g BASE_INPUT=""
    declare -ga SELECTED=()
    declare -gA BRANCH_CHOICES
    declare -gA CONFIG_CHOICES
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "💡 Loading previous inputs from $CONFIG_FILE..."
        while IFS='=' read -r key value; do
            value="$(echo "$value" | sed "s/^'//; s/'$//")"
            case "$key" in
                BASE_INPUT) BASE_INPUT="$value" ;;
                SELECTED_REPOS_STRING) IFS=' ' read -r -a SELECTED <<< "$value" ;;
                BRANCH_CHOICES__*) local repo_name="${key#BRANCH_CHOICES__}"; BRANCH_CHOICES["$repo_name"]="$value" ;;
                CONFIG_CHOICES__*) local repo_name="${key#CONFIG_CHOICES__}"; CONFIG_CHOICES["$repo_name"]="$value" ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

load_config
START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_SETUP_SCRIPT="$SCRIPT_DIR/required-setup.sh"
if [[ -f "$REQUIRED_SETUP_SCRIPT" ]]; then
    read -rp "Do you want to run '$REQUIRED_SETUP_SCRIPT'? (y/N): " RUN_SETUP
    if [[ "${RUN_SETUP,,}" == "y" ]]; then
        if [[ -x "$REQUIRED_SETUP_SCRIPT" ]]; then
            "$REQUIRED_SETUP_SCRIPT"
        else
            echo "❌ Error: '$REQUIRED_SETUP_SCRIPT' is not executable. Skipping." >&2
        fi
    else
        echo "Skipping required-setup.sh."
    fi
else
    echo "⚠️ Warning: required-setup.sh not found."
fi

DEFAULT_BASE_INPUT="${BASE_INPUT:-build}"
read -rp "📁 Enter base directory (relative to ~) [default: $DEFAULT_BASE_INPUT]: " USER_BASE_INPUT
BASE_INPUT="${USER_BASE_INPUT:-$DEFAULT_BASE_INPUT}"
BASE_DIR="$HOME/$BASE_INPUT"
DATE_TAG=$(date +"%Y%m%d_%H%M%S")
CLONE_DIR="$BASE_DIR/repos"
DEPLOY_DIR="$BASE_DIR/builds"
LOG_DIR="$BASE_DIR/automationlogs"
TRACKER_FILE="$LOG_DIR/build-tracker-${DATE_TAG}.csv"
SUMMARY_CSV_FILE="$LOG_DIR/build-summary-${DATE_TAG}.csv"
mkdir -p "$CLONE_DIR" "$DEPLOY_DIR" "$LOG_DIR"

declare -A REPO_URLS=(
    ["off_highway_backend"]="https://github.com/simaiserver/off_highway_backend.git"
    ["dvm_visualization_tool"]="https://github.com/simaiserver/dvm_visualization_tool.git"
    ["spriced-platform-data-management-layer"]="https://github.com/simaiserver/spriced-platform-data-management-layer.git"
    ["spriced-platform-ib-ob"]="https://github.com/simaiserver/spriced-platform-ib-ob.git"
)

declare -A DEFAULT_BRANCHES=(
    ["off_highway_backend"]="main"
    ["dvm_visualization_tool"]="main"
    ["spriced-platform-data-management-layer"]="main"
    ["spriced-platform-ib-ob"]="develop"
)

REPOS=("dvm_visualization_tool" "off_highway_backend" "spriced-platform-data-management-layer" "spriced-platform-ib-ob")

BUILD_SCRIPTS=(
    "$SCRIPT_DIR/build_dvm_visualization_tool.sh"
    "$SCRIPT_DIR/build_off_highway_backend.sh"
    "$SCRIPT_DIR/build_spriced_platform_data_management_layer.sh"
    "$SCRIPT_DIR/build_spriced_platform_ib_ob.sh"
)

echo -e "\n📦 Available Repositories:"
for i in "${!REPOS[@]}"; do
    printf "  %d) %s\n" "$((i+1))" "${REPOS[$i]}"
done
echo "  0) ALL"

DEFAULT_SELECTION_NUMBERS=""
if [ "${#SELECTED[@]}" -gt 0 ]; then
    for repo_name in "${SELECTED[@]}"; do
        for i in "${!REPOS[@]}"; do
            if [[ "${REPOS[$i]}" == "$repo_name" ]]; then
                DEFAULT_SELECTION_NUMBERS+="$((i+1)) "
                break
            fi
        done
    done
    DEFAULT_SELECTION_NUMBERS="${DEFAULT_SELECTION_NUMBERS% }"
fi

read -rp $'\n📌 Enter repo numbers (space-separated or 0 for all) [default: '"${DEFAULT_SELECTION_NUMBERS:-0}"']: ' -a USER_SELECTED_INPUT
if [[ -z "${USER_SELECTED_INPUT[*]}" ]]; then
    if [ -n "$DEFAULT_SELECTION_NUMBERS" ]; then
        IFS=' ' read -r -a USER_SELECTED_INPUT <<< "$DEFAULT_SELECTION_NUMBERS"
    else
        USER_SELECTED_INPUT=("0")
    fi
fi

SELECTED=()
if [[ "${USER_SELECTED_INPUT[0]}" == "0" ]]; then
    SELECTED=("${REPOS[@]}")
else
    for idx_str in "${USER_SELECTED_INPUT[@]}"; do
        idx="$idx_str"
        if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#REPOS[@]} )); then
            echo "⚠️ Invalid selection: $idx. Skipping..."
            continue
        fi
        i=$((idx - 1))
        SELECTED+=("${REPOS[$i]}")
    done
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
    echo "No valid repositories selected. Exiting."
    exit 0
fi

build_and_log_repo() {
    local repo_name="$1"
    local script_path="$2"
    local log_file="$3"
    local tracker_file="$4"
    local base_dir_for_build_script="$5"
    local branch="$6"
    local config="$7"

    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build started for $repo_name ---" >> "$log_file"
    set +e
    if script_output=$("${script_path}" "$branch" "$base_dir_for_build_script" "$config" 2>&1); then
        script_exit_code=0
    else
        script_exit_code=$?
    fi
    set -e

    echo "$script_output" | while IFS= read -r line; do
        echo "$(date +'%Y-%m-%m %H:%M:%S') $line"
    done >> "$log_file"

    local status="FAIL"
    if [[ "$script_exit_code" -eq 0 ]]; then
        status="SUCCESS"
    fi
    echo "${repo_name},${status},${log_file}" >> "$tracker_file"
    echo "$(date +'%Y-%m-%d %H:%M:%S') --- Build finished for $repo_name with status: $status ---" >> "$log_file"
}

export -f build_and_log_repo

COMMANDS=()
for REPO in "${SELECTED[@]}"; do
    SCRIPT_TO_RUN=""
    for j in "${!REPOS[@]}"; do
        if [[ "${REPOS[$j]}" == "$REPO" ]]; then
            SCRIPT_TO_RUN="${BUILD_SCRIPTS[$j]}"
            break
        fi
    done
    [[ -z "$SCRIPT_TO_RUN" ]] && continue

    REPO_DIR="$CLONE_DIR/$REPO"
    PREVIOUSLY_SAVED_BRANCH="${BRANCH_CHOICES[$REPO]:-${DEFAULT_BRANCHES[$REPO]}}"
    read -rp "Enter branch for $REPO [default: $PREVIOUSLY_SAVED_BRANCH]: " USER_BRANCH
    BRANCH_CHOICES["$REPO"]="${USER_BRANCH:-$PREVIOUSLY_SAVED_BRANCH}"

    echo -e "\n🚀 Checking '$REPO' repository..."
    if [[ -d "$REPO_DIR/.git" ]]; then
        echo "🔄 Updating $REPO..."
        (cd "$REPO_DIR" && git fetch origin --prune && git reset --hard HEAD && git clean -fd)
        if ! (cd "$REPO_DIR" && git checkout "${BRANCH_CHOICES[$REPO]}"); then
            echo "⚠️ Warning: The selected branch '${BRANCH_CHOICES[$REPO]}' not found for '$REPO'. Falling back to 'main' or 'master'."
            if ! (cd "$REPO_DIR" && git checkout -B "main" "origin/main"); then
                if ! (cd "$REPO_DIR" && git checkout -B "master" "origin/master"); then
                    echo "⚠️  Warning: Neither 'main' nor 'master' found for '$REPO'. Attempting fallback."
                    remote_branch=$(cd "$REPO_DIR" && git branch -r | grep -v 'HEAD' | grep -v '->' | head -n 1 | sed 's/ *origin\///' | xargs)
                    if [ -n "$remote_branch" ]; then
                        echo "🔍 Found remote branch '$remote_branch'. Checking it out."
                        if ! (cd "$REPO_DIR" && git checkout -B "$remote_branch" "origin/$remote_branch"); then
                            echo "❌ Failed to checkout branch '$remote_branch'. Skipping."
                            continue
                        fi
                    else
                        echo "❌ Failed to prepare $REPO: No valid remote branches found. Skipping."
                        continue
                    fi
                fi
            fi
        fi
    else
        echo "📥 Cloning ${REPO_URLS[$REPO]}"
        git clone --branch "${BRANCH_CHOICES[$REPO]}" "${REPO_URLS[$REPO]}" "$REPO_DIR" || { echo "❌ Failed to clone $REPO. Skipping."; continue; }
    fi

    if [[ "$REPO" == "dvm_visualization_tool" ]]; then
        ENV_DIR="$REPO_DIR/projects/my-app/src/environments"
        declare -a DYNAMIC_CONFIGS=()
        DEFAULT_CONFIG_NAME="development"
        if [[ -d "$ENV_DIR" ]]; then
            for file in "$ENV_DIR"/environment.*.ts; do
                if [[ -f "$file" ]]; then
                    config_name=$(basename "$file" .ts)
                    config_name="${config_name#environment.}"
                    if [[ "$config_name" != "development" ]]; then
                        DYNAMIC_CONFIGS+=("$config_name")
                    fi
                fi
            done
        fi
        IFS=$'\n' DYNAMIC_CONFIGS=($(sort <<<"${DYNAMIC_CONFIGS[*]}"))
        unset IFS

        declare -a AVAILABLE_CONFIGS=("${DYNAMIC_CONFIGS[@]}")
        echo -e "\n⚙️ Available build configurations for $REPO:"
        echo "  0) Create a new environment..."
        for k in "${!AVAILABLE_CONFIGS[@]}"; do
            printf "  %d) %s\n" "$((k+1))" "${AVAILABLE_CONFIGS[$k]}"
        done

        PREVIOUSLY_SAVED_CONFIG="${CONFIG_CHOICES[$REPO]:-$DEFAULT_CONFIG_NAME}"
        read -rp "📌 Enter configuration name or number [default: $PREVIOUSLY_SAVED_CONFIG]: " USER_CONFIG_INPUT
        USER_CONFIG_INPUT="${USER_CONFIG_INPUT:-$PREVIOUSLY_SAVED_CONFIG}"
        FINAL_CONFIG=""

        if [[ "$USER_CONFIG_INPUT" =~ ^[0-9]+$ ]]; then
            if [[ "$USER_CONFIG_INPUT" == "0" ]]; then
                read -rp "Enter the name for the new environment: " NEW_ENV_NAME
                FINAL_CONFIG="${NEW_ENV_NAME:-$DEFAULT_CONFIG_NAME}"
                NEW_ENV_FILE="$ENV_DIR/environment.${FINAL_CONFIG}.ts"
                ANGULAR_CONFIG_FILE="$REPO_DIR/angular.json"
                NEW_REALM="D_SPRICED"
                NEW_CLIENT_ID="D_SPRICED_Client"
                DEFAULT_URL="https://dev-off-highway.alpha.simadvisory.com"

                if [ ! -f "$NEW_ENV_FILE" ]; then
                    echo "🆕 Creating new environment file '$NEW_ENV_FILE' with updated URL..."
                    cat > "$NEW_ENV_FILE" <<EOF
export const environment = {
  URL: '$DEFAULT_URL',
  KEYCLOAK_URL: 'https://auth.dev.simadvisory.com/auth',
  KEYCLOAK_REALM: '$NEW_REALM',
  KEYCLOAK_CLIENT_ID: '$NEW_CLIENT_ID',
};
EOF
                    echo "✅ New environment file created with updated URL."
                else
                    echo "⚠️ Environment file '$NEW_ENV_FILE' already exists. Not overwriting."
                fi

                if command -v jq &> /dev/null; then
                    echo "Updating 'angular.json' to include the new configuration..."
                    TEMP_JSON=$(jq --arg config_name "$FINAL_CONFIG" \
                                   --arg env_file "projects/my-app/src/environments/environment.${FINAL_CONFIG}.ts" \
                                   '
                                   .projects["my-app"].architect.build.configurations |= (
                                     if (. == null) or (. == "") then {} else . end
                                   ) |
                                   .projects["my-app"].architect.build.configurations[$config_name] = {
                                     "fileReplacements": [
                                       {
                                         "replace": "projects/my-app/src/environments/environment.ts",
                                         "with": $env_file
                                       }
                                     ],
                                     "budgets": [
                                       {
                                         "type": "initial",
                                         "maximumWarning": "500kb",
                                         "maximumError": "1mb"
                                       },
                                       {
                                         "type": "anyComponentStyle",
                                         "maximumWarning": "2kb",
                                         "maximumError": "4kb"
                                       }
                                     ]
                                   }
                                   ' "$ANGULAR_CONFIG_FILE")
                    echo "$TEMP_JSON" > "$ANGULAR_CONFIG_FILE"
                    echo "✅ 'angular.json' updated successfully."
                else
                    echo "⚠️ Warning: 'jq' is not installed. Unable to update 'angular.json'."
                    echo "Please install 'jq' (e.g., 'sudo apt-get install jq') to automatically add build configurations."
                fi

                (
                    cd "$REPO_DIR" || exit
                    git add "projects/my-app/src/environments/environment.${FINAL_CONFIG}.ts"
                    git add "angular.json"
                    git commit -m "feat(config): Add new environment configuration for ${FINAL_CONFIG}"
                ) || echo "❌ Failed to commit new configuration."
            elif (( USER_CONFIG_INPUT > 0 && USER_CONFIG_INPUT <= ${#AVAILABLE_CONFIGS[@]} )); then
                FINAL_CONFIG="${AVAILABLE_CONFIGS[$((USER_CONFIG_INPUT-1))]}"
            else
                echo "⚠️ Invalid selection: $USER_CONFIG_INPUT. Defaulting to '$DEFAULT_CONFIG_NAME'."
                FINAL_CONFIG="$DEFAULT_CONFIG_NAME"
            fi
        else
            FINAL_CONFIG="$USER_CONFIG_INPUT"
        fi
        CONFIG_CHOICES["$REPO"]="$FINAL_CONFIG"
    else
        PREVIOUSLY_SAVED_CONFIG="${CONFIG_CHOICES[$REPO]:-development}"
        CONFIG_CHOICES["$REPO"]="$PREVIOUSLY_SAVED_CONFIG"
    fi

    LOG_FILE="$LOG_DIR/${REPO}_${DATE_TAG}.log"
    COMMANDS+=("build_and_log_repo \"$REPO\" \"$SCRIPT_TO_RUN\" \"$LOG_FILE\" \"$TRACKER_FILE\" \"$BASE_DIR\" \"${BRANCH_CHOICES[$REPO]}\" \"${CONFIG_CHOICES[$REPO]}\"")
done

save_config
CPU_CORES=$(nproc)
MAX_JOBS=$(( (CPU_CORES * 80 + 99) / 100 ))

echo -e "\n🚀 Running ${#COMMANDS[@]} builds in parallel, limited to ~80% of CPU capacity..."
if [ ${#COMMANDS[@]} -eq 0 ]; then
    echo "No parallel commands to execute. Exiting."
    exit 0
fi

set +e
printf "%s\n" "${COMMANDS[@]}" | parallel -j "$MAX_JOBS" --load 80% --no-notice --bar
PARALLEL_EXIT_CODE=$?
set -e

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")

if [[ -f "$TRACKER_FILE" ]]; then
    echo "Script Start Time,$START_TIME" > "$SUMMARY_CSV_FILE"
    echo "Script End Time,$END_TIME" >> "$SUMMARY_CSV_FILE"
    echo "---" >> "$SUMMARY_CSV_FILE"
    echo "Status,Repository,Log File" >> "$SUMMARY_CSV_FILE"
    while IFS=',' read -r REPO STATUS LOGFILE; do
        [[ "$STATUS" == "SUCCESS" ]] && echo "[✔️ DONE] $REPO - see log: $LOGFILE" || echo "[❌ FAIL] $REPO - see log: $LOGFILE"
        echo "$STATUS,$REPO,$LOGFILE" >> "$SUMMARY_CSV_FILE"
    done < "$TRACKER_FILE"
else
    echo "⚠️ No tracker file found."
fi

echo "📄 Summary at: $SUMMARY_CSV_FILE"
exit $PARALLEL_EXIT_CODE
