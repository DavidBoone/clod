#!/bin/bash
# Claude Code statusline for clod homes, part of the starter shared config.
# `↑` = session total of uncached input: new input + cache writes, summed per API call.
# `↓` = session total of output tokens, summed per API call.
# Cache reads are left out of both. Both include subagents, summed from their
# transcripts in <session>/subagents/ beside transcript_path.
#
# Cache-miss detection, two tiers:
#  - full (red ⚠ MISS):   cache_creation > cache_read and >10k — most of the
#    context rewritten at full price.
#  - partial (yellow ⚠ miss): cache_read fell below the previous turn's read —
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
# Claude Code's context_window.total_*_tokens fields describe only the latest
# API call, so the totals are summed in a per-session state file. A new call is
# recognised by a change in its (cache_read, cache_created) pair; output grows
# while a call streams, so each call's output is added once the next call starts.

set -euo pipefail
shopt -s extglob

# ${#var} counts characters, not bytes, only in a UTF-8 locale.
export LC_ALL=C.UTF-8

export PATH="$HOME/.local/bin:$PATH"

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
# The context size, as in "Opus 5.5 (1M context)", is left off.
model=${model% (* context)}
effort=$(echo "$input" | jq -r '.effort.level // empty')
prompt_id=$(echo "$input" | jq -r '.prompt_id // "-"')
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')
call_in=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
call_out=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
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
# truecolor gets approximated by the statusline renderer. Each group has one
# hue (cyan Claude, magenta home, brown (dark yellow) image, green git); meters
# and counts have bold blue symbols and labels and white values. Green, yellow
# and red otherwise mean good, warning and bad.
RST=$'\033[0m'
DIM=$'\033[2m'
MAGENTA=$'\033[35m'
BR_MAGENTA=$'\033[95m'
DARK_CYAN=$'\033[36m'
BOLD_CYAN=$'\033[1;96m'
YELLOW=$'\033[93m'
BROWN=$'\033[33m'
GREEN=$'\033[92m'
BOLD_BLUE=$'\033[1;94m'
WHITE=$'\033[97m'
RED=$'\033[91m'
BOLD_RED=$'\033[1;91m'
UL_MAGENTA=$'\033[4;35m'

# State: summed uncached input, output of finished calls, the latest call's
# output so far, last-activity timestamp (cache-TTL idle timer), last miss size
# + when it was detected + which prompt it happened under, and the latest call's
# (read, created) pair.
cum_in=0
cum_out=0
prev_out=0
last_activity=0
last_miss=0
miss_ts=0
miss_prompt="-"
miss_kind="-"
prev_read=-1
prev_create=-1
if [ -f "$state_file" ]; then
    read -r cum_in cum_out prev_out last_activity last_miss miss_ts miss_prompt miss_kind prev_read prev_create < "$state_file" || true
    : "${cum_out:=0}"
    : "${prev_out:=0}"
    : "${last_activity:=0}"
    : "${last_miss:=0}"
    : "${miss_ts:=0}"
    : "${miss_prompt:=-}"
    : "${miss_kind:=-}"
    : "${prev_read:=-1}"
    : "${prev_create:=-1}"
fi

now=$(date +%s)

# A changed (read, created) pair is a new API call: bank the previous call's
# output, add this call's uncached input, and check it for a cache miss. Output
# growing on the same pair is the same call still streaming. Either one stamps
# activity; while idle, "now - last_activity" = cache-cold age. Redraws before
# the first call report all zeros and are ignored.
new_call=0
if [ $((call_in + cache_create + cache_read)) -gt 0 ] \
    && { [ "$cache_read" != "$prev_read" ] || [ "$cache_create" != "$prev_create" ]; }; then
    new_call=1
fi
if [ "$new_call" = 1 ] || [ "$call_out" != "$prev_out" ]; then
    idle_gap=0
    [ "$last_activity" -gt 0 ] && idle_gap=$((now - last_activity))
    last_activity=$now

    if [ "$new_call" = 1 ]; then
        cum_out=$((cum_out + prev_out))
        cum_in=$((cum_in + call_in + cache_create))

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

    prev_out=$call_out
    echo "$cum_in $cum_out $prev_out $last_activity $last_miss $miss_ts $miss_prompt $miss_kind $cache_read $cache_create" > "$state_file"
fi


# Subagent usage, from their transcripts, which only ever grow. A streamed
# message is written several times with growing output, so only the last entry
# per message id counts. Each transcript's sums are cached with the byte offset
# they cover and the last message counted, so a refresh reads only what was
# appended since; a message continued past that offset replaces its earlier
# count. A line still being written is left for a later refresh, and each
# transcript's cache line is appended as soon as it's computed (later lines
# win), so a run cut short keeps its progress.
sub_in=0
sub_out=0
sub_dir="${transcript%.jsonl}/subagents"
if [ -n "$transcript" ] && [ -d "$sub_dir" ]; then
    sub_cache="$state_file.sub"
    declare -A cached
    if [ -f "$sub_cache" ]; then
        while read -r f rest; do
            cached[$f]=$rest
        done < "$sub_cache"
    fi
    new_cache=""
    while read -r f size; do
        read -r off f_in f_out lid lin lout <<< "${cached[$f]:-}"
        if [ -z "$lout" ] || [ "$size" -lt "$off" ]; then
            off=0 f_in=0 f_out=0 lid=- lin=0 lout=0
        fi
        if [ "$size" -gt "$off" ] && [ "$(tail -c +"$size" "$f" | head -c 1 | od -An -tx1)" != " 0a" ]; then
            size=$(( size - $(tail -c +$((off + 1)) "$f" | head -c $((size - off)) | tail -n 1 | wc -c) ))
        fi
        if [ "$size" -gt "$off" ]; then
            read -r d_in d_out n_lid n_lin n_lout < <(tail -c +$((off + 1)) "$f" | head -c $((size - off)) \
                | grep -aF '"usage"' \
                | jq -nrR --arg lid "$lid" --argjson lin "$lin" --argjson lout "$lout" '
                    reduce (inputs | fromjson? | .message | select(.usage and .id)) as $m
                        ({ids: {}, last: $lid};
                         .ids[$m.id] = [$m.usage.input_tokens + ($m.usage.cache_creation_input_tokens // 0),
                                        $m.usage.output_tokens // 0]
                         | .last = $m.id)
                    | (if .ids | has($lid) then [$lin, $lout] else [0, 0] end) as $old
                    | ([.ids[]] | transpose | map(add)) as $sum
                    | (.ids[.last] // [$lin, $lout]) as $l
                    | "\(($sum[0] // 0) - $old[0]) \(($sum[1] // 0) - $old[1]) \(.last) \($l[0]) \($l[1])"' 2>/dev/null)
            if [ -n "$n_lout" ]; then
                lid=$n_lid lin=$n_lin lout=$n_lout
                f_in=$(( f_in + d_in ))
                f_out=$(( f_out + d_out ))
                off=$size
                echo "$f $off $f_in $f_out $lid $lin $lout" >> "$sub_cache"
            fi
        fi
        sub_in=$(( sub_in + f_in ))
        sub_out=$(( sub_out + f_out ))
        new_cache+="$f $off $f_in $f_out $lid $lin $lout"$'\n'
    done < <(find "$sub_dir" -name '*.jsonl' -printf '%p %s\n')
    printf '%s' "$new_cache" > "$sub_cache.$$" && mv "$sub_cache.$$" "$sub_cache"
fi


fmt_k() {
    local n=$1
    if [ -z "$n" ] || [ "$n" = "0" ]; then
        echo "0"
        return
    fi
    awk -v n="$n" 'BEGIN { if (n >= 999950) printf "%.1fM", n/1000000; else if (n >= 1000) printf "%.1fk", n/1000; else print n }'
}

# Ten-cell meter for percentage $1; filled cells shade green → yellow → red by
# position, and any nonzero value fills at least one cell.
bar() {
    local pct n i s=""
    pct=$(printf '%.0f' "$1")
    n=$(( (pct + 9) / 10 ))
    [ "$n" -gt 10 ] && n=10
    local cols=("$GREEN" "$GREEN" "$GREEN" "$GREEN" "$YELLOW" "$YELLOW" "$YELLOW" "$YELLOW" "$RED" "$RED")
    for ((i = 0; i < 10; i++)); do
        if [ "$i" -lt "$n" ]; then s+="${cols[$i]}▰"; else s+="${RST}${DIM}▱"; fi
    done
    printf '%s%s' "$s" "$RST"
}

# Two lines in five aligned columns, `top` over `bottom`: model over effort,
# context meter over token counts, idle timer over cache-miss warning, clod home
# over image and ports, git branch over lines changed. The 5h and 7d quota
# meters go at the right end of lines 1 and 2.
top=("" "" "" "" "")
bottom=("" "" "" "" "")

top[0]="${BOLD_CYAN}✨ ${model}${RST}"
[ -n "$effort" ] && bottom[0]="${DARK_CYAN}⚡ ${effort}${RST}"

# Percentages are padded to two digits so the meters keep their width.
if [ -n "$used_pct" ]; then
    ctx_int=$(printf '%.0f' "$used_pct")
    ctx_color=$WHITE
    [ "$ctx_int" -ge 60 ] && ctx_color=$YELLOW
    [ "$ctx_int" -ge 80 ] && ctx_color=$RED
    top[1]="${BOLD_BLUE}◔${RST} $(bar "$ctx_int") ${ctx_color}$(printf '%2d' "$ctx_int")%${RST}"
fi

# clod launch context: 🏠 home, 📦 image.
if [ -n "${CLOD_HOME:-}" ]; then
    top[3]="${BR_MAGENTA}🏠 ${CLOD_HOME}${RST}"
    [ -n "${CLOD_IMAGE:-}" ] && bottom[3]="${BROWN}📦 ${CLOD_IMAGE}${RST}"
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
    bottom[3]+="${bottom[3]:+  }$ports_part"
fi

# Git branch (short hash when detached) and ±N changed files, untracked included.
# A linked worktree (git dir differs from the common one) shows as 🌿 and its
# folder in place of 🪾 and the branch. A folder inside a host-mounted /workspace
# shows relative to it, which iTerm resolves against the folder clod ran from
# and opens on ⌘-click; any other shows only its name. The branch follows,
# dimmed, when it doesn't contain the folder's name.
if [ -n "$cwd" ] && branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null \
        || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null); then
    git_part="🪾 ${GREEN}${branch}${RST}"
    # Inside .git there is no top level, and rev-parse prints less.
    git_dir="" common_dir="" top_dir=""
    { read -r git_dir; read -r common_dir; read -r top_dir; } < <(git -C "$cwd" --no-optional-locks \
        rev-parse --path-format=absolute --git-dir --git-common-dir --show-toplevel 2>/dev/null) || true
    if [ -n "$git_dir" ] && [ "$git_dir" != "$common_dir" ]; then
        wt=${top_dir##*/}
        [ -n "${CLOD_WORKSPACE_PATH:-}" ] && [[ $top_dir == /workspace/* ]] && wt=${top_dir#/workspace/}
        git_part="🌿 ${GREEN}${wt}${RST}"
        [[ $branch == *"${top_dir##*/}"* ]] || git_part+=" ${DIM}${branch}${RST}"
    fi
    dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | wc -l) || dirty=0
    [ "$dirty" -gt 0 ] && git_part+=" ${YELLOW}±${dirty}${RST}"
    top[4]=$git_part
fi

bottom[1]="${BOLD_BLUE}↑${RST}${WHITE}$(fmt_k "$((cum_in + sub_in))")"$'\t'"${BOLD_BLUE}↓${RST}${WHITE}$(fmt_k "$((cum_out + prev_out + sub_out))")${RST}"

if [ "$lines_add" != "0" ] || [ "$lines_rm" != "0" ]; then
    bottom[4]="${GREEN}+${lines_add}${RST}${DIM}/${RST}${RED}-${lines_rm}${RST}"
fi

if [ "$last_activity" -gt 0 ]; then
    idle=$((now - last_activity))
    # Whole minutes, so the statusline output changes only once a minute while idle.
    idle_m=$((idle / 60))
    if [ "$idle" -ge 3600 ]; then
        top[2]=$(printf '%s💤 %dh%02dm%s' "$BOLD_RED" "$((idle_m / 60))" "$((idle_m % 60))" "$RST")
    else
        top[2]=$(printf '%s⏱%s %s%dm%s' "$BOLD_BLUE" "$RST" "$WHITE" "$idle_m" "$RST")
    fi
fi

# Quota meter $3 cells wide: used % $1, elapsed % $2. The dim ▱ track covers
# the elapsed share of the window and a dim ▁ line the time still to come, on
# the terminal's own background; the green fill is usage, and fill past the
# track is red. Usage rounds up to whole cells, elapsed to the nearest. The
# last usage cell shows the pace from the percentages themselves: red when
# usage is ahead of elapsed, yellow within 5 points behind it, green otherwise. Rounding moves usage at most one cell past
# the track, and that cell is the last, so red shows only when usage is ahead.
qbar() {
    local u=$1 e=$2 W=$3 s="" i pace
    local BG="" FUT="${DIM}▁"
    # Alternative: a gray background marking out all the cells, with blank
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

# Rate-limit meter: label $1 (pre-colored), used % $2, reset epoch $3, window
# seconds $4, $5 cells wide.
# The dim /N% after the value is how much of the window has elapsed; without a
# reset time the track spans the full width.
limit_part() {
    local label=$1 pct elapsed="" shown=""
    pct=$(printf '%.0f' "$2")
    if [ -n "$3" ]; then
        elapsed=$(awk -v n="$now" -v r="$3" -v w="$4" 'BEGIN { e = (n - (r - w)) * 100 / w; if (e < 0) e = 0; if (e > 100) e = 100; printf "%.0f", e }')
    fi
    [ -n "$elapsed" ] && printf -v shown '%s/%2d%%' "$DIM" "$elapsed"
    printf '%s %s %s%2d%%%s' "$label" "$(qbar "$pct" "${elapsed:-100}" "$5")" "$WHITE" "$pct" "$shown$RST"
}

# Miss warning, under the idle timer.
# Shown until the next typed user message (prompt_id change) or 2 minutes,
# whichever comes first — warm follow-up API calls in the same turn never hide it.
if [ "$last_miss" -gt 0 ] && [ "$prompt_id" = "$miss_prompt" ] && [ $((now - miss_ts)) -lt 120 ]; then
    if [ "$miss_kind" = "full" ]; then
        bottom[2]="${BOLD_RED}⚠ MISS $(fmt_k "$last_miss")${RST}"
    else
        bottom[2]="${YELLOW}⚠ miss $(fmt_k "$last_miss")${RST}"
    fi
fi

# Terminal columns taken by $1: escape codes (SGR colours, OSC 8 links) take
# none, and the emoji (✨ ⚡ 🏠 📦 💤) take two.
width() {
    local s=$1 narrow
    s=${s//$'\033['*([0-9;])m/}
    s=${s//$'\033]8;;'*([!$'\a'])$'\a'/}
    narrow=${s//[✨⚡🏠📦💤🪾🌿]/}
    echo $(( 2 * ${#s} - ${#narrow} ))
}

# Line $1 with $2 at its right end, starting no further left than column $3.
# Claude Code sets COLUMNS to the terminal width and shows COLUMNS - 4 columns
# of the statusline; without COLUMNS, or with too little room, $2 starts at $3.
row() {
    local left=$1 right=$2 start pad
    if [ -z "$right" ]; then
        echo "$left"
        return
    fi
    start=$(( ${COLUMNS:-0} - 4 - $(width "$right") ))
    [ "$start" -lt "$3" ] && start=$3
    printf -v pad '%*s' $(( start - $(width "$left") )) ""
    echo "$left$pad$right"
}

# Columns a cell takes: a tab in it marks where padding goes, at least 1 column.
cell_width() {
    if [[ $1 == *$'\t'* ]]; then
        echo $(( $(width "${1/$'\t'/}") + 1 ))
    else
        width "$1"
    fi
}

# Cell $1 padded with spaces to $2 columns, at its tab or else at its end.
fit() {
    local pad
    printf -v pad '%*s' $(( $2 - $(width "${1/$'\t'/}") )) ""
    if [[ $1 == *$'\t'* ]]; then
        echo "${1/$'\t'/$pad}"
    else
        echo "$1$pad"
    fi
}

# Each column is as wide as its wider cell, 3 spaces apart, and a column empty on
# both lines is left out. Claude Code trims leading spaces off each line, so the
# lines start with a reset code to keep the padding of an empty first cell.
line1=$RST
line2=$RST
for i in "${!top[@]}"; do
    a=${top[i]}
    b=${bottom[i]}
    [ -z "$a$b" ] && continue
    wa=$(cell_width "$a")
    wb=$(cell_width "$b")
    w=$(( wa > wb ? wa : wb ))
    if [ "$line1$line2" != "$RST$RST" ]; then
        line1+="   "
        line2+="   "
    fi
    line1+=$(fit "$a" "$w")
    line2+=$(fit "$b" "$w")
done
line1=${line1%%+( )}
line2=${line2%%+( )}

# The quota meters start at least 2 columns after the longer line. Their bars
# are 20 cells wide, 5% each, narrowed to as few as 10 to fit the terminal.
w1=$(width "$line1")
w2=$(width "$line2")
min_start=$(( (w1 > w2 ? w1 : w2) + 2 ))

quota_part() {
    local reset
    reset=$(echo "$input" | jq -r ".rate_limits.$1.resets_at // empty")
    limit_part "${BOLD_BLUE}$2${RST}" "$3" "$reset" "$4" "$5"
}
quota_meters() {
    five_part=""
    week_part=""
    [ -n "$five_pct" ] && five_part=$(quota_part five_hour 5h "$five_pct" 18000 "$1")
    [ -n "$week_pct" ] && week_part=$(quota_part seven_day 7d "$week_pct" 604800 "$1")
    return 0
}

# Measured without bars, the meters show how many cells the room left holds.
quota_meters 0
w5=$(width "$five_part")
w7=$(width "$week_part")
cells=$(( ${COLUMNS:-0} - 4 - min_start - (w5 > w7 ? w5 : w7) ))
[ "$cells" -gt 20 ] && cells=20
[ "$cells" -lt 10 ] && cells=10
quota_meters "$cells"

row "$line1" "$five_part" "$min_start"
row "$line2" "$week_part" "$min_start"


