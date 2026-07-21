# SessionStart hook: check / create the project LOCK (WORKING_NOW.txt).
# Conflict-copy aware + claim handshake: if a Drive sync conflict-copy exists, warn and do
# nothing; when creating the lock, wait LOCK_SETTLE_SECONDS for Drive to sync, then re-check
# for a foreign owner or a conflict copy (simultaneous start) before declaring success.
# ASCII-only on purpose (Windows PowerShell 5.1 reads .ps1 as ANSI without BOM).
$ErrorActionPreference = 'SilentlyContinue'

# Self-locate the project dir: prefer the hook env var, else two levels up from this script.
$dir = $env:CLAUDE_PROJECT_DIR
if (-not $dir) { $dir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

$lock = Join-Path $dir 'WORKING_NOW.txt'
$me   = "$env:USERNAME@$env:COMPUTERNAME"

$settle = 10
if ($env:LOCK_SETTLE_SECONDS) { $settle = [int]$env:LOCK_SETTLE_SECONDS }

function Emit([string]$ctx) {
  $o = @{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $ctx } }
  $o | ConvertTo-Json -Compress -Depth 5
}
function Get-Copies {
  @(Get-ChildItem -Path $dir -Filter 'WORKING_NOW*.txt' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'WORKING_NOW.txt' })
}
function Get-Owner {
  if (Test-Path $lock) { ((Get-Content $lock -TotalCount 1) -replace '^OWNER=','').Trim() } else { $null }
}

# Conflict-copy detection (Layer 1).
$copies = Get-Copies
if ($copies.Count -gt 0) {
  $names = ($copies | ForEach-Object { $_.Name }) -join ', '
  Emit ("LOCK SYNC CONFLICT: found " + $names + " next to WORKING_NOW.txt. Two machines likely locked at once. Warn the user clearly in Russian: STOP, do not edit, reconcile the WORKING_NOW copies manually (COLLABORATION.md rule 5) and coordinate with the colleague.")
  exit 0
}

if (Test-Path $lock) {
  $owner = Get-Owner
  if ($owner -eq $me) {
    Emit "LOCK already yours ($me) - OK to work. Tell the user briefly in Russian."
  } else {
    Emit ("LOCK WARNING: project is BUSY by colleague '" + $owner + "' (WORKING_NOW.txt). Work in turns: do NOT edit files until the lock is released. Edits will be blocked by a guard hook. Warn the user clearly in Russian and suggest contacting the colleague.")
  }
} else {
  $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm'
  $body = @("OWNER=$me", "Who:     $me", "Started: $ts", "Host:    $env:COMPUTERNAME")
  Set-Content -Path $lock -Value $body -Encoding UTF8
  # Handshake (Layer 2): let Drive settle, then verify we won the race.
  Start-Sleep -Seconds $settle
  $c2 = Get-Copies
  $o2 = Get-Owner
  if ($c2.Count -gt 0) {
    $names = ($c2 | ForEach-Object { $_.Name }) -join ', '
    Emit ("LOCK SYNC CONFLICT after claim: found " + $names + ". Another machine locked simultaneously. Warn the user clearly in Russian: STOP, do not edit, reconcile WORKING_NOW copies manually (COLLABORATION.md rule 5) and coordinate.")
  } elseif ($o2 -and ($o2 -ne $me)) {
    Emit ("LOCK race lost: WORKING_NOW.txt now owned by '" + $o2 + "'. Another machine locked simultaneously. Warn the user clearly in Russian: STOP and coordinate; do not edit.")
  } else {
    Emit ("LOCK set for you (" + $me + ", " + $ts + "). Release via /unlock or automatically on session end. Tell the user briefly in Russian.")
  }
}
exit 0
