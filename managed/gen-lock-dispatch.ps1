# Generates the cross-platform lock as a SINGLE command per event, OS-dispatched via `||`:
#   powershell.exe -EncodedCommand <WIN>  ||  echo <MAC> | openssl base64 -d -A | sh
# Windows: the hook shell (cmd/Git Bash) finds powershell.exe -> runs it -> `||` short-circuits,
#          sh part never runs (so no openssl/sh needed on Windows). Windows paths handled natively.
# macOS:   powershell.exe not found -> non-zero -> `||` runs the sh pipe (confirmed working).
# No uname check, no separate hook entries, no smoke needed to know if sh runs on Windows.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$psFull = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $here 'lock.ps1')
$psBody = $psFull.Substring(0, $psFull.IndexOf('# --- entrypoint'))
$shTmpl = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $here 'lock.sh')

function DispatchCmd($ev) {
  $win = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($psBody + "Invoke-Lock '$ev'"))
  $mac = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($shTmpl.Replace('__EVENT__', $ev)))
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $win || echo $mac | openssl base64 -d -A | sh"
}
function Entry($ev, $matcher) {
  @( [ordered]@{ matcher=$matcher; hooks=@([ordered]@{ type='command'; command=(DispatchCmd $ev) }) } )
}

$tmpl = '{ "enabledPlugins": { "collab@tfm-collab": true }, "extraKnownMarketplaces": { "tfm-collab": { "autoUpdate": true, "source": { "repo": "TFM-OAA/claude-collab", "source": "github" } } }, "hooks": { "SessionStart": [ { "matcher": "startup|resume|clear", "hooks": [ { "type": "command", "command": "@@SS@@" } ] } ], "PreToolUse": [ { "matcher": "Edit|Write|NotebookEdit", "hooks": [ { "type": "command", "command": "@@PT@@" } ] } ], "SessionEnd": [ { "matcher": "", "hooks": [ { "type": "command", "command": "@@SE@@" } ] } ] } }'
$json = $tmpl.Replace('@@SS@@',(DispatchCmd 'sessionstart')).Replace('@@PT@@',(DispatchCmd 'pretooluse')).Replace('@@SE@@',(DispatchCmd 'sessionend'))
Set-Content -LiteralPath (Join-Path $here 'managed-settings.lock.dispatch.json') -Value $json -Encoding UTF8

$p = $json | ConvertFrom-Json
$c = $p.hooks.PreToolUse[0].hooks[0].command
Write-Output ("events: " + (($p.hooks.PSObject.Properties.Name) -join ', ') + " | one entry each: " + ($p.hooks.PreToolUse.Count -eq 1))
Write-Output ("has ' || echo ': " + ($c -match ' \|\| echo '))
$winB = ($c -split ' ')[5]; $macB = (($c -split ' \|\| echo ')[1] -split ' ')[0]
Write-Output ("WIN decodes, Invoke-Lock pretooluse: " + ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($winB)) -match "Invoke-Lock 'pretooluse'"))
Write-Output ("MAC decodes, LOCK_EVENT pretooluse: " + ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($macB)) -match 'LOCK_EVENT="pretooluse"'))
Write-Output ("full chars: " + $json.Length)