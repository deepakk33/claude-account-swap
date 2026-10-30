# cswap bash completion. Install: add to ~/.bashrc
#   source /full/path/to/cswap-completion.bash
_cswap() {
  local reg="${XDG_CONFIG_HOME:-$HOME/.config}/cswap-min/slots"
  local cur="${COMP_WORDS[COMP_CWORD]}" cmd="${COMP_WORDS[1]}"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "save switch list current rename forget help" -- "$cur")); return
  fi
  case "$cmd" in
    switch|rename|forget)
      local names=""; [ -r "$reg" ] && names="$(cat "$reg")"
      COMPREPLY=($(compgen -W "$names _prev" -- "$cur")) ;;
  esac
}
complete -F _cswap cswap
