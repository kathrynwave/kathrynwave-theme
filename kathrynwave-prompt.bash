# kathrynwave Bash prompt.
# Source this from ~/.bashrc in interactive Bash sessions.

case $- in
  *i*) ;;
  *) return ;;
esac

__kathrynwave_git_branch() {
  command -v git >/dev/null 2>&1 || return 0

  branch="$(git branch --show-current 2>/dev/null || true)"
  if [ -z "$branch" ]; then
    branch="$(git rev-parse --short HEAD 2>/dev/null || true)"
  fi

  [ -n "$branch" ] || return 0
  printf ' \[\033[38;5;214m\]git:\[\033[38;5;213m\]%s\[\033[0m\]' "$branch"
}

__kathrynwave_reset_input_color() {
  trap - DEBUG
  printf '\033[0m'
}

__kathrynwave_prompt_command() {
  last_status=$?
  trap - DEBUG

  title='\[\e]0;\u@\h: \w\a\]'
  user='\[\033[38;5;207;1m\]\u'
  at='\[\033[38;5;99m\]@'
  host='\[\033[38;5;51;1m\]\h'
  colon='\[\033[38;5;99m\]:'
  path='\[\033[38;5;75;1m\]\w'
  prompt='\[\033[38;5;214;1m\]\$'
  input='\[\033[38;5;231;1m\]'
  reset='\[\033[0m\]'
  git_info="$(__kathrynwave_git_branch)"

  if [ "$last_status" -eq 0 ]; then
    status=''
  else
    status=" \[\033[38;5;203m\]$last_status\[\033[0m\]"
  fi

  PS1="${title}${user}${at}${host}${colon}${path}${git_info}${status}${prompt}${reset} ${input}"
  trap '__kathrynwave_reset_input_color' DEBUG
}

PROMPT_COMMAND="__kathrynwave_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
