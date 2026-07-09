# Generates the MANAGED-settings `hooks` JSON for the collaboration lock.
# Encodes lock.ps1 (event pinned per blob) as base64 -EncodedCommand so the whole
# logic ships inside the managed hook command — zero files on the machine.
#
# Also emits a Phase-0 SMOKE test (trivial SessionStart marker) to first prove the
# managed-hook channel fires in the desktop app before deploying the real lock.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File .\gen-managed-hooks.ps1
# Output: managed-settings.smoke.json  +  managed-settings.lock.json  (next to this script)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Enc([string]$src) {
  # PowerShell -EncodedCommand expects base64 of UTF-16LE (Unicode) bytes.
  [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($src))
}
function PwshCmd([string]$b64) {
  'powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $b64
}
function Pretty([string]$json) {
  # round-trip validates the JSON and pretty-prints it
  $json | ConvertFrom-Json | ConvertTo-Json -Depth 20
}

# --- production lock blobs (one per event, event pinned at the entrypoint) ---
$full   = Get-Content -Raw -LiteralPath (Join-Path $here 'lock.ps1')
$marker = '# --- entrypoint'
$idx    = $full.IndexOf($marker)
if ($idx -lt 0) { throw 'entrypoint marker not found in lock.ps1' }
$body   = $full.Substring(0, $idx)

$ssCmd = PwshCmd (Enc ($body + "Invoke-Lock 'sessionstart'"))
$ptCmd = PwshCmd (Enc ($body + "Invoke-Lock 'pretooluse'"))
$seCmd = PwshCmd (Enc ($body + "Invoke-Lock 'sessionend'"))

# single-quoted template; literal { } doubled for -f; base64 commands are JSON-safe (no " or \)
$tmpl = '{{ "hooks": {{ "SessionStart": [ {{ "matcher": "startup|resume|clear", "hooks": [ {{ "type": "command", "command": "{0}" }} ] }} ], "PreToolUse": [ {{ "matcher": "Edit|Write|NotebookEdit", "hooks": [ {{ "type": "command", "command": "{1}" }} ] }} ], "SessionEnd": [ {{ "matcher": "", "hooks": [ {{ "type": "command", "command": "{2}" }} ] }} ] }} }}'
$lockJson = Pretty ($tmpl -f $ssCmd, $ptCmd, $seCmd)
Set-Content -LiteralPath (Join-Path $here 'managed-settings.lock.json') -Value $lockJson -Encoding UTF8

# --- Phase-0 smoke test: does a managed SessionStart hook fire at all in the desktop? ---
$smokeSrc  = '$p = Join-Path $env:CLAUDE_PROJECT_DIR ".mgmt_hook_ok.txt"; Set-Content -LiteralPath $p -Value ("managed hook OK " + (Get-Date))'
$smokeCmd  = PwshCmd (Enc $smokeSrc)
$smokeTmpl = '{{ "hooks": {{ "SessionStart": [ {{ "matcher": "startup|resume|clear", "hooks": [ {{ "type": "command", "command": "{0}" }} ] }} ] }} }}'
$smokeJson = Pretty ($smokeTmpl -f $smokeCmd)
Set-Content -LiteralPath (Join-Path $here 'managed-settings.smoke.json') -Value $smokeJson -Encoding UTF8

Write-Output '=== SMOKE (Phase 0) decoded source ==='
Write-Output $smokeSrc
Write-Output ''
Write-Output '=== managed-settings.smoke.json ==='
Write-Output $smokeJson
Write-Output ''
Write-Output '=== lock.json length (chars) / decoded blob sanity ==='
Write-Output ('lock.json chars: ' + $lockJson.Length)
Write-Output 'Wrote: managed-settings.smoke.json , managed-settings.lock.json'
