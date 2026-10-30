#!/usr/bin/env bash
# cswap-min — minimal multi-account Claude Code switcher. macOS + Linux. No install.
# Swaps BOTH halves CC uses: the credential/token (drives billing/quota) AND the
# display identity (oauthAccount, the email CC shows).
#
#   cswap save <name>          back up the CURRENTLY logged-in account
#   cswap switch <name>        activate <name> (token + identity + reload)
#   cswap list                 list saved slots
#   cswap current              active account email
#   cswap rename <old> <new>   rename a slot label (credentials unchanged)
#   cswap forget <name>        drop a slot's backups
#
# Backend per OS:
#   macOS  -> active token in the login Keychain (CC's own item); backups in Keychain.
#   Linux  -> active token in <config_home>/.credentials.json (CC's own file, plaintext);
#             backups in plaintext files under the registry dir (0600, same exposure
#             as CC's own credentials file on Linux).
#
# Setup: log in A -> `save A`; /login B -> `save B`; then `switch A|B`.
# Never /logout before saving — CC revokes the refresh token on logout.

set -euo pipefail

OS="${CSWAP_OS:-$(uname -s)}"          # Darwin | Linux (CSWAP_OS overrides, for tests)
SECURITY=/usr/bin/security             # macOS only
SVC="Claude Code-credentials"          # CC's active-credential (token) Keychain item
ACC="${USER:-$(id -un)}"               # CC keys the macOS token item by $USER
TSVC="claude-swap-min"                 # macOS per-slot TOKEN backups (Keychain service)
ISVC="claude-swap-min-id"              # macOS per-slot IDENTITY backups (Keychain service)

# Resolve CC's real paths once, handling CLAUDE_CONFIG_DIR and CC 2.1.299's
# .config.json-vs-.claude.json pick (paths.py:_pick_global_config). Sets:
#   CFG_HOME   config home (CLAUDE_CONFIG_DIR or ~/.claude)
#   CRED_FILE  active token file          (<config_home>/.credentials.json)
#   CONFIG     global config w/ oauthAccount (.config.json | ~/.claude.json)
command -v python3 >/dev/null || { echo "cswap: need 'python3' on PATH" >&2; exit 1; }
eval "$(python3 - <<'PY'
import os, stat, shlex
home = os.path.expanduser("~")
env = os.environ.get("CLAUDE_CONFIG_DIR")
cfg_home = env or os.path.join(home, ".claude")
creds = os.path.join(cfg_home, ".credentials.json")
base = env or home
legacy, glob = os.path.join(cfg_home, ".config.json"), os.path.join(base, ".claude.json")
def pick(legacy, glob):
    try: st = os.stat(legacy)
    except OSError: return glob
    if stat.S_ISREG(st.st_mode) and (st.st_size > 0 or (st.st_mode & 0o222 and not os.path.exists(glob))):
        return legacy
    return glob
print("CFG_HOME=%s"  % shlex.quote(cfg_home))
print("CRED_FILE=%s" % shlex.quote(creds))
print("CONFIG=%s"    % shlex.quote(pick(legacy, glob)))
PY
)"

REG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cswap-min"
REG="$REG_DIR/slots"                   # one slot name per line (source of truth)
BDIR="$REG_DIR/slots.d"                # Linux per-slot backup files

LOCK_PRIMARY="$CFG_HOME/.oauth_refresh.lock"
LOCK_LEGACY="$(dirname "$CFG_HOME")/$(basename "$CFG_HOME").lock"
LOCK_TIMEOUT=9
LOCK_STALE=60

# Canonical command name in help. Install as `cswap`; override with CSWAP_PROG.
PROG="${CSWAP_PROG:-cswap}"
die(){ echo "$PROG: $*" >&2; exit 1; }
is_help(){ case "${1:-}" in -h|--help|help) return 0;; *) return 1;; esac; }
# Slot names must be safe as a Keychain account, a filename, and a registry line.
valid_name(){ case "${1:-}" in ""|-*|*/*|*[[:space:]]*) return 1;; *) return 0;; esac; }
usage(){ cat >&2 <<EOF
$PROG — minimal Claude Code account switcher (${OS})
  $PROG save <name>          back up the currently logged-in account (token + identity)
  $PROG switch <name>        activate <name>
  $PROG list                 list saved slots
  $PROG current              show active account email
  $PROG rename <old> <new>   rename a slot label (credentials unchanged)
  $PROG forget <name>        drop a slot's backups
EOF
}

# ---- lock helpers (cooperate with CC's proper-lockfile dirs) ----------------
mtime(){ if [ "$OS" = Darwin ]; then stat -f %m "$1"; else stat -c %Y "$1"; fi; }
acquire(){ local d="$1" start now mt; start=$(date +%s)
  while ! mkdir "$d" 2>/dev/null; do now=$(date +%s)
    (( now - start > LOCK_TIMEOUT )) && die "lock busy: $d (CC refreshing? retry)"
    mt=$(mtime "$d" 2>/dev/null || echo "$now")
    if (( now - mt > LOCK_STALE )); then rmdir "$d" 2>/dev/null || sleep 0.1; continue; fi
    sleep 0.3
  done; }
release(){ rmdir "$1" 2>/dev/null || true; }

# ---- macOS Keychain i/o -----------------------------------------------------
kc_get(){ "$SECURITY" find-generic-password -a "$2" -w -s "$1" 2>/dev/null; } # svc acct
kc_put(){ "$SECURITY" add-generic-password -U -a "$2" -s "$1" -w "$3"; }      # svc acct val
kc_has(){ "$SECURITY" find-generic-password -a "$2" -s "$1" >/dev/null 2>&1; } # svc acct
kc_del(){ "$SECURITY" delete-generic-password -a "$2" -s "$1" >/dev/null 2>&1 || true; }

# ---- file i/o ---------------------------------------------------------------
write_file(){ local path="$1" val="$2"; mkdir -p "$(dirname "$path")"
  ( umask 177; printf '%s' "$val" > "$path.tmp" ) && mv -f "$path.tmp" "$path"; }

# ---- active token (what CC bills on) ----------------------------------------
read_active_token(){
  if [ "$OS" = Darwin ]; then kc_get "$SVC" "$ACC"
  else [ -s "$CRED_FILE" ] && cat "$CRED_FILE"; fi
}
write_active_token(){  # $1 = token value
  if [ "$OS" = Darwin ]; then kc_put "$SVC" "$ACC" "$1"
  else write_file "$CRED_FILE" "$1"; fi   # Linux: writing the file IS the hot-reload
}

# ---- per-slot backups (token + identity) ------------------------------------
bk_put(){ # kind name val   (kind = token | id)
  if [ "$OS" = Darwin ]; then
    [ "$1" = token ] && kc_put "$TSVC" "$2" "$3" || kc_put "$ISVC" "$2" "$3"
  else write_file "$BDIR/$2.$1" "$3"; fi
}
bk_get(){ if [ "$OS" = Darwin ]; then
    [ "$1" = token ] && kc_get "$TSVC" "$2" || kc_get "$ISVC" "$2"
  else cat "$BDIR/$2.$1" 2>/dev/null; fi; }
bk_has(){ if [ "$OS" = Darwin ]; then
    [ "$1" = token ] && kc_has "$TSVC" "$2" || kc_has "$ISVC" "$2"
  else [ -s "$BDIR/$2.$1" ]; fi; }
bk_del(){ # name — drop both halves
  if [ "$OS" = Darwin ]; then kc_del "$TSVC" "$1"; kc_del "$ISVC" "$1"
  else rm -f "$BDIR/$1.token" "$BDIR/$1.id"; fi; }

# ---- registry ---------------------------------------------------------------
reg_add(){ mkdir -p "$REG_DIR"; touch "$REG"
  grep -qxF -- "$1" "$REG" || printf '%s\n' "$1" >> "$REG"; }
reg_del(){ [ -f "$REG" ] || return 0; grep -vxF -- "$1" "$REG" > "$REG.tmp" || true; mv -f "$REG.tmp" "$REG"; }

# ---- identity (oauthAccount in the global config) ---------------------------
read_identity(){  # emit oauthAccount JSON from CONFIG, or {}
  python3 - "$CONFIG" <<'PY'
import json, os, sys
p = sys.argv[1]
try: print(json.dumps(json.load(open(p)).get("oauthAccount", {})))
except Exception: print("{}")
PY
}
email_of(){ printf '%s' "$1" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("emailAddress",""))
except Exception: print("")' 2>/dev/null; }
# Warn if a token''s accessToken is already expired: a switch to it forces CC to
# refresh with the saved (possibly rotated/revoked) refreshToken → logout risk.
token_is_stale(){ printf '%s' "$1" | python3 -c 'import sys,json,time
try:
 o=json.load(sys.stdin); o=o.get("claudeAiOauth",o)
 print("stale" if (o.get("expiresAt",0)/1000) < time.time() else "fresh")
except Exception: print("fresh")' 2>/dev/null; }
splice_identity(){  # $1 = oauthAccount json; atomic, preserves all other keys
  [ -f "$CONFIG" ] || return 0
  python3 - "$1" "$CONFIG" <<'PY'
import json, os, sys
obj, path = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d["oauthAccount"] = json.loads(obj)
tmp = path + ".cswap.tmp"
open(tmp, "w").write(json.dumps(d))
os.replace(tmp, path)   # atomic, bumps mtime
PY
}

cmd_save(){
  is_help "${1:-}" && { echo "usage: $PROG save <name>" >&2; return 0; }
  valid_name "${1:-}" || die "bad slot name '${1:-}' (no leading '-', no '/' or spaces)"
  local name="$1" tok id idmsg="token ✓"
  tok="$(read_active_token)" || true
  [ -n "$tok" ] || die "no active Claude Code token found (log in first)"
  bk_put token "$name" "$tok"
  if [ -f "$CONFIG" ]; then id="$(read_identity)"; bk_put id "$name" "$id"; idmsg="token ✓, identity ✓"; fi
  reg_add "$name"
  echo "saved '$name'  ($idmsg)"
}

cmd_switch(){
  is_help "${1:-}" && { echo "usage: $PROG switch <name> [--force]" >&2; return 0; }
  valid_name "${1:-}" || die "bad slot name '${1:-}'"
  local name="$1" tok id force=0
  [ "${2:-}" = "--force" ] && force=1
  bk_has token "$name" || die "no saved slot '$name' (run: $PROG save $name)"
  tok="$(bk_get token "$name")"; [ -n "$tok" ] || die "slot '$name' token empty"

  # Guard 1: refuse switching to the account that is ALREADY active. Overwriting
  # today's fresh token with an older saved snapshot of the same account almost
  # always logs you out (the saved refresh token has since rotated/revoked).
  local cur_tok cur_email tgt_email
  cur_tok="$(read_active_token || true)"
  [ -f "$CONFIG" ] && cur_email="$(email_of "$(read_identity)")" || cur_email=""
  # Read the identity HERE, not at the splice below: the _prev stash further down
  # overwrites this slot's id backup when $name is _prev.
  if bk_has id "$name"; then id="$(bk_get id "$name")"; else id=""; fi
  tgt_email="$(email_of "$id")"
  if [ -n "$cur_email" ] && [ "$cur_email" = "$tgt_email" ] && [ $force -eq 0 ]; then
    die "'$name' ($tgt_email) is already active. Switching restores an OLDER saved token and will likely log you out. If the backup is genuinely fresh: $PROG switch $name --force"
  fi
  # Guard 2: warn when the target token is already expired (forces a refresh on a
  # possibly-stale refresh token). Proceed, but say so.
  if [ "$(token_is_stale "$tok")" = stale ] && [ $force -eq 0 ]; then
    echo "warning: slot '$name' token is stale (saved a while ago); if it fails, log in again and re-run '$PROG save $name'." >&2
  fi
  # Keep backups fresh: refresh the DEPARTING account's own named slot(s) with the
  # live (fresh) token before leaving, so a later switch back restores a current
  # token instead of a stale one. Matches slots by identity email.
  if [ -n "$cur_tok" ] && [ -n "$cur_email" ] && [ -s "$REG" ]; then
    local s
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      [ "$(email_of "$(bk_get id "$s")")" = "$cur_email" ] && {
        bk_put token "$s" "$cur_tok"; [ -f "$CONFIG" ] && bk_put id "$s" "$(read_identity)"; }
    done < "$REG"
  fi
  # Safety net: stash the account being left into '_prev' so a bad switch is
  # recoverable with: $PROG switch _prev
  if [ -n "$cur_tok" ]; then
    bk_put token _prev "$cur_tok"
    [ -f "$CONFIG" ] && bk_put id _prev "$(read_identity)"
  fi

  mkdir -p "$CFG_HOME"
  acquire "$LOCK_PRIMARY"; acquire "$LOCK_LEGACY"
  trap 'release "$LOCK_LEGACY"; release "$LOCK_PRIMARY"' EXIT
  write_active_token "$tok"                       # 1) token (billing/quota)
  if [ -n "$id" ] && [ -f "$CONFIG" ]; then       # 2) identity (shown email)
    splice_identity "$id"
  fi
  # 3) macOS hot-reload: bump an existing shadow file so a running session reloads
  #    (Linux already reloaded — write_active_token wrote CRED_FILE itself).
  if [ "$OS" = Darwin ] && [ -f "$CRED_FILE" ]; then write_file "$CRED_FILE" "$tok"; fi
  release "$LOCK_LEGACY"; release "$LOCK_PRIMARY"; trap - EXIT
  echo "switched to '$name'"
  echo "  billing/quota: now this account (immediate)"
  [ -n "$cur_tok" ] && echo "  previous account stashed — undo with: $PROG switch _prev"
  if [ "$OS" = Darwin ]; then
    echo "  shown email:   updated; reopen the session if it still shows the old one"
  else
    echo "  shown email:   updated in $(basename "$CONFIG")"
  fi
}

cmd_list(){
  [ -s "$REG" ] || { echo "(no slots yet — run: $PROG save <name>)"; return; }
  local cur; cur="$(read_active_token || true)"
  local n mark t i
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    mark=""; [ -n "$cur" ] && [ "$(bk_get token "$n" 2>/dev/null)" = "$cur" ] && mark=" (active)"
    bk_has token "$n" && t=✓ || t=x
    bk_has id "$n"    && i=✓ || i=x
    printf '  %-16s token:%s identity:%s%s\n' "$n" "$t" "$i" "$mark"
  done < "$REG"
}

cmd_current(){
  [ -f "$CONFIG" ] || die "no config file at $CONFIG"
  python3 - "$CONFIG" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1])).get("oauthAccount", {})
    print(d.get("emailAddress") or "(no email in oauthAccount)")
except Exception as e:
    print("(could not read:", e, ")")
PY
}

cmd_rename(){   # rename a slot label only; token + identity bytes preserved
  { is_help "${1:-}" || [ $# -lt 2 ]; } && { echo "usage: $PROG rename <old> <new>" >&2; return 0; }
  local old="$1" new="$2"
  valid_name "$old" || die "bad slot name '$old'"
  valid_name "$new" || die "bad slot name '$new'"
  [ "$old" = "$new" ] && die "old and new are the same"
  bk_has token "$old" || die "no slot '$old'"
  bk_has token "$new" && die "slot '$new' already exists (forget it first)"
  bk_put token "$new" "$(bk_get token "$old")"
  bk_has id "$old" && bk_put id "$new" "$(bk_get id "$old")"
  bk_del "$old"; reg_del "$old"; reg_add "$new"
  echo "renamed slot '$old' -> '$new' (credentials unchanged)"
}

cmd_forget(){
  is_help "${1:-}" && { echo "usage: $PROG forget <name>" >&2; return 0; }
  [ -n "${1:-}" ] || die "usage: $PROG forget <name>"
  bk_del "$1"; reg_del "$1"
  echo "forgot slot '$1' (active login untouched)"
}

case "${1:-}" in
  save)    shift; cmd_save "$@";;
  switch)  shift; cmd_switch "$@";;
  list)    cmd_list;;
  current) cmd_current;;
  rename)  shift; cmd_rename "$@";;
  forget)  shift; cmd_forget "$@";;
  help|-h|--help|"") usage; [ -z "${1:-}" ] && exit 1 || exit 0;;
  *) echo "$PROG: unknown command '$1'" >&2; usage; exit 1;;
esac
