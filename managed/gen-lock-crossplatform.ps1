# Generates the cross-platform MANAGED `hooks` JSON for the real collaboration lock.
# Windows: lock.ps1 -> base64(UTF-16LE) -> powershell.exe -EncodedCommand   (event pinned)
# macOS:   lock.sh  -> base64(UTF-8)     -> echo <b64> | openssl base64 -d -A | sh  (event pinned)
# Two hook entries per event (win + mac) so the right one runs per OS; the "foreign" one no-ops.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\gen-lock-crossplatform.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$psFull = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $here 'lock.ps1')
$psBody = $psFull.Substring(0, $psFull.IndexOf('# --- entrypoint'))
$shTmpl = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $here 'lock.sh')

function WinCmd($ev) {
  $b = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($psBody + "Invoke-Lock '$ev'"))
  'powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $b
}
function MacCmd($ev) {
  $s = $shTmpl.Replace('__EVENT__', $ev)
  $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
  'echo ' + $b + ' | openssl base64 -d -A | sh'
}
function Pair($ev, $matcher) {
  @(
    [ordered]@{ matcher=$matcher; hooks=@([ordered]@{ type='command'; command=(WinCmd $ev) }) },
    [ordered]@{ matcher=$matcher; hooks=@([ordered]@{ type='command'; command=(MacCmd $ev) }) }
  )
}

$obj = [ordered]@{
  enabledPlugins        = [ordered]@{ 'collab@tfm-collab' = $true }
  extraKnownMarketplaces = [ordered]@{ 'tfm-collab' = [ordered]@{ autoUpdate = $true; source = [ordered]@{ repo = 'TFM-OAA/claude-collab'; source = 'github' } } }
  hooks = [ordered]@{
    SessionStart = Pair 'sessionstart' 'startup|resume|clear'
    PreToolUse   = Pair 'pretooluse'   'Edit|Write|NotebookEdit'
    SessionEnd   = Pair 'sessionend'   ''
  }
}
$json = $obj | ConvertTo-Json -Depth 25
Set-Content -LiteralPath (Join-Path $here 'managed-settings.lock.crossplatform.json') -Value $json -Encoding UTF8

$p = $json | ConvertFrom-Json
Write-Output ("events: " + (($p.hooks.PSObject.Properties.Name) -join ', '))
Write-Output ("SessionStart entries: " + $p.hooks.SessionStart.Count + " | PreToolUse: " + $p.hooks.PreToolUse.Count + " | SessionEnd: " + $p.hooks.SessionEnd.Count)
Write-Output ("total JSON chars: " + $json.Length)
Write-Output "--- sample mac SessionStart cmd (head) ---"
Write-Output ($p.hooks.SessionStart[1].hooks[0].command.Substring(0,60) + " ...")
Write-Output "--- sanity: decode mac sessionstart blob, tail ---"
$macB64 = ($p.hooks.SessionStart[1].hooks[0].command -split ' ')[1]
$dec = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($macB64))
Write-Output ("mac script LOCK_EVENT line: " + (($dec -split "`n") | Where-Object { $_ -match 'LOCK_EVENT=' }))