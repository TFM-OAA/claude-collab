# Removes the project LOCK (WORKING_NOW.txt) but ONLY if it belongs to the current user.
# Used by SessionEnd hook and by the /unlock slash command. ASCII-only.
$ErrorActionPreference = 'SilentlyContinue'

# Self-locate the project dir: prefer the hook env var, else two levels up from this
# script (<project>\.claude\hooks\remove-lock.ps1). Works as a hook (env var set) or run manually.
$dir = $env:CLAUDE_PROJECT_DIR
if (-not $dir) { $dir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }

$lock = Join-Path $dir 'WORKING_NOW.txt'
$me   = "$env:USERNAME@$env:COMPUTERNAME"

if (Test-Path $lock) {
  $owner = ((Get-Content $lock -TotalCount 1) -replace '^OWNER=','').Trim()
  if ((-not $owner) -or ($owner -eq $me)) {
    Remove-Item -Force $lock
    Write-Output ("LOCK released (" + $me + ").")
  } else {
    Write-Output ("LOCK belongs to '" + $owner + "', not you (" + $me + ") - not removing. If it is stale, delete WORKING_NOW.txt manually.")
  }
} else {
  Write-Output "No lock to release."
}
exit 0
