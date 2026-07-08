# Installs the collaboration LOCK infrastructure into a target project.
# Copies the hook scripts + /lock,/unlock commands + a COLLABORATION.md template.
# settings.json merge is intentionally left to Claude (the skill) - see SKILL.md.
# Idempotent: hooks/commands are overwritten (canonical); COLLABORATION.md is kept if present.
# ASCII-only on purpose (Windows PowerShell 5.1 reads .ps1 as ANSI without BOM).
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Target
)
$ErrorActionPreference = 'Stop'

$assets = Join-Path $PSScriptRoot 'assets'
if (-not (Test-Path $assets)) { Write-Error "assets folder not found next to install-collab.ps1"; exit 1 }
if (-not (Test-Path $Target)) { Write-Error "Target project folder does not exist: $Target"; exit 1 }
$Target = (Resolve-Path $Target).Path

$claude   = Join-Path $Target '.claude'
$hooksDst = Join-Path $claude 'hooks'
$cmdDst   = Join-Path $claude 'commands'
New-Item -ItemType Directory -Force -Path $hooksDst, $cmdDst | Out-Null

# 1. Hooks (overwrite - canonical, ASCII, byte-exact copies).
Copy-Item (Join-Path $assets 'hooks\*.ps1') -Destination $hooksDst -Force
Write-Output ("[ok]   hooks -> " + $hooksDst)

# 2. Commands /lock /unlock (overwrite).
Copy-Item (Join-Path $assets 'commands\lock.md')   -Destination $cmdDst -Force
Copy-Item (Join-Path $assets 'commands\unlock.md') -Destination $cmdDst -Force
Write-Output ("[ok]   commands (lock.md, unlock.md) -> " + $cmdDst)

# 3. COLLABORATION.md - only if absent (do not clobber a customized one).
$collabDst = Join-Path $Target 'COLLABORATION.md'
if (Test-Path $collabDst) {
  Write-Output "[skip] COLLABORATION.md already exists - left untouched"
} else {
  Copy-Item (Join-Path $assets 'COLLABORATION.template.md') -Destination $collabDst -Force
  Write-Output "[ok]   COLLABORATION.md created from template"
}

# 4. Report settings.json state for the merge step (Claude handles the actual merge).
$settings = Join-Path $claude 'settings.json'
if (Test-Path $settings) {
  Write-Output "[next] settings.json EXISTS -> merge the 3 hook entries (SessionStart/PreToolUse/SessionEnd), do NOT overwrite"
} else {
  Write-Output "[next] settings.json MISSING -> create it from assets\settings.hooks.json"
}
Write-Output ("[done] target: " + $Target)
exit 0
