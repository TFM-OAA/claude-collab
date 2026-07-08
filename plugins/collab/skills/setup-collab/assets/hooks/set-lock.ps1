# Sets the project LOCK (WORKING_NOW.txt) for the current user, but ONLY if no one
# else holds it. For manual use mid-session (slash command /lock) when there is no
# foreign lock. The SessionStart hook (check-lock.ps1) creates the lock automatically
# at session start; this script covers the "already-running session" case.
# Conflict-copy aware + claim handshake (same model as check-lock.ps1 / guard-lock.ps1).
# ASCII-only on purpose (Windows PowerShell 5.1 reads .ps1 as ANSI without BOM).
$ErrorActionPreference = 'SilentlyContinue'

# Self-locate the project dir: prefer the hook env var, else two levels up from this script.
$dir = $env:CLAUDE_PROJECT_DIR
if (-not $dir) { $dir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

$lock = Join-Path $dir 'WORKING_NOW.txt'
$me   = $env:USERNAME

$settle = 10
if ($env:LOCK_SETTLE_SECONDS) { $settle = [int]$env:LOCK_SETTLE_SECONDS }

function Get-Copies {
  @(Get-ChildItem -Path $dir -Filter 'WORKING_NOW*.txt' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'WORKING_NOW.txt' })
}
function Get-Owner {
  if (Test-Path $lock) { ((Get-Content $lock -TotalCount 1) -replace '^OWNER=','').Trim() } else { $null }
}
function Claim-WithHandshake {
  $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm'
  $body = @("OWNER=$me", "Who:     $me", "Started: $ts", "Host:    $env:COMPUTERNAME")
  Set-Content -Path $lock -Value $body -Encoding UTF8
  Start-Sleep -Seconds $settle
  $c2 = Get-Copies
  $o2 = Get-Owner
  if ($c2.Count -gt 0) {
    $names = ($c2 | ForEach-Object { $_.Name }) -join ', '
    Write-Output ("LOCK SYNC CONFLICT after claim: found " + $names + ". Another machine locked simultaneously. STOP - reconcile WORKING_NOW copies manually (COLLABORATION.md rule 5) and coordinate.")
  } elseif ($o2 -and ($o2 -ne $me)) {
    Write-Output ("LOCK race lost: WORKING_NOW.txt now owned by '" + $o2 + "'. Another machine locked simultaneously. STOP and coordinate.")
  } else {
    Write-Output ("LOCK set for you (" + $me + ", " + $ts + ").")
  }
}

# Conflict-copy detection (Layer 1).
$copies = Get-Copies
if ($copies.Count -gt 0) {
  $names = ($copies | ForEach-Object { $_.Name }) -join ', '
  Write-Output ("LOCK SYNC CONFLICT: found " + $names + " next to WORKING_NOW.txt. Two machines likely locked at once. STOP - reconcile copies manually (COLLABORATION.md rule 5) and coordinate before working.")
  exit 0
}

if (Test-Path $lock) {
  $owner = Get-Owner
  if ($owner -eq $me) {
    Write-Output ("LOCK already yours (" + $me + ") - OK to work.")
  } elseif (-not $owner) {
    # Malformed empty-owner lock - claim it with handshake.
    Claim-WithHandshake
  } else {
    Write-Output ("LOCK belongs to '" + $owner + "', not you (" + $me + ") - NOT overwriting. Work in turns; ask the colleague to release it (or run /unlock on their side).")
  }
} else {
  Claim-WithHandshake
}
exit 0
