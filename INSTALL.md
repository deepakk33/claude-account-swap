# cswap — minimal Claude Code account switcher

Switch between multiple Claude Code accounts **mid-session** — no `/logout`, no restart.
Works on macOS and Linux. No install/package needed, just a shell script.

## Files
| File | Need it? |
|---|---|
| `cswap-min.sh` | **Required** — the tool |
| `cswap-completion.zsh` | Optional — TAB-completion for zsh (macOS default shell) |
| `cswap-completion.bash` | Optional — TAB-completion for bash |

---

## 1. Prerequisites
- macOS or Linux
- Claude Code installed, logged into at least one account
- `python3` (check: `python3 --version`; macOS without it: `xcode-select --install`)

## 2. Install the command
Put the script anywhere, make it executable, expose it as `cswap`.

```bash
mv ~/Downloads/cswap-min.sh ~/cswap-min.sh
chmod +x ~/cswap-min.sh
```

Add to `~/.zshrc` (zsh, macOS default) — use a **function**, not an alias (completion needs it):
```bash
cswap(){ "$HOME/cswap-min.sh" "$@"; }
```
(bash users: same line in `~/.bashrc`.)

Reload: `exec zsh`  (or `exec bash`). Check: `cswap --help`.

## 3. Save your accounts
Once per account. **Do not `/logout`** between — that revokes the token.

```bash
# In Claude Code, be logged into account A, then:
cswap save work

# In Claude Code run /login -> account B, then:
cswap save personal
```
macOS first run shows a Keychain prompt → click **Always Allow**.

Check: `cswap list`
```
work       token:✓ identity:✓ (active)
personal   token:✓ identity:✓
```

## 4. Switch
```bash
cswap switch personal
cswap switch work
cswap current        # shows active account email
```
- **Billing/quota flips instantly.**
- The shown email in a *running* session is cached at startup → reopen the `claude` session / VS Code tab if it still shows the old one. (Linux updates immediately.)

## 5. (Optional) TAB-completion
zsh:
```bash
# with oh-my-zsh or any zsh that already runs compinit, add to the END of ~/.zshrc:
source "$HOME/cswap-completion.zsh"
zstyle ':completion:*' menu select
exec zsh
```
Then `cswap switch <TAB>` lists your slots and cycles through them.

bash: `source ~/cswap-completion.bash` in `~/.bashrc`.

---

## Commands
```
cswap save <name>          back up the currently logged-in account (token + identity)
cswap switch <name>        activate <name>
cswap list                 list saved slots
cswap current              show active account email
cswap rename <old> <new>   rename a slot label (credentials unchanged)
cswap forget <name>        drop a slot's backups
```

## Important gotchas
- **Don't `switch` to the account that's already active.** The tool refuses it (it would restore an older token snapshot and can log you out). It auto-refreshes a departing account's backup on every switch, so normal A↔B switching keeps tokens fresh.
- **Stale backups → re-save.** If you haven't switched in a while and a `switch` fails/logs you out, just `/login` that account again and `cswap save <name>`. Undo a bad switch with `cswap switch _prev`.
- Tokens never leave your machine — macOS keeps them in your login Keychain; Linux keeps them in files under `~/.config/cswap-min/` (0600), same place/format Claude Code already stores them.

## What this is
A no-install, ~230-line version of [claude-swap](https://github.com/realiti4/claude-swap).
It swaps the credential Claude Code reads (Keychain on macOS, `.credentials.json` on Linux)
and the shown identity (`oauthAccount` in `.claude.json`), while cooperating with Claude Code's
own refresh locks. For usage dashboards, auto-switching before rate limits, and background
token-refresh persistence, use the full `claude-swap` tool instead.
