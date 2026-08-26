#!/bin/bash
set -euo pipefail

DESCRIPTION="Focused presentation layer for OpenCode responses"
DEFAULT_REPOSITORY="https://github.com/DevElCuy/skills.git"
DEFAULT_REF="main"

show_help() {
    cat <<'EOF'
Install opencode-attention from the DevElCuy/skills repository and register its
compiled JavaScript entry point in the current user's global OpenCode config.

Usage: cuybox-install install opencode-attention

Environment overrides:
  OPENCODE_ATTENTION_REPOSITORY  Git repository URL
  OPENCODE_ATTENTION_REF         Git branch or tag (default: main)
  OPENCODE_ATTENTION_SOURCE_DIR  Local opencode-attention source directory;
                                 intended for development and testing
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
        echo "Error: opencode-attention installer does not accept arguments." >&2
        exit 1
        ;;
esac

for dependency in git jq; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "Error: $dependency is required to install opencode-attention." >&2
        exit 1
    fi
done

work_dir=$(mktemp -d)
config_temp=""
cleanup() {
    rm -rf -- "$work_dir"
    if [ -n "$config_temp" ]; then
        rm -f -- "$config_temp"
    fi
}
trap cleanup EXIT

source_override="${OPENCODE_ATTENTION_SOURCE_DIR:-}"
if [ -n "$source_override" ]; then
    if [ ! -d "$source_override" ]; then
        echo "Error: OPENCODE_ATTENTION_SOURCE_DIR is not a directory: $source_override" >&2
        exit 1
    fi
    source_dir="$work_dir/opencode-attention"
    cp -a "$source_override" "$source_dir"
else
    repository="${OPENCODE_ATTENTION_REPOSITORY:-$DEFAULT_REPOSITORY}"
    repository_ref="${OPENCODE_ATTENTION_REF:-$DEFAULT_REF}"
    repository_dir="$work_dir/skills"

    echo "Downloading opencode-attention from $repository ($repository_ref)..."
    git clone --quiet --depth 1 --branch "$repository_ref" "$repository" "$repository_dir"
    source_dir="$repository_dir/opencode-attention"
fi

if [ ! -f "$source_dir/package.json" ] || \
   ! jq -e '.name == "opencode-attention"' "$source_dir/package.json" >/dev/null 2>&1; then
    echo "Error: the source does not contain the opencode-attention package." >&2
    exit 1
fi

if [ ! -f "$source_dir/dist/index.js" ]; then
    echo "Error: opencode-attention/dist/index.js is missing; publish a built plugin before installing it." >&2
    exit 1
fi

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
install_dir="$data_home/cuybox/plugins/opencode-attention"
mkdir -p "$install_dir/dist"
cp -a "$source_dir/dist/." "$install_dir/dist/"
cp -a "$source_dir/package.json" "$install_dir/package.json"
for package_file in README.md LICENSE; do
    if [ -f "$source_dir/$package_file" ]; then
        cp -a "$source_dir/$package_file" "$install_dir/$package_file"
    fi
done

plugin_entry="$install_dir/dist/index.js"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
config_dir="$config_home/opencode"
config_file="$config_dir/opencode.json"
mkdir -p "$config_dir"

if [ ! -f "$config_file" ]; then
    printf '%s\n' '{"$schema":"https://opencode.ai/config.json"}' > "$config_file"
fi

if ! jq empty "$config_file" >/dev/null 2>&1; then
    echo "Error: $config_file is not valid JSON; plugin files were installed, but the config was not changed." >&2
    exit 1
fi

config_temp=$(mktemp "$config_dir/.opencode.json.XXXXXX")
jq --arg plugin_entry "$plugin_entry" '
    (.plugin // []) as $plugins
    | ($plugins
        | map(select(
            type == "array"
            and (.[0] == "opencode-attention" or .[0] == $plugin_entry)
        ))
        | first) as $existing_options
    | .plugin = (
        ($plugins
            | map(select(
                . != "opencode-attention"
                and . != $plugin_entry
                and (
                    type != "array"
                    or (.[0] != "opencode-attention" and .[0] != $plugin_entry)
                )
            )))
        + [
            if $existing_options == null
            then $plugin_entry
            else ($existing_options | .[0] = $plugin_entry)
            end
        ]
    )
' "$config_file" > "$config_temp"
chmod --reference="$config_file" "$config_temp"
mv "$config_temp" "$config_file"
config_temp=""

echo "opencode-attention is installed at $install_dir."
echo "Restart OpenCode to load the plugin."
