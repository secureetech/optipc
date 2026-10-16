param([string]$T)
$root = Split-Path $PSScriptRoot -Parent
$src = (Get-Content "$root/src/engine/functions.ps1" -Raw) + "`n" + (Get-Content "$root/src/engine/extra.ps1" -Raw) + "`n" + (Get-Content "$root/src/engine/router.ps1" -Raw)
. ([scriptblock]::Create($src))
$env:LOCALAPPDATA = "$T/lad"; $env:TEMP = "$T/tmp"; $env:USERPROFILE = $T
New-Item -ItemType Directory -Force "$T/lad","$T/tmp" | Out-Null
function Get-OptiUserRoots { @(@{label='Telechargements';path="$T/Downloads"},@{label='Documents';path="$T/Documents"},@{label='Images';path="$T/Pictures"},@{label='Videos';path="$T/Videos"}) }
"SELFTEST: " + (Format-Size 1048576) + '|' + (Format-Size 0) + '|' + @(Get-ScanPlan 'quick').Count
try { $s = Get-OptiSpaceScan $true; "SPACE OK: " + ($s | ConvertTo-Json -Depth 8 -Compress) } catch { "SPACE ERR: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber + " : " + $_.InvocationInfo.Line }
Add-OptiScoreHistory 72
"HIST: " + ((Get-OptiScoreHistory) | ConvertTo-Json -Compress)
Get-ChildItem "$T/lad/OptiPC" | % Name
