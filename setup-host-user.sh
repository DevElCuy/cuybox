#!/bin/bash
set -euo pipefail

required_vars=(TARGET_UID TARGET_GID)
for var in "${required_vars[@]}"; do
    if [ -z "${!var-}" ]; then
        echo "Error: $var is not set." >&2
        exit 1
    fi
done

if [ "${TARGET_UID}" -eq 0 ]; then
    echo "Skipping user setup for root (UID 0)."
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: setup-host-user.sh must run as root." >&2
    exit 1
fi

# Get target username
TARGET_USER=$(id -un "$TARGET_UID")
if [ -z "$TARGET_USER" ]; then
    echo "Error: Could not determine username for UID $TARGET_UID." >&2
    exit 1
fi

# NVM and Node.js configuration
NVM_DIR="/home/$TARGET_USER/.nvm" # NVM will be installed in the user's home directory
NODE_VERSION="v22" # Use the same version as in the Dockerfile previously

# Check if nvm is already installed for the target user
if [ ! -d "$NVM_DIR" ]; then
    echo "Installing nvm for user $TARGET_USER..."
    /sbin/setuser "$TARGET_USER" bash -l -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
    echo "nvm installed."
fi

# Install Node.js for the target user
echo "Installing Node.js $NODE_VERSION for user $TARGET_USER..."
/sbin/setuser "$TARGET_USER" bash -l -c "export NVM_DIR=\"$NVM_DIR\" && [ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\" && nvm install $NODE_VERSION && nvm alias default $NODE_VERSION"
echo "Node.js $NODE_VERSION installed and set as default."

# Install CLI tools globally via npm (idempotent: skip any already present)
echo "Ensuring CLI tools (codex, claude, opencode) are installed for user $TARGET_USER..."
/sbin/setuser "$TARGET_USER" bash -l -c "
    export NVM_DIR=\"$NVM_DIR\"
    \\. \"\$NVM_DIR/nvm.sh\"
    command -v codex    >/dev/null 2>&1 || npm install -g @openai/codex
    command -v claude   >/dev/null 2>&1 || npm install -g @anthropic-ai/claude-code
    command -v opencode >/dev/null 2>&1 || npm install -g opencode-ai
"
echo "CLI tools ready."

# Install broad, language-agnostic OpenCode watcher defaults without replacing
# any user settings or ignore patterns already present in opencode.json.
OPENCODE_DEFAULTS=/usr/local/share/cuybox/opencode-defaults.json
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_CONFIG_HOME="${XDG_CONFIG_HOME:-$TARGET_HOME/.config}"
OPENCODE_CONFIG_DIR="$TARGET_CONFIG_HOME/opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"
OPENCODE_CONFIG_TEMP=""

/sbin/setuser "$TARGET_USER" mkdir -p "$OPENCODE_CONFIG_DIR"

if [ ! -f "$OPENCODE_CONFIG_FILE" ]; then
    install -o "$TARGET_UID" -g "$TARGET_GID" -m 644 \
        "$OPENCODE_DEFAULTS" "$OPENCODE_CONFIG_FILE"
elif jq -e '
    type == "object"
    and ((.watcher // {}) | type == "object")
    and ((.watcher.ignore // []) | type == "array")
' "$OPENCODE_CONFIG_FILE" >/dev/null 2>&1; then
    OPENCODE_CONFIG_TEMP=$(mktemp "$OPENCODE_CONFIG_DIR/.opencode.json.XXXXXX")
    jq --slurpfile defaults "$OPENCODE_DEFAULTS" '
        .watcher.ignore = reduce (
            ((.watcher.ignore // []) + $defaults[0].watcher.ignore)[]
        ) as $pattern (
            [];
            if index($pattern) == null then . + [$pattern] else . end
        )
    ' "$OPENCODE_CONFIG_FILE" > "$OPENCODE_CONFIG_TEMP"
    chown "$TARGET_UID:$TARGET_GID" "$OPENCODE_CONFIG_TEMP"
    chmod --reference="$OPENCODE_CONFIG_FILE" "$OPENCODE_CONFIG_TEMP"
    mv "$OPENCODE_CONFIG_TEMP" "$OPENCODE_CONFIG_FILE"
    OPENCODE_CONFIG_TEMP=""
else
    echo "Warning: $OPENCODE_CONFIG_FILE is not a valid OpenCode JSON object; watcher defaults were not added." >&2
fi

echo "OpenCode watcher defaults ready."

# Add host.docker.internal to /etc/hosts if not already present
GATEWAY_IP=$(ip route | awk '/default/ {print $3}')
if ! grep -q "host.docker.internal" /etc/hosts; then
    echo "$GATEWAY_IP host.docker.internal" >> /etc/hosts
fi

# Source custom setup script if it exists
if [ -f /sandbox/.cuyboxrc ]; then
    echo "Running custom setup from .cuyboxrc..."
    set +e  # Temporarily disable exit-on-error
    source /sandbox/.cuyboxrc
    CUYBOXRC_EXIT=$?
    set -e  # Re-enable exit-on-error

    if [ $CUYBOXRC_EXIT -ne 0 ]; then
        echo "Warning: .cuyboxrc exited with code $CUYBOXRC_EXIT" >&2
        echo "Container setup will continue, but custom setup may be incomplete." >&2
    else
        echo ".cuyboxrc completed successfully."
    fi
fi

# Marker file creation - commented out (not used in control flow)
# MARKER_DIR=/etc/cuybox
# MARKER_FILE=${MARKER_DIR}/user-${TARGET_UID}.marker
#
# mkdir -p "$MARKER_DIR"
# cat > "$MARKER_FILE" <<EOF
# uid=$TARGET_UID
# gid=$TARGET_GID
# generated=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# EOF
# chmod 600 "$MARKER_FILE"
