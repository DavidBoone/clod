# shellcheck shell=bash
# clod's tab completion for bash, which bash-completion loads from its
# completions directory, where clod install links it as clod. It hands the
# words to clod __complete, and completes file names only when that exits 1.

_clod() {
  local out line
  COMPREPLY=()
  out=$(clod __complete "${COMP_WORDS[@]:1:$COMP_CWORD}") || {
    compopt -o default 2>/dev/null
    return 0
  }
  # Each candidate is a word with any description after a tab, which bash
  # doesn't show. A folder, ending in /, takes no space after it.
  while IFS= read -r line; do
    [[ -n $line ]] && COMPREPLY+=("${line%%$'\t'*}")
    [[ $line == */ ]] && compopt -o nospace 2>/dev/null
  done <<<"$out"
}
# bash 3.2 has no compopt, so there it falls back to file names whenever
# nothing else matches.
if type compopt >/dev/null 2>&1; then
  complete -F _clod clod
else
  complete -o default -F _clod clod
fi
