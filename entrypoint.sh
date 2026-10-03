#!/bin/sh
set -eu

case "${1:-}" in
    codex)
        shift
        mkdir -p "${CODEX_HOME:-$HOME/.codex}"
        # Installed into the mounted home so Codex can update itself.
        command -v codex >/dev/null || {
            echo "clod: installing Codex into this home..." >&2
            npm install --global @openai/codex
        }
        exec codex --dangerously-bypass-approvals-and-sandbox "$@"
        ;;
    bash|zsh)
        shell=$1
        shift
        exec "$shell" "$@"
        ;;
    claude)
        shift
        ;;
esac

# A fresh home skips first-run prompts; its login comes from /login or from a
# home borrowed via CLOD_CREDS.
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$config"
[ -e "$config/.claude.json" ] ||
    echo '{"hasCompletedOnboarding":true,"projects":{"/workspace":{"hasTrustDialogAccepted":true}}}' > "$config/.claude.json"
[ -e "$config/settings.json" ] ||
    echo '{"skipDangerousModePermissionPrompt":true}' > "$config/settings.json"

# Preserve the original default and forwarding of Claude arguments.
if [ "$#" -eq 0 ]; then
    set -- --dangerously-skip-permissions
fi
# Installed into the mounted home so Claude Code can update itself.
command -v claude >/dev/null || {
    echo "clod: installing Claude Code into this home..." >&2
    curl -fsSL https://claude.ai/install.sh | bash
}
exec claude "$@"
