#!/bin/bash
# Renders the statusline picture in the docs: docs/statusline-svg.sh > docs/statusline.svg
# Runs shared/statusline.sh on sample input, with its state seeded so the idle
# timer and rate-limit windows show realistic values, then converts the output.
set -euo pipefail
docs=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
now=$(date +%s)
mkdir -p "$tmp/claude-statusline"
# a project on branch main with three changed files, for the git part
git init -q -b main "$tmp/project"
touch "$tmp/project/"{a,b,c}
# output tokens, cache created, last activity (25s ago), then no cache miss
echo "759 0 $((now - 25)) 0 0 - - 0 0" > "$tmp/claude-statusline/sample"
cat > "$tmp/input.json" <<JSON
{"model":{"display_name":"Opus 5.5"},"workspace":{"current_dir":"$tmp/project"},"effort":{"level":"medium"},"session_id":"sample","prompt_id":"p1",
 "context_window":{"total_input_tokens":710700,"total_output_tokens":759,"used_percentage":38,
   "current_usage":{"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},
 "cost":{"total_lines_added":957,"total_lines_removed":151},
 "rate_limits":{"five_hour":{"used_percentage":19,"resets_at":$((now + 18000 * 13 / 100))},
                "seven_day":{"used_percentage":32,"resets_at":$((now + 604800 * 46 / 100))}}}
JSON
{
  CLOD_HOME=work CLOD_IMAGE=go CLOD_PORTS=5173 TMPDIR=$tmp CLAUDE_CONFIG_DIR=$tmp \
    bash "$docs/../shared/statusline.sh" < "$tmp/input.json"
  # Claude Code's own mode line, which it shows below the statusline
  printf '\033[95m⏵⏵ bypass permissions on\033[0m \033[2m·\033[0m PR \033[4;93m#9\033[0m \033[2m·\033[0m \033[96m1 shell\033[0m \033[2m· ← for agents\033[0m\n'
} | python3 "$docs/ansi2svg.py"
