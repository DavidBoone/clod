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

# Composes the instructions agents share into the file $1: the image's
# /etc/clod/AGENTS.md, then anything its variants added under
# /etc/clod/AGENTS.d/, then the shared config's own AGENTS.md, or, when there
# is none, a CLAUDE.md kept from before clod shipped AGENTS.md. With $2 set,
# that CLAUDE.md is left out: Claude Code reads it itself from /etc/claude-code,
# and reading it here too would repeat it.
compose_agents_md() {
    # /etc/clod comes with the image, so on one from before this composition
    # it isn't the container user's to write. Say so and go on: the agent then
    # runs without the composed instructions rather than not at all.
    # 2>/dev/null goes first, or the failed redirect's own error would print;
    # and cat, not :, whose failed redirect dash treats as fatal however it is
    # guarded
    if ! cat /dev/null 2>/dev/null > "$1"; then
        echo "clod: can't write the instructions to $1; they are left out" >&2
        return 0
    fi
    # A blank line between sources, so one without a trailing newline doesn't
    # run its last line into the next file's first.
    first=1
    for src in /etc/clod/AGENTS.md /etc/clod/AGENTS.d/*.md; do
        if [ -r "$src" ]; then
            [ "$first" = 1 ] || printf '\n' >> "$1"
            first=0
            cat "$src" >> "$1"
        fi
    done
    if [ -r /etc/claude-code/AGENTS.md ]; then
        [ "$first" = 1 ] || printf '\n' >> "$1"
        cat /etc/claude-code/AGENTS.md >> "$1"
    elif [ -z "${2:-}" ] && [ -r /etc/claude-code/CLAUDE.md ]; then
        [ "$first" = 1 ] || printf '\n' >> "$1"
        cat /etc/claude-code/CLAUDE.md >> "$1"
    fi
}

case "${1:-}" in
    codex)
        shift
        mkdir -p "${CODEX_HOME:-$HOME/.codex}"
        # Installed into the mounted home so Codex can update itself.
        command -v codex >/dev/null || {
            echo "clod: installing Codex into this home..." >&2
            npm install --global @openai/codex
        }
        # The container's and the shared config's instructions, as Codex's
        # global AGENTS.md. Written every run, so changes apply on the next one.
        compose_agents_md "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
        exec codex --dangerously-bypass-approvals-and-sandbox "$@"
        ;;
    opencode)
        shift
        # Installed into the mounted home so OpenCode and its login persist.
        if command -v opencode >/dev/null; then
            case "$(opencode --version)" in
                1.*|opencode\ v1.*)
                    echo "clod: upgrading OpenCode to v2 in this home..." >&2
                    npm uninstall --global opencode-ai
                    npm install --global @opencode/cli@2
                    ;;
            esac
        else
            echo "clod: installing OpenCode into this home..." >&2
            npm install --global @opencode/cli@2
        fi
        OPENCODE_PERMISSION=${OPENCODE_PERMISSION:-'{"*":"allow"}'}
        # V2 reads inline config rather than OPENCODE_PERMISSION. Its V1
        # config compatibility keeps existing permission overrides working.
        OPENCODE_CONFIG_CONTENT=${OPENCODE_CONFIG_CONTENT:-'{}'}
        OPENCODE_CONFIG_CONTENT=$(printf '%s\n' "$OPENCODE_CONFIG_CONTENT" |
            jq -c --argjson permission "$OPENCODE_PERMISSION" '.permission = $permission')
        export OPENCODE_PERMISSION OPENCODE_CONFIG_CONTENT
        # The container's and the shared config's instructions, as OpenCode's
        # global AGENTS.md, the only instructions file it reads from outside
        # the workspace. Written every run, so changes apply on the next one.
        mkdir -p "$HOME/.config/opencode"
        compose_agents_md "$HOME/.config/opencode/AGENTS.md"
        exec opencode "$@"
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
# Instructions an image adds under /etc/clod (its AGENTS.md and any files its
# variants put in AGENTS.d/) compose with the shared config's into one file,
# which the agents each get as their global instructions: Codex's
# $CODEX_HOME/AGENTS.md and OpenCode's ~/.config/opencode/AGENTS.md, and, here,
# /etc/clod/CLAUDE.md, which loads through --add-dir. The = form keeps the
# option, which takes several directories, from taking a subcommand or prompt
# as one.
if [ -d /etc/clod ]; then
    # The agents skip a file they can't read without a word, and compose
    # leaves one out. COPY keeps the source file's mode, so a source saved as
    # 600 gives an unreadable one.
    find /etc/clod ! -readable -printf \
        "clod: the agents can't read %p; chmod 644 the file it was copied from and rebuild\n" >&2 || true
    compose_agents_md /etc/clod/CLAUDE.md claude
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
