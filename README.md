# cswap — minimal Claude Code account switcher

Switch between multiple Claude Code accounts **mid-session** — no `/logout`, no restart.
macOS and Linux. One bash script, no package, no dependencies beyond `python3`.

```bash
cswap save work        # back up whoever is logged in right now
cswap switch personal  # billing/quota flips instantly
cswap list             # see your slots
```

---

## Install

Copy-paste the whole block. It works the same in bash and zsh — it writes to whichever
one you actually use, and does not need a shell restart.

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/deepakk33/claude-account-swap/main/cswap-min.sh -o ~/.local/bin/cswap
chmod +x ~/.local/bin/cswap

RC=~/.bashrc; [ -n "${ZSH_VERSION:-}" ] && RC=~/.zshrc
grep -qs '.local/bin' "$RC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
export PATH="$HOME/.local/bin:$PATH"
```

Verify — in the same terminal, no reopening needed:

```bash
cswap --help
```

<details>
<summary>Prefer to read the script before running it? (recommended)</summary>

```bash
git clone https://github.com/deepakk33/claude-account-swap.git
cd claude-account-swap
less cswap-min.sh          # ~300 lines, all of it readable
mkdir -p ~/.local/bin && cp cswap-min.sh ~/.local/bin/cswap && chmod +x ~/.local/bin/cswap
```
</details>

### Requirements

- Claude Code, logged into at least one account
- `bash` (the script runs under bash even if your login shell is zsh, fish or something else)
- `python3` — check with `python3 --version`

Missing `python3`? It is absent from many minimal Linux images:

```bash
sudo apt install -y python3        # Debian / Ubuntu
sudo dnf install -y python3        # Fedora / RHEL
sudo pacman -S python              # Arch
xcode-select --install             # macOS
```

### TAB-completion (optional)

Same deal — one block, picks the right file for your shell:

```bash
RC=~/.bashrc; F=cswap-completion.bash
[ -n "${ZSH_VERSION:-}" ] && { RC=~/.zshrc; F=cswap-completion.zsh; }
curl -fsSL "https://raw.githubusercontent.com/deepakk33/claude-account-swap/main/$F" -o ~/."$F"
grep -qs "$F" "$RC" || echo "source ~/.$F" >> "$RC"
source ~/."$F"
```

Then `cswap switch <TAB>` lists your saved slots and cycles through them.

### Uninstall

```bash
rm -f ~/.local/bin/cswap ~/.cswap-completion.bash ~/.cswap-completion.zsh
rm -rf ~/.config/cswap-min      # also deletes your saved account backups
```

Then drop the `source` and `PATH` lines from your `~/.bashrc` or `~/.zshrc`. On macOS, remove
the Keychain backups with `cswap forget <name>` *before* deleting the script.

---

## Set up your accounts

Once per account. **Do not `/logout` between them** — that revokes the refresh token and the
backup becomes useless.

```bash
# logged into account A in Claude Code:
cswap save work

# now run /login in Claude Code, pick account B:
cswap save personal
```

macOS first run shows a Keychain prompt → click **Always Allow**.

```console
$ cswap list
  work             token:✓ identity:✓ (active)
  personal         token:✓ identity:✓
```

## Switch

```bash
cswap switch personal
cswap current          # shows the active account email
cswap switch _prev     # undo the last switch
```

- **Billing/quota flips instantly.**
- The email shown in an *already-running* session is cached at startup — reopen the `claude`
  session or VS Code tab if it still shows the old one. Linux updates immediately.

## Commands

| Command | Does |
|---|---|
| `cswap save <name>` | Back up the currently logged-in account (token + identity) |
| `cswap switch <name>` | Activate `<name>` |
| `cswap switch _prev` | Undo the last switch |
| `cswap list` | List saved slots |
| `cswap current` | Show the active account email |
| `cswap rename <old> <new>` | Rename a slot label (credentials unchanged) |
| `cswap forget <name>` | Drop a slot's backups (active login untouched) |

## Gotchas

- **Don't switch to the account that's already active.** The tool refuses it — restoring an older
  token snapshot over a fresh one usually logs you out. Override with `--force` only if you know
  the backup is current.
- **Stale backup → re-save.** If a switch fails or logs you out, `/login` that account again and
  `cswap save <name>`. Recover from a bad switch with `cswap switch _prev`.
- Normal A↔B switching keeps itself healthy: every switch re-saves the *departing* account's
  backup from its live token first.

## Where your tokens live

Nothing leaves your machine.

| | Active token | Backups |
|---|---|---|
| **macOS** | login Keychain (Claude Code's own item) | login Keychain |
| **Linux** | `~/.claude/.credentials.json` (Claude Code's own file) | `~/.config/cswap-min/`, mode `0600` |

Same place and format Claude Code already uses. On Linux that means plaintext on disk — which is
how Claude Code stores it too, so this adds no new exposure.

## What this is

A no-install, ~300-line cousin of [claude-swap](https://github.com/realiti4/claude-swap). It swaps
the credential Claude Code reads and the identity it displays (`oauthAccount` in `.claude.json`),
cooperating with Claude Code's own refresh locks.

Want usage dashboards, auto-switching before you hit rate limits, or background token-refresh
persistence? Use the full `claude-swap` tool instead.

## Status

Linux path tested on Debian 12 / bash 5.2: full `save`/`switch`/`list`/`rename`/`forget`
lifecycle, lock contention and stale-lock recovery, `CLAUDE_CONFIG_DIR`, and file permissions.
The macOS Keychain path is not covered by an automated test — testing it means writing to a
real login Keychain. Review it before trusting it with an account you care about.
