# goto

Directory shortcuts for zsh and bash. Bookmark a directory once, then jump to it
from anywhere:

```sh
cd ~/work/projectA
goto register projectA      # bookmark the current directory as "projectA"

cd /
goto projectA               # back to ~/work/projectA
```

`goto` is a sourced shell function (not a binary), because only the parent shell
can change its own working directory.

## Requirements

- zsh or bash (macOS default zsh, bash 3.2+)
- standard POSIX tools: `awk`, `sed`, `grep`, `mktemp`, `cmp`, `mkdir`, `mv`, `chmod`
- macOS or Linux

## Install

`install.sh` installs `goto` by adding it to your shell's rc file. Run it from
this directory:

```sh
./install.sh
```

Then activate it with:

```sh
source ~/.zshrc    # or ~/.bashrc
```

or simply open a new shell.

### Manual install

Instead of the installer, add this line to your zsh or bash rc file:

```sh
source "/Users/dawn/agents/dawnXW/goto/goto.sh"
```

Then open a new shell and check that it works:

```sh
goto help
```

## Usage

| Command | Effect |
| --- | --- |
| `goto <name>` | Jump to a registered shortcut |
| `goto <path>` | Jump to an existing directory (`goto ..`, `goto /tmp`, `goto ./build`) |
| `goto register <name> [path]` | Register or update a shortcut; path defaults to `$PWD` |
| `goto add <name> [path]` | Alias for `register` |
| `goto list` / `goto ls` | List shortcuts as `name<TAB>path` |
| `goto remove <name>` | Remove a shortcut (`rm`, `unregister` also work) |
| `goto help` | Show usage |
| `goto` | Show usage and registered shortcuts |

Examples:

```sh
# bookmark the current directory
goto register projectA

# bookmark an explicit directory (absolute, relative or unquoted ~ path)
goto register blog ~/src/blog
goto register build ./build

# update a shortcut (re-registering replaces the path, never duplicates)
cd ~/work/projectA-v2
goto register projectA

goto list
goto projectA
goto remove blog
```

Details:

- Names may contain letters, digits, `.`, `_` and `-`, and cannot start with `-`.
- `help`, `register`, `add`, `list`, `ls`, `remove`, `rm` and `unregister` are
  reserved names.
- A registered name wins over a directory with the same name. Use `./name` or an
  absolute path to force the directory.
- Paths are stored as absolute physical paths (symlinks resolved).
- If a target directory disappears, `goto` reports it and suggests re-registering;
  the entry is not removed automatically.
- Paths containing a tab or newline cannot be registered.

## Registry

Shortcuts live in:

```
${GOTO_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/goto}/registry
```

which defaults to `~/.config/goto/registry`. It is a plain text file with one
`name<TAB>path` record per line; blank lines and lines starting with `#` are
ignored. The directory is created `0700` and the file `0600`.

You can point `GOTO_CONFIG_DIR` somewhere else before sourcing `goto.sh` (useful
for tests).

## Uninstall

1. Remove the marker block from `~/.zshrc` / `~/.bashrc`:

   ```sh
   # >>> goto >>>
   source "/path/to/goto/goto.sh"
   # <<< goto <<<
   ```

   (or remove the manual `source .../goto.sh` line, if that is how you installed).
2. Optionally delete the registry:
   `rm -rf "${GOTO_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/goto}"`.

## Notes

- Running `goto.sh` directly prints an error; it must be sourced.
- Status messages and errors go to stderr; `goto list` data goes to stdout.
- Design and implementation notes: [DESIGN.md](DESIGN.md).
