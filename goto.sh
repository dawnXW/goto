#!/usr/bin/env bash
# goto.sh — jump to a directory by shortcut name (zsh / bash).
#
# This file must be sourced, because a child process cannot change its parent
# shell's working directory:
#
#   source /path/to/goto.sh
#
# Running it directly prints an error.

# --- sourced-vs-executed guard ------------------------------------------------

_goto_executed=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file*) : ;;
    *) _goto_executed=1 ;;
  esac
elif [ -n "${BASH_VERSION:-}" ]; then
  if [ "${BASH_SOURCE:-}" = "$0" ]; then
    _goto_executed=1
  fi
fi

if [ "$_goto_executed" -eq 1 ]; then
  printf '%s\n' \
    "goto: this file must be sourced, not executed." \
    "      Add this line to ~/.zshrc or ~/.bashrc:" \
    "          source /path/to/goto.sh" >&2
  exit 1
fi
unset _goto_executed

# --- configuration ------------------------------------------------------------

_GOTO_CONFIG_DIR="${GOTO_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/goto}"
_GOTO_REGISTRY="$_GOTO_CONFIG_DIR/registry"

# --- helpers ------------------------------------------------------------------

_goto_err() {
  printf 'goto: %s\n' "$*" >&2
}

_goto_valid_name() {
  local name="$1"

  case "$name" in
    '')
      _goto_err "name must not be empty"
      return 1
      ;;
    -*)
      _goto_err "name must not start with '-'"
      return 1
      ;;
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*)
      _goto_err "invalid name '$name' (use letters, digits, '.', '_' or '-')"
      return 1
      ;;
  esac

  case "$name" in
    help|-h|--help|register|add|list|ls|remove|rm|unregister|--)
      _goto_err "name '$name' is reserved"
      return 1
      ;;
  esac

  return 0
}

_goto_init() {
  if [ ! -d "$_GOTO_CONFIG_DIR" ]; then
    if ! mkdir -p -- "$_GOTO_CONFIG_DIR"; then
      _goto_err "cannot create config directory: $_GOTO_CONFIG_DIR"
      return 1
    fi
    if ! chmod 700 "$_GOTO_CONFIG_DIR"; then
      _goto_err "cannot set permissions on: $_GOTO_CONFIG_DIR"
      return 1
    fi
  fi

  if [ ! -f "$_GOTO_REGISTRY" ]; then
    if [ -e "$_GOTO_REGISTRY" ]; then
      _goto_err "registry is not a regular file: $_GOTO_REGISTRY"
      return 1
    fi
    if ! (umask 077; : > "$_GOTO_REGISTRY"); then
      _goto_err "cannot create registry: $_GOTO_REGISTRY"
      return 1
    fi
  fi

  return 0
}

# Print the path registered for $1 and return 0, or return 1 if absent.
_goto_lookup() {
  local name="$1"

  [ -f "$_GOTO_REGISTRY" ] || return 1

  _GOTO_AWK_NAME="$name" awk -F '\t' '
    BEGIN { n = ENVIRON["_GOTO_AWK_NAME"] }
    $1 == n { print $2; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$_GOTO_REGISTRY"
}

# --- subcommands --------------------------------------------------------------

_goto_help() {
  cat <<'EOF'
goto — jump to a directory by shortcut name

Usage:
  goto                      Show this help and registered shortcuts
  goto <name|path>          cd to a registered name, or an existing directory
  goto register <name> [path]
                            Register or update <name>; path defaults to $PWD
  goto list                 List registered shortcuts
  goto remove <name>        Remove a shortcut (aliases: rm, unregister)
  goto help                 Show this help

Names may contain letters, digits, '.', '_' and '-', but cannot start with '-'.
Paths are stored as absolute, physical paths.

Examples:
  goto register projectA              bookmark the current directory
  goto register projectA ~/work/app   bookmark an explicit directory
  goto projectA                       jump to it later
  goto remove projectA                delete the bookmark
EOF
  printf 'Registry: %s\n' "$_GOTO_REGISTRY"
}

_goto_list() {
  local rc

  if [ ! -e "$_GOTO_REGISTRY" ]; then
    _goto_err "no shortcuts registered yet"
    return 0
  fi

  if [ ! -f "$_GOTO_REGISTRY" ]; then
    _goto_err "registry is not a regular file: $_GOTO_REGISTRY"
    return 1
  fi

  if awk -F '\t' '
    NF == 0 || $1 ~ /^#/ { next }
    { print; count++ }
    END { if (count == 0) exit 3 }
  ' "$_GOTO_REGISTRY"; then
    return 0
  else
    rc=$?
    if [ "$rc" -eq 3 ]; then
      _goto_err "no shortcuts registered yet"
      return 0
    fi
    _goto_err "cannot read registry: $_GOTO_REGISTRY"
    return 1
  fi
}

_goto_register() {
  local name src target old tmp existed=0

  if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    _goto_err "usage: goto register <name> [path]"
    return 1
  fi

  name=$1
  if [ $# -eq 2 ]; then
    src=$2
  else
    src=$PWD
  fi

  _goto_valid_name "$name" || return 1

  case "$src" in
    *$'\t'*|*$'\n'*)
      _goto_err "path contains a tab or newline; cannot register"
      return 1
      ;;
  esac

  if [ ! -e "$src" ]; then
    _goto_err "no such directory: $src"
    return 1
  fi
  if [ ! -d "$src" ]; then
    _goto_err "not a directory: $src"
    return 1
  fi

  if ! target=$(builtin cd -- "$src" && pwd -P); then
    _goto_err "cannot access directory: $src"
    return 1
  fi

  case "$target" in
    *$'\t'*|*$'\n'*)
      _goto_err "path contains a tab or newline; cannot register"
      return 1
      ;;
  esac

  if old=$(_goto_lookup "$name") && [ -n "$old" ]; then
    existed=1
  fi

  _goto_init || return 1

  tmp="$_GOTO_REGISTRY.tmp.$$"
  if ! (umask 077; _GOTO_AWK_NAME="$name" _GOTO_AWK_PATH="$target" \
    awk -F '\t' -v OFS='\t' '
      BEGIN {
        n = ENVIRON["_GOTO_AWK_NAME"]
        p = ENVIRON["_GOTO_AWK_PATH"]
      }
      $1 == n {
        if (!done) { print n, p; done = 1 }
        next
      }
      { print }
      END { if (!done) print n, p }
    ' "$_GOTO_REGISTRY" > "$tmp"); then
    rm -f -- "$tmp"
    _goto_err "cannot update registry: $_GOTO_REGISTRY"
    return 1
  fi

  if ! mv -- "$tmp" "$_GOTO_REGISTRY"; then
    rm -f -- "$tmp"
    _goto_err "cannot replace registry: $_GOTO_REGISTRY"
    return 1
  fi

  if [ "$existed" -eq 1 ]; then
    _goto_err "updated '$name' -> $target"
  else
    _goto_err "registered '$name' -> $target"
  fi

  return 0
}

_goto_remove() {
  local name tmp

  if [ $# -ne 1 ]; then
    _goto_err "usage: goto remove <name>"
    return 1
  fi

  name=$1
  _goto_valid_name "$name" || return 1

  if ! _goto_lookup "$name" >/dev/null; then
    _goto_err "no shortcut named '$name'"
    return 1
  fi

  tmp="$_GOTO_REGISTRY.tmp.$$"
  if ! (umask 077; _GOTO_AWK_NAME="$name" awk -F '\t' '
    BEGIN { n = ENVIRON["_GOTO_AWK_NAME"] }
    $1 != n
  ' "$_GOTO_REGISTRY" > "$tmp"); then
    rm -f -- "$tmp"
    _goto_err "cannot update registry: $_GOTO_REGISTRY"
    return 1
  fi

  if ! mv -- "$tmp" "$_GOTO_REGISTRY"; then
    rm -f -- "$tmp"
    _goto_err "cannot replace registry: $_GOTO_REGISTRY"
    return 1
  fi

  _goto_err "removed '$name'"
  return 0
}

# --- cd resolution ------------------------------------------------------------

_goto_cd() {
  local name="$1" target

  if target=$(_goto_lookup "$name") && [ -n "$target" ]; then
    :
  elif [ -d "$name" ]; then
    if ! target=$(builtin cd -- "$name" && pwd -P); then
      _goto_err "cannot access directory: $name"
      return 1
    fi
  else
    _goto_err "no shortcut or directory named '$name'"
    return 1
  fi

  if [ ! -d "$target" ]; then
    _goto_err "'$name' points to a missing directory: $target"
    _goto_err "re-register with: goto register $name <path>"
    return 1
  fi

  builtin cd -- "$target"
}

# --- public dispatcher --------------------------------------------------------

goto() {
  if [ $# -eq 0 ]; then
    _goto_help
    _goto_list
    return $?
  fi

  case "$1" in
    help|-h|--help)
      if [ $# -ne 1 ]; then
        _goto_err "usage: goto help"
        return 1
      fi
      _goto_help
      ;;
    register|add)
      shift
      _goto_register "$@"
      ;;
    list|ls)
      if [ $# -ne 1 ]; then
        _goto_err "usage: goto list"
        return 1
      fi
      _goto_list
      ;;
    remove|rm|unregister)
      shift
      _goto_remove "$@"
      ;;
    -*)
      _goto_err "unknown option '$1'"
      return 1
      ;;
    *)
      if [ $# -ne 1 ]; then
        _goto_err "usage: goto <name|path>"
        return 1
      fi
      _goto_cd "$1"
      ;;
  esac
}
