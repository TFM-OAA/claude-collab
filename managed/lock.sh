#!/bin/sh
# Collaboration LOCK — POSIX sh port for macOS/Linux, delivered via managed hooks.
# Zero-touch delivery: the whole script is base64'd and run as  echo <b64> | base64 -d | sh
# so quoting/substitution never touches the hook command line (that's what broke the first
# Mac probe). Event is pinned per blob by gen-managed-hooks.ps1 (replaces __EVENT__).
# Mirrors lock.ps1: owner=$USER, claim-handshake (LOCK_SETTLE_SECONDS), Drive conflict-copy
# detection, PreToolUse deny-JSON. Reads/searches never blocked.
LOCK_EVENT="__EVENT__"
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$(printf '%s' "$DIR" | tr '\\' '/')"   # normalize Windows backslashes for Git Bash
LOCK="$DIR/WORKING_NOW.txt"
ME="$(id -un 2>/dev/null || printf '%s' "$USER")@$(hostname 2>/dev/null)"
SETTLE="${LOCK_SETTLE_SECONDS:-10}"

copies() { ls -1 "$DIR"/WORKING_NOW*.txt 2>/dev/null | grep -v '/WORKING_NOW\.txt$'; }
lock_owner() { [ -f "$LOCK" ] && head -n1 "$LOCK" 2>/dev/null | LC_ALL=C tr -d '\357\273\277\r\n' | sed 's/^OWNER=//'; }
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
emit_start() { printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$(esc "$1")"; }
emit_deny() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}' "$(esc "$1")"; }
claim() { printf 'OWNER=%s\nWho:     %s\nStarted: %s\nHost:    %s\n' "$ME" "$ME" "$(date '+%Y-%m-%d %H:%M')" "$(hostname 2>/dev/null)" > "$LOCK"; }

case "$LOCK_EVENT" in
  sessionstart)
    if [ -n "$(copies)" ]; then
      emit_start "LOCK SYNC CONFLICT: found a WORKING_NOW copy next to WORKING_NOW.txt. Two machines likely locked at once. Warn the user clearly in Russian: STOP, do not edit, reconcile the copies manually (COLLABORATION.md rule 5) and coordinate."
      exit 0
    fi
    if [ -f "$LOCK" ]; then
      O="$(lock_owner)"
      if [ "$O" = "$ME" ]; then
        emit_start "LOCK already yours ($ME) - OK to work. Tell the user briefly in Russian."
      else
        emit_start "LOCK WARNING: project is BUSY by colleague '$O' (WORKING_NOW.txt). Work in turns: do NOT edit files until released. Edits will be blocked by a guard hook. Warn the user clearly in Russian and suggest contacting the colleague."
      fi
    else
      claim; sleep "$SETTLE"
      if [ -n "$(copies)" ]; then
        emit_start "LOCK SYNC CONFLICT after claim. Another machine locked simultaneously. Warn the user clearly in Russian: STOP, do not edit, reconcile copies (COLLABORATION.md rule 5)."
      else
        O2="$(lock_owner)"
        if [ -n "$O2" ] && [ "$O2" != "$ME" ]; then
          emit_start "LOCK race lost: now owned by '$O2'. Warn the user clearly in Russian: STOP and coordinate; do not edit."
        else
          emit_start "LOCK set for you ($ME). Release via /unlock or automatically on session end. Tell the user briefly in Russian."
        fi
      fi
    fi
    ;;
  pretooluse)
    if [ -n "$(copies)" ]; then
      emit_deny "LOCK SYNC CONFLICT: a WORKING_NOW copy exists. Two machines locked at once. STOP. Reconcile copies manually (COLLABORATION.md rule 5), then continue."
      exit 0
    fi
    if [ -f "$LOCK" ]; then
      O="$(lock_owner)"
      if [ -n "$O" ] && [ "$O" != "$ME" ]; then
        emit_deny "Project LOCK held by colleague '$O' (WORKING_NOW.txt). Edits are blocked until the lock is released. Coordinate and work in turns; the colleague runs /unlock or ends their session to release."
      elif [ -z "$O" ]; then
        claim; sleep "$SETTLE"
        O2="$(lock_owner)"
        [ -n "$O2" ] && [ "$O2" != "$ME" ] && emit_deny "LOCK race lost: now owned by '$O2'. STOP and coordinate; do not edit."
      fi
    else
      claim; sleep "$SETTLE"
      O2="$(lock_owner)"
      [ -n "$O2" ] && [ "$O2" != "$ME" ] && emit_deny "LOCK race lost: now owned by '$O2'. STOP and coordinate; do not edit."
    fi
    ;;
  sessionend)
    if [ -f "$LOCK" ]; then
      O="$(lock_owner)"
      { [ -z "$O" ] || [ "$O" = "$ME" ]; } && rm -f "$LOCK"
    fi
    ;;
esac
exit 0
