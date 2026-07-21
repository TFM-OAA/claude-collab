# PreToolUse hook (matcher Edit|Write|NotebookEdit). Two layers of protection:
#   Layer 1 (cheap, every edit): if a Google Drive sync conflict-copy of the lock exists
#     (e.g. "WORKING_NOW (1).txt"), two machines locked at once -> deny, ask to reconcile.
#   Layer 2 (handshake, only when claiming): on first edit with no lock, write the claim,
#     wait LOCK_SETTLE_SECONDS for Drive to sync, re-read; if a foreign owner or a conflict
#     copy appeared we lost the race -> deny. Otherwise proceed (no permission decision, so
#     the normal Edit/Write permission flow continues). Conflict copies are NEVER auto-deleted.
# ASCII-only on purpose (Windows PowerShell 5.1 reads .ps1 as ANSI without BOM).
$ErrorActionPreference = 'SilentlyContinue'

# Self-locate the project dir: prefer the hook env var, else two levels up from this script.
$dir = $env:CLAUDE_PROJECT_DIR
if (-not $dir) { $dir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

$lock = Join-Path $dir 'WORKING_NOW.txt'
$me   = "$env:USERNAME@$env:COMPUTERNAME"

$settle = 10
if ($env:LOCK_SETTLE_SECONDS) { $settle = [int]$env:LOCK_SETTLE_SECONDS }

function Get-Copies {
  @(Get-ChildItem -Path $dir -Filter 'WORKING_NOW*.txt' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'WORKING_NOW.txt' })
}
function Get-Owner {
  if (Test-Path $lock) { ((Get-Content $lock -TotalCount 1) -replace '^OWNER=','').Trim() } else { $null }
}
function Emit-Deny([string]$reason) {
  $o = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } }
  $o | ConvertTo-Json -Compress -Depth 5
}
function Claim-Lock {
  $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm'
  $body = @("OWNER=$me", "Who:     $me", "Started: $ts", "Host:    $env:COMPUTERNAME")
  Set-Content -Path $lock -Value $body -Encoding UTF8
}
# Write the claim, let Drive settle, then verify we won the race. Emits a deny on conflict.
function Claim-WithHandshake {
  Claim-Lock
  Start-Sleep -Seconds $settle
  $c2 = Get-Copies
  if ($c2.Count -gt 0) {
    $names = ($c2 | ForEach-Object { $_.Name }) -join ', '
    Emit-Deny ("LOCK SYNC CONFLICT after claim: found " + $names + ". Another machine locked simultaneously. STOP. Reconcile WORKING_NOW copies manually (COLLABORATION.md rule 5), then continue.")
    return
  }
  $o2 = Get-Owner
  if ($o2 -and ($o2 -ne $me)) {
    Emit-Deny ("LOCK race lost: WORKING_NOW.txt now owned by '" + $o2 + "'. Another machine locked simultaneously. STOP and coordinate; do not edit.")
  }
}

# Layer 1: conflict-copy detection (runs first, every edit).
$copies = Get-Copies
if ($copies.Count -gt 0) {
  $names = ($copies | ForEach-Object { $_.Name }) -join ', '
  Emit-Deny ("LOCK SYNC CONFLICT: found " + $names + " next to WORKING_NOW.txt. Two machines locked at once. STOP. Reconcile WORKING_NOW copies manually (COLLABORATION.md rule 5), then continue.")
  exit 0
}

if (Test-Path $lock) {
  $owner = Get-Owner
  if ($owner -and ($owner -ne $me)) {
    Emit-Deny ("Project LOCK held by colleague '" + $owner + "' (WORKING_NOW.txt). Edits are blocked until the lock is released. Coordinate and work in turns; the colleague runs /unlock or ends their session to release.")
  } elseif (-not $owner) {
    # Lock file exists but has no owner (malformed) - claim it with handshake.
    Claim-WithHandshake
  }
  # owner == me: nothing to do, proceed silently (no sleep).
} else {
  # No lock at all (old session) - claim it for me on this first edit, with handshake.
  Claim-WithHandshake
}
exit 0
