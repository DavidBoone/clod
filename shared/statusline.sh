#!/bin/bash
# Claude Code statusline for clod homes, part of the starter shared config.
# `↑` = rolling total of uncached input + cache creation tokens (the tokens you actually pay premium for).
# `↓` = rolling total of output tokens (as reported by Claude Code).
# Cache reads are intentionally omitted from `↑` — they're cheap and mostly mirror the ◔ context meter.
#
# Cache-miss detection, two tiers:
#  - full (red ⚠ MISS):   cache_creation > cache_read and >10k — most of the
#    context rewritten at full price.
#  - partial (yellow ~miss): cache_read fell below the previous turn's read —
#    the cached prefix regressed (e.g. an /effort change invalidates everything
#    after the effort marker) — with created >1k to skip noise.
# Shown until the next typed user message (prompt_id change) or 2 minutes,
# whichever comes first. A single assistant turn spans several API calls, and a
# warm follow-up call must not hide the flag before it's seen.
# Subscription sessions use a 1-hour cache TTL (refreshed every request), so the
# idle timer (⏱) turns into a red 💤 at 60 min.
#
# If cache-turns.log exists in the Claude config dir, every detected turn is
# appended to it (ts, session, idle-gap-before-turn, cache_read, cache_created)
# to build an empirical picture of when misses actually happen vs idle time.
# Create the file to start logging; delete it to stop.
#
# Since cache_creation_input_tokens is only reported per-turn (no rolling total),
# we accumulate it ourselves in a per-session state file, using total_output_tokens
# as a "new turn" fingerprint to avoid double-counting on repeated statusline redraws.
# The fingerprint can tick more than once while a single API response streams, so
# turns whose (read, created) pair is identical to the previous one are skipped.

set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
prompt_id=$(echo "$input" | jq -r '.prompt_id // "-"')
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
lines_add=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_rm=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')

state_dir="${TMPDIR:-/tmp}/claude-statusline"
mkdir -p "$state_dir"
state_file="$state_dir/$session_id"
turn_log="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache-turns.log"

# ANSI helpers (statusline renders escape codes). Basic/bright 16 colors and no
# backgrounds, so the terminal's own background and theme show through:
# truecolor gets approximated by the statusline renderer. Line 1 gives each
# group one hue (cyan Claude, magenta clod, green git); line 2 has blue labels
# and white values. Green, yellow and red otherwise mean good, warning and bad.
RST=$'\033[0m'
DIM=$'\033[2m'
MAGENTA=$'\033[35m'
BR_MAGENTA=$'\033[95m'
DARK_CYAN=$'\033[36m'
BOLD_CYAN=$'\033[1;96m'
YELLOW=$'\033[93m'
GREEN=$'\033[92m'
BLUE=$'\033[94m'
WHITE=$'\033[97m'
RED=$'\033[91m'
BOLD_RED=$'\033[1;91m'
UL_MAGENTA=$'\033[4;35m'

# State: output-tokens fingerprint, accumulated cache-creation, last-activity
# timestamp (cache-TTL idle timer), last miss size + when it was detected +
# which prompt it happened under, and the previous (read, created) pair for
# streaming-redraw dedupe.
prev_out=0
cum_cache=0
last_activity=0
last_miss=0
miss_ts=0
miss_prompt="-"
miss_kind="-"
prev_read=-1
prev_create=-1
if [ -f "$state_file" ]; then
    read -r prev_out cum_cache last_activity last_miss miss_ts miss_prompt miss_kind prev_read prev_create < "$state_file" || true
    : "${last_activity:=0}"
    : "${last_miss:=0}"
    : "${miss_ts:=0}"
    : "${miss_prompt:=-}"
    : "${miss_kind:=-}"
    : "${prev_read:=-1}"
    : "${prev_create:=-1}"
fi

now=$(date +%s)

# If output token count changed since we last saw this session, the model just
# produced new tokens — accumulate this turn's cache_creation and stamp activity.
# Use != (not -gt): total_output_tokens lives under context_window and can RESET
# below prev_out after compaction or session resume, freezing last_activity forever.
# While idle, last_activity is frozen, so "now - last_activity" = cache-cold age.
# An unchanged (read, created) pair means the fingerprint ticked mid-stream on the
# same API response — stamp activity but don't re-count or re-log it.
if [ "$total_out" != "$prev_out" ]; then
    idle_gap=0
    [ "$last_activity" -gt 0 ] && idle_gap=$((now - last_activity))
    last_activity=$now

    if [ "$cache_read" != "$prev_read" ] || [ "$cache_create" != "$prev_create" ]; then
        cum_cache=$((cum_cache + cache_create))

        # Full miss = most of the context written, not read (10k floor keeps
        # tiny early-session turns from flagging). Partial = read regressed
        # below the previous turn's read: cached prefix was invalidated partway.
        if [ "$cache_create" -gt "$cache_read" ] && [ "$cache_create" -gt 10000 ]; then
            last_miss=$cache_create
            miss_ts=$now
            miss_prompt=$prompt_id
            miss_kind="full"
        elif [ "$prev_read" -ge 0 ] && [ "$cache_read" -lt "$prev_read" ] && [ "$cache_create" -gt 1000 ]; then
            last_miss=$cache_create
            miss_ts=$now
            miss_prompt=$prompt_id
            miss_kind="partial"
        fi

        if [ -f "$turn_log" ]; then
            echo "$(date -d "@$now" '+%F %T') $session_id idle=${idle_gap}s read=$cache_read created=$cache_create" >> "$turn_log"
        fi
    fi

    echo "$total_out $cum_cache $last_activity $last_miss $miss_ts $miss_prompt $miss_kind $cache_read $cache_create" > "$state_file"
fi

adjusted_in=$((total_in + cum_cache))

fmt_k() {
    local n=$1
    if [ -z "$n" ] || [ "$n" = "0" ]; then
        echo "0"
        return
    fi
    awk -v n="$n" 'BEGIN { if (n >= 1000) printf "%.1fk", n/1000; else print n }'
}

# Five-cell meter for percentage $1; filled cells shade green → yellow → red by
# position, and any nonzero value fills at least one cell.
bar() {
    local pct n i s=""
    pct=$(printf '%.0f' "$1")
    n=$(( (pct + 19) / 20 ))
    [ "$n" -gt 5 ] && n=5
    local cols=("$GREEN" "$GREEN" "$YELLOW" "$YELLOW" "$RED")
    for i in 0 1 2 3 4; do
        if [ "$i" -lt "$n" ]; then s+="${cols[$i]}▰"; else s+="${RST}${DIM}▱"; fi
    done
    printf '%s%s' "$s" "$RST"
}

# Two lines: `head` is model, clod launch context, ports and git; `parts` is
# the token counts and meters.
head=()
parts=()

model_part="${BOLD_CYAN}✦ ${model}${RST}"
[ -n "$effort" ] && model_part+=" ${DARK_CYAN}⚡${effort}${RST}"
head+=("$model_part")

# clod launch context: ⌂ home, ⬢ image.
if [ -n "${CLOD_HOME:-}" ]; then
    clod_part="${MAGENTA}⌂ ${BR_MAGENTA}${CLOD_HOME}${RST}"
    [ -n "${CLOD_IMAGE:-}" ] && clod_part+=" ${MAGENTA}⬢ ${CLOD_IMAGE}${RST}"
    head+=("$clod_part")
fi

# Published container ports (CLOD_PORTS) as underlined :PORT, each an OSC 8
# link to http://localhost:PORT. Claude Code passes the links on only when it
# recognises the terminal (TERM_PROGRAM and the like, or FORCE_HYPERLINK=1);
# otherwise they show as plain text. CLOD_PORTS holds container ports, so a
# link is right only when the host port is the same. UDP ports aren't shown.
if [ -n "${CLOD_PORTS:-}" ]; then
    ports_part="${MAGENTA}⇄${RST}"
    for port in ${CLOD_PORTS//,/ }; do
        [[ $port == */udp ]] && continue
        port=${port%/tcp}
        ports_part+=" ${UL_MAGENTA}"$'\033]8;;'"http://localhost:${port}"$'\a'":${port}"$'\033]8;;\a'"${RST}"
    done
    head+=("$ports_part")
fi

# Git branch (short hash when detached) and ±N changed files, untracked included.
if [ -n "$cwd" ] && branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null \
        || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null); then
    # Two extra spaces set the git part apart from the model/ports/clod group.
    git_part="  ${GREEN}ᚴ ${branch}${RST}"
    dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | wc -l) || dirty=0
    [ "$dirty" -gt 0 ] && git_part+=" ${YELLOW}±${dirty}${RST}"
    head+=("$git_part")
fi

parts+=("${BLUE}↑${WHITE}$(fmt_k "$adjusted_in") ${BLUE}↓${WHITE}$(fmt_k "$total_out")${RST}")

if [ "$lines_add" != "0" ] || [ "$lines_rm" != "0" ]; then
    parts+=("${GREEN}+${lines_add}${RST}${DIM}/${RST}${RED}-${lines_rm}${RST}")
fi

if [ -n "$used_pct" ]; then
    ctx_int=$(printf '%.0f' "$used_pct")
    ctx_color=$WHITE
    [ "$ctx_int" -ge 60 ] && ctx_color=$YELLOW
    [ "$ctx_int" -ge 80 ] && ctx_color=$RED
    parts+=("${BLUE}◔ $(bar "$ctx_int") ${ctx_color}${ctx_int}%${RST}")
fi

if [ "$last_activity" -gt 0 ]; then
    idle=$((now - last_activity))
    idle_m=$((idle / 60))
    idle_s=$((idle % 60))
    if [ "$idle" -ge 3600 ]; then
        parts+=("$(printf '%s💤 %d:%02d%s' "$BOLD_RED" "$idle_m" "$idle_s" "$RST")")
    else
        parts+=("$(printf '%s⏱ %s%d:%02d%s' "$BLUE" "$WHITE" "$idle_m" "$idle_s" "$RST")")
    fi
fi

# Quota meter, ten cells wide: used % $1, elapsed % $2. The dim ▱ track covers
# the elapsed share of the window and a dim ▁ line the time still to come, on
# the terminal's own background; the green fill is usage, and fill past the
# track is red. Usage rounds up to whole cells, elapsed to the nearest. The
# last usage cell shows the pace from the percentages themselves: red when
# usage is ahead of elapsed, yellow within 5 points behind it, green otherwise. Rounding moves usage at most one cell past
# the track, and that cell is the last, so red shows only when usage is ahead.
qbar() {
    local u=$1 e=$2 W=10 s="" i pace
    local BG="" FUT="${DIM}▁"
    # Alternative: a gray background marking out all ten cells, with blank
    # cells for the future (256-color gray; 232 is black, 255 white; 236 suits
    # a black terminal background, and clashes with others).
    # local BG=$'\033[48;5;236m' FUT=" "
    local nu=$(( (u * W + 99) / 100 )) ne=$(( (e * W + 50) / 100 ))
    [ "$nu" -gt "$W" ] && nu=$W
    [ "$ne" -gt "$W" ] && ne=$W
    if [ "$u" -gt "$e" ]; then pace=$RED
    elif [ $((u + 5)) -ge "$e" ]; then pace=$YELLOW
    else pace=$GREEN
    fi
    for ((i = 0; i < W; i++)); do
        if [ "$i" -eq $((nu - 1)) ]; then s+="${RST}${BG}${pace}▰"
        elif [ "$i" -lt "$nu" ] && [ "$i" -lt "$ne" ]; then s+="${RST}${BG}${GREEN}▰"
        elif [ "$i" -lt "$nu" ]; then s+="${RST}${BG}${RED}▰"
        elif [ "$i" -lt "$ne" ]; then s+="${RST}${BG}${DIM}▱"
        else s+="${RST}${BG}${FUT}"
        fi
    done
    printf '%s%s' "$s" "$RST"
}

# Rate-limit meter: label $1 (pre-colored), used % $2, reset epoch $3, window seconds $4.
# The dim /N% after the value is how much of the window has elapsed; without a
# reset time the track spans the full width.
limit_part() {
    local label=$1 pct elapsed=""
    pct=$(printf '%.0f' "$2")
    if [ -n "$3" ]; then
        elapsed=$(awk -v n="$now" -v r="$3" -v w="$4" 'BEGIN { e = (n - (r - w)) * 100 / w; if (e < 0) e = 0; if (e > 100) e = 100; printf "%.0f", e }')
    fi
    printf '%s %s %s%s%%%s' "$label" "$(qbar "$pct" "${elapsed:-100}")" "$WHITE" "$pct" "${elapsed:+${DIM}/${elapsed}%}${RST}"
}

if [ -n "$five_pct" ]; then
    five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    parts+=("$(limit_part "${BLUE}5h" "$five_pct" "$five_reset" 18000)")
fi
if [ -n "$week_pct" ]; then
    week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
    parts+=("$(limit_part "${BLUE}7d" "$week_pct" "$week_reset" 604800)")
fi

# Miss warning goes last so it stands out at the end of the line.
# Shown until the next typed user message (prompt_id change) or 2 minutes,
# whichever comes first — warm follow-up API calls in the same turn never hide it.
if [ "$last_miss" -gt 0 ] && [ "$prompt_id" = "$miss_prompt" ] && [ $((now - miss_ts)) -lt 120 ]; then
    if [ "$miss_kind" = "full" ]; then
        parts+=("${BOLD_RED}⚠ MISS $(fmt_k "$last_miss")${RST}")
    else
        parts+=("${YELLOW}~miss $(fmt_k "$last_miss")${RST}")
    fi
fi

join() {
    local result="" part
    for part in "$@"; do
        result="${result:+$result  }$part"
    done
    echo "$result"
}
join "${head[@]}"
join "${parts[@]}"
