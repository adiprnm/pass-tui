# pass-tui

A terminal UI for the standard unix password manager, built on
[ruby-tui](https://github.com/adiprnm/ruby-tui). Two columns: an expandable
tree of your `pass` entries on the left, the selected entry's metadata on
the right.

```
╭ pass-tui ────────── ↑↓ select · enter open · / search · g sync · ? help · q quit ────────────────╮
│╭ Entries ────────────────── 4 entries ╮╭ Detail ─────────────── Ready. ──────────── example.com ╮│
││ search entries…                      ││ web › example.com                                      ││
││  ▸ app/                              ││────────────────────────────────────────────────────────││
││  ▾ web/                              ││╭ Password ────────────────────────────────  r reveal  ╮││
││▌     example.com                     │││ •••••••••                                            │││
││      other.org                       ││╰──────────────────────────────────────────────────────╯││
││    db                                ││                                                        ││
││                                      ││╭ User ──────────────────────────────────────  u copy  ╮││
││                                      │││ alice                                                │││
││                                      ││╰──────────────────────────────────────────────────────╯││
││                                      ││                                                        ││
││                                      ││╭ URL ─────────────────────────────────────────────────╮││
││                                      │││ https://example.com                                  │││
││                                      ││╰──────────────────────────────────────────────────────╯││
││                                      ││                                                        ││
││                                      ││╭ Notes ───────────────────────────────────────────────╮││
││                                      │││ recovery codes:                                      │││
││                                      │││   1111 2222                                          │││
││                                      ││╰──────────────────────────────────────────────────────╯││
╰──────────────────────────────────────╯╰────────────────────────────────────────────────────────╯│
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
```

Nothing about `pass` is reimplemented: decryption, encryption and deletion
all go through the `pass` CLI, so gpg-agent, pinentry and your `.gpg-id`
setup keep working exactly as configured.

## Design

Every credential field is drawn the way HTML draws an input: its own
bordered box with the field's name as the *legend* on the top border, and
the key that acts on it on the right of the legend. Folders get a short
`Summary`/`Contents` card instead.

The one place colour means something is a revealed secret. While a password
is sealed its compartment is amber and its value is bullets; press `r` and
the whole compartment turns red, because an exposed password is worth
noticing.

`vault` (the default) follows the same idea as todotui: the chrome is
cool graphite and the *data* carries the colour, so the eye lands on the
credential rather than the frame. One warm accent (amber) marks folders,
the selected row's `▌` marker and the password legend; each kind of field
gets a stable colour -- user green, url blue, extra keys soft, notes grey,
and a revealed secret red. Body text stays on the terminal's own
foreground, so values always read. The selected tree row highlights only
the row's own text, not the whole pane.

`--theme=plain` drops every colour code and keeps the vocabulary legible
through weight instead (bold / underline / reverse).

## Requirements

* [`pass`](https://www.passwordstore.org/) on `PATH`.
* `ruby-tui` next to this project (`../ruby-tui`), or set `RUBY_TUI_LIB` to
  its `lib/` directory. It is **not** installed as a gem yet, so the entry
  point adds it to the load path.
* A clipboard tool: `wl-copy` (Wayland), `xclip`/`xsel` (X11) or `pbcopy`.
* Ruby 2.0+ for the interpreter, or Spinel for an AOT binary.

## Install

Put `pass-tui` on `PATH` as `pt`, so it can be called from any directory:

```sh
rake install            # ~/.local/bin/pt -> bin/pass-tui (a link)
```

`rake install` makes a link to the launcher, so `pt` always runs the
current sources -- no rebuild while developing. It needs Ruby and the
sibling `ruby-tui` checkout at run time. Override the location/name with
`BINDIR=` / `NAME=`.

For a standalone command with no Ruby or gems at run time, compile the
Spinel binary and install that instead (rebuild after a change):

```sh
rake install:spinel     # builds, then copies the native binary to ~/.local/bin/pt
rake uninstall          # remove it again
```

## Running

```sh
pt                                        # interactive
pt --store=~/.password-store              # a different store
pt --config=/tmp/cfg.json                 # a different config file
pt --theme=plain                          # no colours at all
pt --list                                 # entry names, no tty needed
pt --sync                                 # git pull + push the store, then exit
pt --snapshot --w=100 --h=30              # one frame to stdout
```

The `bin/pass-tui` path works too, from inside the checkout.

## Keys

| key | action |
| --- | --- |
| `↑` `↓` / `j` `k` | move the tree cursor |
| `enter` | open/close a folder; reveal the selected password |
| `→` / `l` | expand a folder |
| `←` / `h` | collapse a folder |
| `/` | search (filters the tree to matching entries) |
| `tab` | move focus |
| `r` | toggle reveal |
| `c` | copy the password (auto-cleared) |
| `u` | copy the `user:` field |
| `n` | new entry (a form: name, username, password) |
| `e` | edit the entry (opens `$EDITOR`) |
| `d` | delete (`y`/`enter` confirms, `n`/`esc` cancels) |
| `g` | sync the store over git (`pull --rebase`, then `push`) |
| `s` | settings |
| `?` | help |
| `ctrl-d` / `ctrl-u` | scroll the detail pane |
| `q` / `ctrl-c` | quit |

## Configuration

pass-tui keeps its own settings -- it does not write to `pass`'s files. By
default they live in `~/.config/pass-tui/config.json`; edit them by hand or
from the in-app Settings dialog (`s`).

```json
{
  "store_dir": "/home/me/.password-store",
  "clip_time": 45,
  "editor": "nvim",
  "theme": "vault"
}
```

* `store_dir` -- the password store. On first run it is seeded from
  `PASSWORD_STORE_DIR`, else `~/.password-store`.
* `clip_time` -- seconds before the clipboard is emptied (seeded from
  `PASSWORD_STORE_CLIP_TIME`, default 45).
* `editor` -- used for `n`/`e`. Seeded from `$VISUAL`/`$EDITOR`.
* `theme` -- `vault` (default) or `plain`. `vault` is the graphite chrome
  with an amber accent and a colour per field kind, described above;
  `plain` drops the colour codes and keeps meaning through attributes.

The command-line `--store`/`--theme` flags override the file for one run.

## Storage format

pass-tui writes entries with the field name on every line, username first:

```
username:carol
password:s3cret
```

It is still the ordinary `pass` file, just labelled. Reading is tolerant:
a `password:` line is taken as the password wherever it sits, and the
classic layout -- the bare password on the first line, then `key: value`
metadata -- is understood too, so entries made by `pass` or other tools
keep working:

```
s3cret
user: alice
url: https://example.com
```

A value may contain a colon (`password:ht:tp://x` keeps the whole value),
and a bare URL line stays a note rather than becoming a field.

### Editor and pinentry

Adding an entry (`n`) is a form in the TUI: you fill in the name, username
and password, and pass-tui pipes `username:...\npassword:...` straight into
`pass insert -m`, so no editor is involved. Editing an existing entry (`e`)
still suspends the TUI (leaving the alternate screen and raw mode), runs
`pass edit`, then re-enters. Reading an entry runs `pass show` with captured
output; a GUI pinentry never touches the terminal, and after the first
unlock gpg-agent caches the key. The default pinentry on a Wayland session
(`pinentry-gnome3`) works this way.

## Clipboard

The first of `wl-copy`, `xclip`, `xsel`, `pbcopy` found on `PATH` is used.
After `clip_time` seconds the selection is cleared, and it is cleared on
quit as well.

## Sync over git

`pass` already versions the store with git when it lives in a repository
(`pass git init`), committing every insert/edit/rm for you. pass-tui adds
the missing half -- moving those commits to and from a remote:

* `g` in the TUI, or `pt --sync` from a script, runs `pass git pull
  --rebase` followed by `pass git push` and then reloads the tree, so
  changes made on another machine appear without restarting.
* In the TUI the sync runs on a background thread: the tree, search and
  detail pane stay responsive while git talks to the network. A `⟳
  syncing…` marker appears in the top-right corner until it finishes, and
  the status bar reports the result. Pressing `g` again while one is
  running is ignored.
* The store's environment is placed on the git command line rather than in
  the process environment, so a background sync never races the foreground
  `pass show` that is decrypting the selected entry.
* A store that is not a git repository is left alone, with a note in the
  status bar instead of a failing command.
* `GIT_TERMINAL_PROMPT=0` is set for the subprocess, so a remote that
  wants credentials fails immediately rather than freezing the TUI. Cache
  the credentials (`git credential-store`, an SSH agent, or a token in the
  remote URL) for unattended sync.

## Building with Spinel

The project is written to compile ahead-of-time with
[Spinel](https://github.com/adiprnm/spinel): no YAML, no `Open3`, no
`Shellwords`, no `OptionParser.new { }` block, no splatted `system`. Config
is JSON (Spinel ships a json package), process I/O uses backticks plus a
hand-quoted command line, and `$?` is read in a way that works whether it
is a `Process::Status` or a plain Integer.

```sh
rake spinel
# or
spinel bin/pass-tui -o build/pass-tui -I lib -I ../ruby-tui/lib
./build/pass-tui --list
```

Spinel prints two `load-path manipulation is meaningless` warnings for the
`$LOAD_PATH.unshift` lines; those lines only matter to the CRuby
interpreter, and Spinel resolves the same requires from the `-I` flags.
The output binary is standalone.

## Tests

```sh
ruby test/run.rb      # or: rake test
```

58 tests, stdlib only, on the same tiny harness ruby-tui uses: config,
entry parsing, the tree model, the store and clipboard shell plumbing, the
UI (including the fieldset layout and the reveal state) driven off-screen,
and one end-to-end session in a pty that asserts the terminal is restored.

## Layout

```
bin/pass-tui                 entry point (manual argv parsing)
lib/pass_tui.rb              requires everything
lib/pass_tui/
  theme.rb                   the vault / plain / dark palettes
  config.rb                  JSON settings
  entry.rb                   parse `pass show` output
  tree.rb                    entry names -> folder tree -> rows
  store.rb                   the `pass` CLI bridge
  clipboard.rb               wl-copy / xclip / xsel / pbcopy
  shell.rb                   quoting + $? (Spinel-safe)
  editing.rb                 suspend/resume around $EDITOR
  ui/tree_view.rb            the expandable tree component
  ui/fieldset.rb             a field as a bordered box + legend
  ui/app.rb                  the application, layout and key bindings
test/                        the suite
```
