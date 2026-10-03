#!/bin/bash
# Renders the README's statusline picture: docs/statusline-svg.sh > docs/statusline.svg
# Runs shared/statusline.sh on sample input, with its state seeded so the idle
# timer and rate-limit windows show realistic values, then converts the output.
set -euo pipefail
docs=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
now=$(date +%s)
mkdir -p "$tmp/claude-statusline"
# output tokens, cache created, last activity (25s ago), then no cache miss
echo "759 0 $((now - 25)) 0 0 - - 0 0" > "$tmp/claude-statusline/sample"
cat > "$tmp/input.json" <<JSON
{"model":{"display_name":"Opus 5.5"},"effort":{"level":"medium"},"session_id":"sample","prompt_id":"p1",
 "context_window":{"total_input_tokens":710700,"total_output_tokens":759,"used_percentage":38,
   "current_usage":{"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},
 "cost":{"total_lines_added":957,"total_lines_removed":151},
 "rate_limits":{"five_hour":{"used_percentage":19,"resets_at":$((now + 18000 * 13 / 100))},
                "seven_day":{"used_percentage":32,"resets_at":$((now + 604800 * 46 / 100))}}}
JSON
CLOD_HOME=work CLOD_IMAGE=clod-go TMPDIR=$tmp CLAUDE_CONFIG_DIR=$tmp \
  bash "$docs/../shared/statusline.sh" < "$tmp/input.json" | python3 "$docs/ansi2svg.py"
