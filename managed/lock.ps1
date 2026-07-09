# Collaboration LOCK — unified hook logic for delivery via Claude Code MANAGED settings.
# One script, dispatched by event arg: sessionstart | pretooluse | sessionend.
# Faithful merge of check-lock.ps1 / guard-lock.ps1 / remove-lock.ps1 (behavior unchanged).
#
# Delivered zero-touch: the FULL body is base64-encoded into a managed `hooks` command
# (powershell.exe -EncodedCommand ...), so nothing needs to exist on the machine.
# The generator (gen-managed-hooks.ps1) pins the event per blob at the entrypoint.
#
# Project dir: $env:CLAUDE_PROJECT_DIR (set by Claude Code for hooks). Owner: $env:USERNAME.
# ASCII-only on purpose.
$ErrorActionPreference = 'SilentlyContinue'

function Invoke-Lock([string]$event) {
  $dir = $env:CLAUDE_PROJECT_DIR
  if (-not $dir) { $dir = (Get-Location).Path }
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
  function Set-Claim {
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm'
    $body = @("OWNER=$me", "Who:     $me", "Started: $ts", "Host:    $env:COMPUTERNAME")
    Set-Content -Path $lock -Value $body -Encoding UTF8
    return $ts
  }

  switch ($event) {

    'sessionstart' {
      function Emit([string]$ctx) {
        $o = @{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $ctx } }
        $o | ConvertTo-Json -Compress -Depth 5
      }
      $copies = Get-Copies
      if ($copies.Count -gt 0) {
        $names = ($copies | ForEach-Object { $_.Name }) -join ', '
        Emit ("LOCK SYNC CONFLICT: found " + $names + " next to WORKING_NOW.txt. Two machines likely locked at once. Warn the user clearly in Russian: STOP, do not edit, reconcile the WORKING_NOW copies manually (COLLABORATION.md rule 5) and coordinate with the colleague.")
        return
      }
      if (Test-Path $lock) {
        $owner = Get-Owner
        if ($owner -eq $me) {
          Emit "LOCK already yours ($me) - OK to work. Tell the user briefly in Russian."
        } else {
          Emit ("LOCK WARNING: project is BUSY by colleague '" + $owner + "' (WORKING_NOW.txt). Work in turns: do NOT edit files until the lock is released. Edits will be blocked by a guard hook. Warn the user clearly in Russian and suggest contacting the colleague.")
        }
      } else {
        $ts = Set-Claim
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
    }

    'pretooluse' {
      function Emit-Deny([string]$reason) {
        $o = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } }
        $o | ConvertTo-Json -Compress -Depth 5
      }
      function Claim-WithHandshake {
        Set-Claim | Out-Null
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
      $copies = Get-Copies
      if ($copies.Count -gt 0) {
        $names = ($copies | ForEach-Object { $_.Name }) -join ', '
        Emit-Deny ("LOCK SYNC CONFLICT: found " + $names + " next to WORKING_NOW.txt. Two machines locked at once. STOP. Reconcile WORKING_NOW copies manually (COLLABORATION.md rule 5), then continue.")
        return
      }
      if (Test-Path $lock) {
        $owner = Get-Owner
        if ($owner -and ($owner -ne $me)) {
          Emit-Deny ("Project LOCK held by colleague '" + $owner + "' (WORKING_NOW.txt). Edits are blocked until the lock is released. Coordinate and work in turns; the colleague runs /unlock or ends their session to release.")
        } elseif (-not $owner) {
          Claim-WithHandshake
        }
        # owner == me: proceed silently (no decision).
      } else {
        Claim-WithHandshake
      }
    }

    'sessionend' {
      if (Test-Path $lock) {
        $owner = Get-Owner
        if ((-not $owner) -or ($owner -eq $me)) {
          Remove-Item -Force $lock
          Write-Output ("LOCK released (" + $me + ").")
        } else {
          Write-Output ("LOCK belongs to '" + $owner + "', not you (" + $me + ") - not removing. If it is stale, delete WORKING_NOW.txt manually.")
        }
      } else {
        Write-Output "No lock to release."
      }
    }
  }
}

# --- entrypoint (generator pins the event per encoded blob) ---
Invoke-Lock $args[0]
