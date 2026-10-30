# cswap zsh completion. Install:
#   mkdir -p ~/.zsh/completions
#   cp cswap-completion.zsh ~/.zsh/completions/_cswap   # (or source it from ~/.zshrc)
# then in ~/.zshrc (once):
#   fpath=(~/.zsh/completions $fpath)
#   autoload -Uz compinit && compinit
#   zstyle ':completion:*' menu select          # TAB cycles choices one by one
# Reload: exec zsh
#
# If you'd rather not deal with fpath, just add to ~/.zshrc:
#   source /full/path/to/cswap-completion.zsh

# Sourced from a bare ~/.zshrc that never ran compinit, compdef does not exist yet.
(( $+functions[compdef] )) || { autoload -Uz compinit && compinit -i; }

_cswap() {
  local reg="${XDG_CONFIG_HOME:-$HOME/.config}/cswap-min/slots"
  local -a cmds slots
  cmds=(save switch list current rename forget help)
  if (( CURRENT == 2 )); then
    compadd -- $cmds
    return
  fi
  case "${words[2]}" in
    switch|rename|forget)
      [[ -r "$reg" ]] && slots=(${(f)"$(<"$reg")"})
      slots+=(_prev)
      compadd -- $slots
      ;;
  esac
}
compdef _cswap cswap
