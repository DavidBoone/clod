#!/bin/sh
set -eu

# A devcontainer image's containerEnv, which its build wrote out (see the
# Dockerfile), for those the run doesn't set, as from the .envrc.
env_file=/usr/local/share/clod/devcontainer.env
if [ -r "$env_file" ]; then
    while IFS= read -r line; do
        name=${line%%=*}
        eval "given=\${$name+x}"
        # shellcheck disable=SC2163 # line is NAME=value, which export sets
        [ -n "$given" ] || export "$line"
    done < "$env_file"
    unset line name given
fi
unset env_file

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

# A fresh home skips first-run prompts; its login comes from /login.
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
mkdir -p "$config"
[ -e "$config/.claude.json" ] ||
    echo '{"hasCompletedOnboarding":true,"projects":{"/workspace":{"hasTrustDialogAccepted":true}}}' > "$config/.claude.json"
[ -e "$config/settings.json" ] ||
    echo '{"skipDangerousModePermissionPrompt":true}' > "$config/settings.json"

# Permission prompts are off unless the arguments choose a permission mode.
skip=--dangerously-skip-permissions
for arg; do
    case $arg in
        --) break ;;
        --permission-mode|--permission-mode=*|--dangerously-skip-permissions|--allow-dangerously-skip-permissions)
            skip= ;;
    esac
done
if [ -n "$skip" ]; then
    set -- "$skip" "$@"
fi
# Instructions an image adds under /etc/clod (a CLAUDE.md, or files in
# .claude/rules/) load through --add-dir. The = form keeps the option, which
# takes several directories, from taking a subcommand or prompt as one.
if [ -d /etc/clod ]; then
    # Claude Code skips a file it can't read without a word. COPY keeps the
    # source file's mode, so a source saved as 600 gives an unreadable one.
    find /etc/clod ! -readable -printf \
        "clod: Claude can't read %p; chmod 644 the file it was copied from and rebuild\n" >&2 || true
    set -- --add-dir=/etc/clod "$@"
    export CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1
fi
# The shared settings (the statusline) go in as --settings, not as managed
# settings, which an organisation's server-managed settings would replace. Only
# the last --settings applies, so one in the arguments replaces them.
settings=/etc/claude-code/settings.json
for arg; do
    case $arg in
        --) break ;;
        --settings|--settings=*) settings= ;;
    esac
done
if [ -n "$settings" ] && [ -r "$settings" ]; then
    set -- --settings="$settings" "$@"
fi
# Plugins the image brings (show-image) load from their folders.
for plugin in /etc/clod/plugins/*/; do
    [ -d "$plugin" ] && set -- --plugin-dir="${plugin%/}" "$@"
done
# Installed into the mounted home so Claude Code can update itself.
command -v claude >/dev/null || {
    echo "clod: installing Claude Code into this home..." >&2
    # sh has no pipefail, so a failed download only shows up here.
    curl -fsSL https://claude.ai/install.sh | bash
    command -v claude >/dev/null || {
        echo "clod: Claude Code install failed" >&2
        exit 1
    }
}
exec claude "$@"
