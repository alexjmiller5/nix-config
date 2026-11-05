# Keep the last command as the native Herdr terminal title, including at the prompt.
[[ -n ${HC_TERMINAL_ID:-} ]] || return 0
autoload -Uz add-zsh-hook
_herdr_command_title() {
  [[ -n ${_herdr_last_command:-} ]] && printf '\033]2;%s\007' "$_herdr_last_command"
  return 0
}
_herdr_command_preexec() {
  _herdr_last_command=${1//[[:cntrl:]]/ }
  _herdr_last_command=${_herdr_last_command[1,120]}
  _herdr_command_title
}
add-zsh-hook preexec _herdr_command_preexec
add-zsh-hook precmd _herdr_command_title
