JACK_DESC="Emit shell completion scripts"
JACK_ABOUT="Prints scripts that make your shell complete jack commands with Tab. It only prints text. Nothing changes until you add the eval line to your shell config."
JACK_DOC_zsh="Print the zsh completion script, for eval in .zshrc after compinit"
JACK_USAGE_zsh=""
JACK_DOC_bash="Print the bash completion script, for eval in .bashrc"
JACK_USAGE_bash=""
JACK_INFO_zsh="Prints the zsh completion script. Put eval of its output in .zshrc after compinit and Tab will complete themes and actions. Changes no files by itself."
JACK_INFO_bash="Prints the bash completion script. Put eval of its output in .bashrc and Tab will complete themes and actions. Changes no files by itself."

completion_zsh() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage completion zsh)"
  cat <<'EOF'
_jack() {
  local -a items
  items=(${(f)"$(jack __complete --desc "${(@)words[2,CURRENT]}" 2>/dev/null)"})
  (( ${#items} )) && _describe 'jack' items
}
(( $+functions[compdef] )) && compdef _jack jack
EOF
}

completion_bash() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage completion bash)"
  cat <<'EOF'
_jack_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local -a words=("${COMP_WORDS[@]:1:COMP_CWORD}")
  local IFS=$'\n'
  COMPREPLY=($(compgen -W "$(jack __complete "${words[@]}" 2>/dev/null)" -- "$cur"))
}
complete -F _jack_complete jack
EOF
}
