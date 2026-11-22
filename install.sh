#!/bin/sh
# install.sh — add goto.sh to the current shell's rc file.
#
# Detects zsh or bash from $SHELL, then adds an idempotent marker block to
# ~/.zshrc or ~/.bashrc that sources the goto.sh located next to this script.
# It cannot source anything into the shell that launched it; it prints the
# command to activate goto in that shell.

set -u

install_dir=$(cd -- "$(dirname -- "$0")" && pwd -P) || {
  printf 'install: cannot determine the script directory\n' >&2
  exit 1
}
goto_sh="$install_dir/goto.sh"

if [ ! -f "$goto_sh" ]; then
  printf 'install: goto.sh not found next to this script: %s\n' "$goto_sh" >&2
  exit 1
fi

if [ -z "${HOME:-}" ]; then
  printf 'install: HOME is not set; cannot locate your shell rc file\n' >&2
  exit 1
fi

shell_name=
case "${SHELL:-}" in
  */zsh|zsh) shell_name=zsh ;;
  */bash|bash) shell_name=bash ;;
  '')
    if [ -n "${ZSH_VERSION:-}" ]; then
      shell_name=zsh
    elif [ -n "${BASH_VERSION:-}" ]; then
      shell_name=bash
    fi
    ;;
esac

if [ -z "$shell_name" ]; then
  printf 'install: unsupported shell: %s (expected zsh or bash)\n' \
    "${SHELL:-unknown}" >&2
  printf 'install: add this line to your shell rc manually:\n' >&2
  printf '    source "%s"\n' "$goto_sh" >&2
  exit 1
fi

case "$shell_name" in
  zsh) rc="$HOME/.zshrc" ;;
  bash) rc="$HOME/.bashrc" ;;
esac

# Build a double-quoted shell literal for the path. Escape in this order:
# backslashes first, then the characters special inside double quotes.
escaped=$(printf '%s' "$goto_sh" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
  -e 's/\$/\\$/g' -e 's/`/\\`/g') || {
  printf 'install: cannot prepare the source line\n' >&2
  exit 1
}
source_line="source \"$escaped\""

start_marker='# >>> goto >>>'

if [ -e "$rc" ] && [ ! -f "$rc" ]; then
  printf 'install: rc path is not a regular file: %s\n' "$rc" >&2
  exit 1
fi

if [ ! -e "$rc" ]; then
  if ! : > "$rc"; then
    printf 'install: cannot create %s\n' "$rc" >&2
    exit 1
  fi
fi

had_block=0
if grep -Fqx "$start_marker" "$rc"; then
  had_block=1
elif grep -Fqx "$source_line" "$rc"; then
  printf 'install: goto is already sourced by %s\n' "$rc"
  exit 0
fi

tmp=
cleanup() {
  if [ -n "$tmp" ]; then
    rm -f "$tmp"
  fi
}
trap cleanup 0
trap 'exit 1' 1 2 15

if ! tmp=$(mktemp "$rc.goto.tmp.XXXXXX"); then
  printf 'install: cannot create a temporary file next to %s\n' "$rc" >&2
  exit 1
fi

if ! _GOTO_INSTALL_LINE="$source_line" awk '
  BEGIN {
    start = "# >>> goto >>>"
    end = "# <<< goto <<<"
    line = ENVIRON["_GOTO_INSTALL_LINE"]
  }
  $0 == start {
    if (!seen) {
      print start
      print line
      print end
      seen = 1
    }
    inblock = 1
    next
  }
  inblock {
    if ($0 == end) inblock = 0
    next
  }
  { print }
  END {
    if (inblock) exit 4
    if (!seen) {
      print ""
      print start
      print line
      print end
    }
  }
' "$rc" > "$tmp"; then
  printf 'install: failed to prepare an update for %s\n' "$rc" >&2
  exit 1
fi

if cmp -s "$tmp" "$rc"; then
  printf 'install: goto is already sourced by %s\n' "$rc"
  exit 0
fi

if ! cat "$tmp" > "$rc"; then
  printf 'install: failed to write %s\n' "$rc" >&2
  exit 1
fi

if [ "$had_block" -eq 1 ]; then
  printf 'install: updated the goto block in %s\n' "$rc"
else
  printf 'install: added goto to %s\n' "$rc"
fi
printf 'install: it will be loaded in new shells; activate it now with:\n'
printf '    source "%s"\n' "$rc"
