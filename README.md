# cswap

Switch between multiple Claude Code accounts **mid-session**. No `/logout`, no restart.

```bash
cswap save work         # back up whoever is logged in now
cswap switch personal   # billing + quota flip instantly
cswap switch _prev      # undo
```

One bash script. Nothing to install, no packages, no account, nothing leaves your machine.

---

# 1. Install

## macOS

```bash
# python3 — skip if `python3 --version` already prints something
xcode-select --install

# install
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/deepakk33/claude-account-swap/main/cswap-min.sh -o ~/.local/bin/cswap
chmod +x ~/.local/bin/cswap
RC=~/.bashrc; [ -n "${ZSH_VERSION:-}" ] && RC=~/.zshrc
grep -qs '.local/bin' "$RC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
export PATH="$HOME/.local/bin:$PATH"

# check — same terminal, no reopening
cswap --help
```

Your tokens stay in the **login Keychain**. First `save` pops a Keychain prompt → click **Always Allow**.

## Linux

```bash
# python3 — missing from most minimal images
sudo apt install -y python3        # Debian/Ubuntu  (dnf: python3 · pacman: python)

# install
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/deepakk33/claude-account-swap/main/cswap-min.sh -o ~/.local/bin/cswap
chmod +x ~/.local/bin/cswap
RC=~/.bashrc; [ -n "${ZSH_VERSION:-}" ] && RC=~/.zshrc
grep -qs '.local/bin' "$RC" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
export PATH="$HOME/.local/bin:$PATH"

# check — same terminal, no reopening
cswap --help
```

Works in bash or zsh — the block detects which you use. zsh not required.

<details>
<summary><b>Rather read the script first? (recommended — it handles your credentials)</b></summary>

```bash
git clone https://github.com/deepakk33/claude-account-swap.git
cd claude-account-swap
less cswap-min.sh        # ~300 lines, plain bash
mkdir -p ~/.local/bin && cp cswap-min.sh ~/.local/bin/cswap && chmod +x ~/.local/bin/cswap
```
</details>

---

# 2. Use

### Step 1 — save each account, once

**Do not `/logout` between them.** Logout revokes the token and the backup becomes dead weight.

```bash
# logged into account A right now:
cswap save work

# run /login inside Claude Code, pick account B:
cswap save personal
```

### Step 2 — switch whenever

```bash
cswap switch personal
```

```console
$ cswap list
  work             token:✓ identity:✓
  personal         token:✓ identity:✓ (active)

$ cswap current
personal@example.com
```

Billing and quota flip **immediately**. The email shown inside an *already-open* session is cached at startup — reopen the `claude` session or VS Code tab if it looks stale. (Linux updates right away.)

### All commands

| Command | Does |
|---|---|
| `cswap save <name>` | Back up the account logged in right now |
| `cswap switch <name>` | Switch to it |
| `cswap switch _prev` | Undo the last switch |
| `cswap list` | Show saved accounts |
| `cswap current` | Show the active account email |
| `cswap rename <old> <new>` | Rename a label (credentials untouched) |
| `cswap forget <name>` | Delete a backup (active login untouched) |

---

# 3. Read this before you rely on it

- **Don't switch to the account that's already active.** cswap refuses — restoring an old token over a fresh one usually logs you out. `--force` overrides, only if you're sure the backup is current.
- **Switch failed or logged you out?** `/login` that account again, then `cswap save <name>`. Undo a bad switch with `cswap switch _prev`.
- Normal A↔B switching stays healthy on its own: every switch re-saves the *departing* account from its live token first.

### Where your tokens live

| | Active token | Backups |
|---|---|---|
| **macOS** | login Keychain | login Keychain |
| **Linux** | `~/.claude/.credentials.json` | `~/.config/cswap-min/`, mode `0600` |

Both are the files and formats Claude Code already uses. On Linux that means plaintext on disk — same as Claude Code itself, so this adds no new exposure.

### Tested

Linux path is covered on Debian 12 / bash 5.2: full save/switch/list/rename/forget lifecycle, lock contention, stale-lock recovery, `CLAUDE_CONFIG_DIR`, file permissions.

The macOS Keychain path has **no automated test** — testing it means writing to a real login Keychain. Read it before trusting it with an account you care about.

---

<details>
<summary><b>TAB-completion (optional)</b></summary>

```bash
RC=~/.bashrc; F=cswap-completion.bash
[ -n "${ZSH_VERSION:-}" ] && { RC=~/.zshrc; F=cswap-completion.zsh; }
curl -fsSL "https://raw.githubusercontent.com/deepakk33/claude-account-swap/main/$F" -o ~/."$F"
grep -qs "$F" "$RC" || echo "source ~/.$F" >> "$RC"
source ~/."$F"
```

`cswap switch <TAB>` then lists and cycles your saved accounts.
</details>

<details>
<summary><b>Uninstall</b></summary>

```bash
cswap forget <name>             # macOS: do this FIRST, it clears the Keychain entries
rm -f ~/.local/bin/cswap ~/.cswap-completion.bash ~/.cswap-completion.zsh
rm -rf ~/.config/cswap-min      # deletes your saved backups too
```

Then delete the `source` and `PATH` lines from `~/.bashrc` or `~/.zshrc`.
</details>

<details>
<summary><b>What this is</b></summary>

A no-install, ~300-line cousin of [claude-swap](https://github.com/realiti4/claude-swap). It swaps the credential Claude Code reads and the identity it displays (`oauthAccount` in `.claude.json`), cooperating with Claude Code's own refresh locks.

Want usage dashboards, auto-switching before you hit rate limits, or background token-refresh persistence? Use the full `claude-swap` instead.
</details>
