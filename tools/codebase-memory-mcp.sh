#!/bin/bash
set -euo pipefail

DESCRIPTION="Code intelligence MCP server with automatic coding-agent configuration"

show_help() {
    cat <<'EOF'
Install codebase-memory-mcp for the current sandbox user and configure every
supported coding agent detected in that user's home directory.

Usage: cuybox-install install codebase-memory-mcp
EOF
}

case "${1:-}" in
    --description)
        echo "$DESCRIPTION"
        exit 0
        ;;
    --help|-h)
        show_help
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Error: codebase-memory-mcp installer does not accept arguments." >&2
        exit 1
        ;;
esac

if ! command -v npm >/dev/null 2>&1; then
    nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$nvm_dir/nvm.sh" ]; then
        export NVM_DIR="$nvm_dir"
        set +u
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh"
        set -u
    fi
fi

if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm is unavailable. Run cuybox user setup before installing this tool." >&2
    exit 1
fi

echo "Installing codebase-memory-mcp for $(id -un)..."
npm install --global --no-audit --no-fund codebase-memory-mcp@latest

if ! command -v codebase-memory-mcp >/dev/null 2>&1; then
    echo "Error: npm completed, but codebase-memory-mcp is not available on PATH." >&2
    exit 1
fi

echo "Configuring codebase-memory-mcp for detected coding agents..."
codebase-memory-mcp install -y

echo "codebase-memory-mcp is ready. Restart active coding-agent sessions before using it."
