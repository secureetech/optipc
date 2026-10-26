# ============================================================
#  OptiPC 2.0 - Aiguillage des demandes de l'interface vers le moteur
#  Reprend a l'identique les routes de la V1 (meme format JSON),
#  plus les nouvelles routes de la 2.0. Plus de serveur HTTP : c'est
#  le logiciel natif qui transmet chaque demande ici.
# ============================================================

function ConvertTo-OptiJson($d){
    try { return ($d | ConvertTo-Json -Depth 10 -Compress) } catch { return '{"error":"serialisation"}' }
}

function Get-OptiTempData {
    $result = @{celsius=-1;available=$false;label="N/A"}
    try {
        $zones = @(Get-CimInstance -Namespace "root/WMI" -ClassName MSAcpi_ThermalZoneTemperature -EA Stop)
        if($zones.Count -gt 0){
            $cpuZone = $zones | Where-Object { $_.InstanceName -match "CPU|TZ0|CPUZ|THM" } | Select-Object -First 1
            if(-not $cpuZone){ $cpuZone = $zones[0] }
            $celsius = [math]::Round(($cpuZone.CurrentTemperature / 10) - 273.15, 1)
            if($celsius -gt 0 -and $celsius -lt 120){ $result = @{celsius=$celsius;available=$true;label="$celsius" + [char]176 + "C";instance=$cpuZone.InstanceName} }
        }
    } catch {}
    $result
}

function Read-OptiTextLogTail($lf){
    $ls = [string[]]@()
    try{
        if([IO.File]::Exists($lf)){
            $fs = [IO.File]::Open($lf,'Open','Read','ReadWrite')
            try{ $sr = New-Object IO.StreamReader($fs,[Text.Encoding]::UTF8); $txt = $sr.ReadToEnd() } finally { $fs.Close() }
            $ls = [string[]]@($txt -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | ForEach-Object { [string]$_ })
        }
    }catch{}
    @{lines=$ls}
}

function Stop-OptiProcessTree([int]$pidInt){
    $sysProcs = @('System','Idle','Registry','smss','csrss','wininit','services','lsass','MemCompression','winlogon','dwm','OptiPC')
    $proc = Get-Process -Id $pidInt -EA SilentlyContinue
    if(-not $proc){ return @{success=$true;message="Deja termine"} }
    if($sysProcs -contains $proc.ProcessName){ return @{success=$false;error="Processus systeme protege : $($proc.ProcessName)"} }
    $pName = $proc.ProcessName
    $svc = Get-Service -EA SilentlyContinue | Where-Object {
        $_.Status -eq 'Running' -and ($_.ServiceName -match [regex]::Escape($pName) -or $_.DisplayName -match [regex]::Escape($pName))
    } | Select-Object -First 1
    if($svc){ try { Set-Service $svc.ServiceName -StartupType Disabled -EA SilentlyContinue; Stop-Service $svc.ServiceName -Force -EA SilentlyContinue } catch {} }
    try {
        Get-ScheduledTask -EA SilentlyContinue | Where-Object {
            $_.TaskName -match [regex]::Escape($pName) -or ($_.Actions | Where-Object { $_.Execute -match [regex]::Escape($pName) })
        } | Disable-ScheduledTask -EA SilentlyContinue | Out-Null
    } catch {}
    foreach($p in @(Get-Process -Name $pName -EA SilentlyContinue | Select-Object -ExpandProperty Id)){ cmd /c "taskkill /F /T /PID $p 2>nul" | Out-Null }
    Start-Sleep -Milliseconds 800
    if(Get-Process -Id $pidInt -EA SilentlyContinue){ Stop-Process -Id $pidInt -Force -EA SilentlyContinue; Start-Sleep -Milliseconds 500 }
    if(-not (Get-Process -Id $pidInt -EA SilentlyContinue)){
        return @{success=$true;name=$pName;message="$pName termine (arborescence complete)";service=$(if($svc){$svc.ServiceName}else{$null})}
    }
    @{success=$false;error="$pName : impossible a terminer (protege par Windows)"}
}

function Invoke-OptiRoute([string]$path, [string]$method, [string]$bodyText, [string]$query){
    $ProgressPreference = 'SilentlyContinue'
    $global:ProgressPreference = 'SilentlyContinue'
    $global:PSDefaultParameterValues['Get-CimInstance:OperationTimeoutSec'] = 30
    $b = $null
    if($bodyText){ try { $b = $bodyText | ConvertFrom-Json } catch { $b = $null } }
    $q = @{}
    if($query){ foreach($kv in ($query.TrimStart('?') -split '&')){ $p = $kv.Split('=',2); if($p.Count -eq 2){ $q[[Uri]::UnescapeDataString($p[0])] = [Uri]::UnescapeDataString($p[1]) } } }
    $isGet = ($method -eq 'GET')
    $status = 200
    $r = $null
    try {
        switch -Regex ($path) {
            # ── Routes de la V1 (inchangees) ─────────────────────────────
            "^/api/analyze$"         { $r = Get-DirtyAnalysis; try{ Add-OptiScoreHistory $r.score }catch{}; break }
            "^/api/clean$"           { $r = Invoke-Cleaning @($b.selected); break }
            "^/api/ram$"             { $r = Get-RamData; break }
            "^/api/ram/optimize$"    { $r = Optimize-Ram; break }
            "^/api/temp$"            { $r = Get-OptiTempData; break }
            "^/api/startup$"         { $r = @{items=@(Get-StartupItems)}; break }
            "^/api/startup/toggle$"  { $qq = @{ok=$true}; if(-not $b.enable){ $qq = Use-OptiFreeQuota 'startup' 2 }; if($qq.ok){ $r = Toggle-StartupItem $b.name $b.regPath $b.enable } else { $r = $qq }; break }
            "^/api/apps$"            { $r = @{apps=@(Get-AppsFull)}; break }
            "^/api/apps/refresh$"    { Clear-AppsCache; $r = @{apps=@(Get-AppsFull)}; break }
            "^/api/perf$"            { $r = Get-PerfData; break }
            "^/api/apps/uninstall2$" { $qq = Use-OptiFreeQuota 'uninstall' 3; if($qq.ok){ $r = Invoke-AppUninstallV2 $b.app $b.mode } else { $r = $qq }; break }
            "^/api/apps/leftovers$"  { $r = Get-AppLeftovers $b.app; break }
            "^/api/apps/leftovers/clean$" { $r = Invoke-RemoveLeftovers $b.app; break }
            "^/api/apps/force-uninstall$" { $qq = Use-OptiFreeQuota 'uninstall' 3; if($qq.ok){ $r = Invoke-AppForceUninstall $b.app } else { $r = $qq }; break }
            "^/api/apps/force-uninstall-log$" { $r = Read-OptiTextLogTail "$env:TEMP\optipc_appforce_log.txt"; break }
            "^/api/security/quarantine$"  { if(Test-IsPro){ $r = Invoke-Quarantine $b.path $b.reason } else { $r = @{ok=$false;msg="Fonction reservee a la version Premium"} }; break }
            "^/api/security/ignore$"      { $r = Add-WhiteList $b.path $b.name; break }
            "^/api/security/ignore/clear$"{ $r = Clear-WhiteList; break }
            "^/api/quarantine$"           { $r = @{items=@(Get-QuarManifest)}; break }
            "^/api/quarantine/restore$"   { $r = Restore-QuarItem $b.id; break }
            "^/api/quarantine/delete$"    { $r = Remove-QuarItem $b.id; break }
            "^/api/defender/fullscan$"    { $r = Start-DefenderFullScan; break }
            "^/api/defender/status$"      { $r = Get-DefenderScanStatus; break }
            "^/api/apps/uninstall$"  { $qq = Use-OptiFreeQuota 'uninstall' 3; if($qq.ok){ $r = Invoke-Uninstall $b.uninstallString } else { $r = $qq }; break }
            "^/api/apps/force$"      { $qq = Use-OptiFreeQuota 'uninstall' 3; if($qq.ok){ $r = ForceRemove-App $b.name $b.uninstallString } else { $r = $qq }; break }
            "^/api/bigfiles$"        { $r = @{files=@(Get-BigFiles)}; break }
            "^/api/duplicates$"      { $r = @{groups=@(Find-Duplicates)}; break }
            "^/api/virtmem$"         { $r = Get-VirtMemInfo; break }
            "^/api/diskinfo$"        { $r = Get-DiskInfoData; break }
            "^/api/registry/scan$"   { $r = Scan-Registry; break }
            "^/api/registry/clean$"  { $r = Clean-RegistryKeys @($b.keys); break }
            "^/api/services$"        { $r = @{services=@(Get-ServicesStatus)}; break }
            "^/api/services/toggle$" { $r = Toggle-ServiceItem $b.name $b.enable; break }
            "^/api/powerplan$"       { $r = Get-PowerPlans; break }
            "^/api/powerplan/set$"   { $r = Set-ActivePowerPlan $b.guid; break }
            "^/api/repair$"          { if($b.action -eq 'virtmem_set'){ $r = Set-OptiPagefile ([int]$b.sizeMB) } elseif($b.action -eq 'virtmem_optimize'){ $r = Set-OptiPagefile 0 } else { $r = Invoke-SystemRepair $b.action }; break }
            "^/api/visual$"          { $r = Set-VisualFX $b.mode; break }
            "^/api/pagefile$"        { $r = Set-PagefileConfig $b.mode; break }
            "^/api/sysinfo$"         { $r = Get-SysInfo; break }
            "^/api/browsers$"        { $r = Get-BrowserSizes; break }
            "^/api/clean/browsers$"  { $r = Clear-BrowserCache @($b.browsers); break }
            "^/api/force-delete$"    { $r = Invoke-ForceDelete $b.path; break }
            "^/api/force-log$"       { $r = Read-OptiTextLogTail "$env:TEMP\optipc_force_log.txt"; break }
            "^/api/schedule$"        { if($isGet){ $r = Get-CleaningSchedule } else { $r = Set-CleaningSchedule $b.frequency $b.time }; break }
            "^/api/cleanlog$"        { $r = Get-CleanLog; break }
            "^/api/schedlog$"        {
                $dlf = "$env:TEMP\optipc_sched_debug.log"
                if(Test-Path $dlf){ $r = @{lines=@(Get-Content $dlf -Tail 100 -EA SilentlyContinue)} } else { $r = @{lines=@("[Aucun journal]")} }
                break
            }
            "^/api/process/kill$"    { $r = Stop-OptiProcessTree ([int]($b.pid)); break }
            "^/api/license/status$"   { $r = Get-LicenseStatus; break }
            "^/api/license/activate$" { $r = Invoke-ActivateLicense $b.key; break }
            "^/api/license/revoke$"   { $r = Invoke-RevokeLicense; break }
            "^/api/license/heartbeat$"{ $r = Invoke-LicenseHeartbeat ([bool]$b.force); break }
            "^/api/license/trial$"    { $r = Invoke-StartTrial $b.prenom $b.email $b.telephone $b.rappel $b.nom $b.newsletter; break }
            "^/api/diskcategories$"  { $r = Get-DiskCategories; break }
            "^/api/security/status$" { $r = Get-SecurityStatus; break }
            "^/api/security/scan$"   { $r = Invoke-MalwareScan; break }
            "^/api/scanner/start$"   { $r = Start-ScanSession $b.mode; break }
            "^/api/scanner/poll$"    { $r = Step-ScanPoll; break }
            "^/api/scanner/stop$"    { $r = Request-ScanStop; break }
            "^/api/settings$"        { if($isGet){ $r = Get-OptiSettings } else { $r = Set-OptiSettings $b }; break }
            "^/api/consent$"         { if($isGet){ $r = Get-ConsentStatus } else { $r = Set-Consent $b.version }; break }
            "^/api/update/check$"    { $r = Get-OptiPCUpdate ([bool]$b.force); break }
            "^/api/update/install$"  { $r = Install-OptiPCUpdate $b.url $b.sha256; break }
            "^/api/version$"         { $r = @{version=(Get-OptiPCVersion)}; break }
            "^/api/errorlog$"        {
                $lf = "$env:LOCALAPPDATA\OptiPC\errors.log"
                if(Test-Path $lf){ $r = @{lines=@(Get-Content $lf -Tail 120 -EA SilentlyContinue)} } else { $r = @{lines=@("(aucune erreur enregistree)")} }
                break
            }
            "^/api/openurl$"         { $r = Open-ExternalUrl $b.url; break }
            "^/api/security/fix$"    { $r = Do-SecurityFix $b.action; break }
            "^/api/security/remove$" { if(Test-IsPro){ $r = Remove-ThreatItem $b.path } else { $r = @{ok=$false;msg="Fonction reservee a la version Premium"} }; break }
            "^/api/security/open$"   { $r = Open-ThreatPath $b.path; break }
            "^/api/access/status$"   { $r = Get-AccessStatus; break }
            "^/api/access/toggle$"   { $r = Set-AccessCtrl $b.feature ([bool]$b.enable); break }
            "^/api/antitracking$"    { $r = Invoke-AntiTracking; break }

            # ── Nouvelles routes 2.0 ──────────────────────────────────────
            "^/api/space/scan$"      { $r = Get-OptiSpaceScan ([bool]$b.force); break }
            "^/api/space/remove$"    { $r = Remove-OptiSpaceItems @($b.paths); break }
            "^/api/space/move$"      { $r = Move-OptiSpaceItems @($b.paths) ([string]$b.dest); break }
            "^/api/health$"          { if($b -and $b.force){ try{ Remove-Item (Get-OptiCacheFile 'health') -Force -EA SilentlyContinue }catch{} }; $r = Get-OptiHealthAll; break }
            "^/api/perf2$"           { $r = Get-OptiPerf2; break }
            "^/api/network$"         { $r = Get-OptiNetwork ([bool]$b.force); break }
            "^/api/network/speed$"   { $r = Invoke-OptiSpeedTest; break }
            "^/api/softupdates$"     { $r = Get-OptiSoftUpdates ([bool]$b.force); break }
            "^/api/softupdates/install$" { $r = Invoke-OptiSoftUpdate ([string]$b.id); break }
            "^/api/restorepoints$"   { $r = Get-OptiRestorePoints; break }
            "^/api/restorepoint$"    { $r = New-OptiRestorePoint ([string]$b.desc); break }
            "^/api/restore/open$"    { $r = Open-OptiRestoreUI; break }
            "^/api/score/history$"   { $r = Get-OptiScoreHistory; break }
            "^/api/callback$"        { $r = Send-OptiCallbackRequest ([string]$b.prenom) ([string]$b.telephone) ([string]$b.sujet); break }
            "^/api/browsers/hijack$"  { $r = Get-OptiBrowserHijack; break }
            "^/api/browsers/repair$"  { $r = Repair-OptiBrowserHijack; break }
            "^/api/boot$"            { $r = Get-OptiBootTime; break }
            default                  { $status = 404; $r = @{error="Not found"} }
        }
    } catch {
        $status = 500
        $err = ''
        try { $err = [string]$_.Exception.Message } catch {}
        try {
            $ld = "$env:LOCALAPPDATA\OptiPC"
            if(-not(Test-Path $ld)){ [System.IO.Directory]::CreateDirectory($ld) | Out-Null }
            $msg = "[{0}] ROUTE {1}`r`n    ERREUR : {2}`r`n    TYPE   : {3}`r`n    LIGNE  : {4}`r`n" -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $path, $_.Exception.Message, $_.Exception.GetType().FullName, $_.InvocationInfo.ScriptLineNumber
            [System.IO.File]::AppendAllText("$ld\errors.log", $msg, [Text.Encoding]::UTF8)
        } catch {}
        $r = @{error='erreur_interne'; message=$err}
    }
    [pscustomobject]@{ s = $status; j = (ConvertTo-OptiJson $r) }
}
