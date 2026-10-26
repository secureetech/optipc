function Format-Size($b) {
    if(-not $b -or $b -le 0){return "0 B"}
    if($b -ge 1GB){return "{0:N1} GB" -f ($b/1GB)}
    if($b -ge 1MB){return "{0:N0} MB" -f ($b/1MB)}
    if($b -ge 1KB){return "{0:N0} KB" -f ($b/1KB)}
    "$b B"
}
function Get-FolderSize($path) {
    try {
        $total = [long]0
        $stack = [System.Collections.Stack]::new()
        $di = [System.IO.DirectoryInfo]::new($path)
        if(-not $di.Exists){return [long]0}
        $stack.Push($di)
        while($stack.Count -gt 0) {
            $d = $stack.Pop()
            try {
                foreach($f in $d.EnumerateFiles()){$total += $f.Length}
                foreach($sub in $d.EnumerateDirectories()){$stack.Push($sub)}
            } catch {}
        }
        $total
    } catch { [long]0 }
}
function Get-RamData {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        if(-not $os){return @{totalMB=0;freeMB=0;usedMB=0;pct=0;cpuPct=0;processes=@()}}
        $tot = [math]::Round($os.TotalVisibleMemorySize/1024)
        $free = [math]::Round($os.FreePhysicalMemory/1024)
        $used = $tot - $free
        $pct = if($tot -gt 0){[math]::Round(($used/$tot)*100)}else{0}
        # CPU rapide via PerfFormattedData (instantane, pas de blocage)
        $cpuPct = 0
        try {
            $perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -EA SilentlyContinue
            $cpuPct = if($perf){[math]::Round($perf.PercentProcessorTime)}else{0}
        } catch {}
        $procs = @(Get-Process -EA SilentlyContinue | Sort-Object WorkingSet64 -Descending | ForEach-Object {
            @{name=$_.ProcessName;pid=$_.Id;memMB=[math]::Round($_.WorkingSet64/1MB)}
        })
        @{totalMB=$tot;freeMB=$free;usedMB=$used;pct=$pct;cpuPct=$cpuPct;processes=$procs}
    } catch {@{totalMB=0;freeMB=0;usedMB=0;pct=0;cpuPct=0;processes=@()}}
}
function Optimize-Ram {
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 300
    Get-RamData
}
function Get-OptiBrowserCachePaths($browser){
    # Dossiers de CACHE uniquement (jamais favoris, mots de passe, historique,
    # cookies ou extensions), pour TOUS les profils du navigateur.
    $out = New-Object System.Collections.Generic.List[string]
    $chromium = @{
        chrome = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        edge   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        brave  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    }
    if($chromium.ContainsKey([string]$browser)){
        $root = $chromium[[string]$browser]
        if(Test-Path -LiteralPath $root){
            foreach($pd in @(Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$' -or $_.Name -eq 'Guest Profile' })){
                foreach($sub in @('Cache','Code Cache','GPUCache','Media Cache')){
                    $p = Join-Path $pd.FullName $sub
                    if(Test-Path -LiteralPath $p){ $out.Add($p) }
                }
            }
            foreach($sub in @('ShaderCache','GrShaderCache')){
                $p = Join-Path $root $sub
                if(Test-Path -LiteralPath $p){ $out.Add($p) }
            }
        }
    } elseif($browser -eq 'firefox'){
        # ATTENTION : le cache de Firefox est dans LOCALAPPDATA. Le dossier
        # APPDATA\Mozilla\Firefox\Profiles contient les favoris, les mots de
        # passe et l'historique : OptiPC ne doit JAMAIS le vider.
        $root = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
        if(Test-Path -LiteralPath $root){
            foreach($pd in @(Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue)){
                foreach($sub in @('cache2','startupCache','thumbnails','jumpListCache')){
                    $p = Join-Path $pd.FullName $sub
                    if(Test-Path -LiteralPath $p){ $out.Add($p) }
                }
            }
        }
    } elseif($browser -eq 'opera'){
        foreach($n in @('Opera Stable','Opera GX Stable')){
            foreach($base in @("$env:LOCALAPPDATA\Opera Software\$n","$env:APPDATA\Opera Software\$n")){
                foreach($sub in @('Cache','Code Cache','GPUCache','Default\Cache','Default\Code Cache','Default\GPUCache')){
                    $p = Join-Path $base $sub
                    if(Test-Path -LiteralPath $p){ $out.Add($p) }
                }
            }
        }
    }
    # Tableau simple de chemins non vides (jamais de tableau vide imbrique)
    [string[]]@($out | Where-Object { $_ } | Select-Object -Unique)
}

# Categories autorisees pour un nettoyage AUTOMATIQUE (planifie / silencieux) :
# jamais la corbeille, les fichiers recents, le Prefetch, les journaux ni Windows.old.
function Get-OptiAutoCleanIds { @('temp_win','thumbnails','d3d','shader_cache','wu_dl','delivery','wer','chrome','edge','brave','firefox','opera') }

function Get-DirtyAnalysis {
    $cats = @(
        @{id="temp_win";cat="Windows";label="Fichiers temporaires";paths=@($env:TEMP,"C:\Windows\Temp")}
        @{id="thumbnails";cat="Windows";label="Cache miniatures";paths=@("$env:LOCALAPPDATA\Microsoft\Windows\Explorer")}
        @{id="recent";cat="Windows";label="Fichiers recents";paths=@("$env:APPDATA\Microsoft\Windows\Recent");optional=$true}
        @{id="recycle";cat="Windows";label="Corbeille";paths=@();special="recycle"}
        @{id="chrome";cat="Navigateurs";label="Cache Chrome";paths=@(Get-OptiBrowserCachePaths 'chrome')}
        @{id="edge";cat="Navigateurs";label="Cache Edge";paths=@(Get-OptiBrowserCachePaths 'edge')}
        @{id="firefox";cat="Navigateurs";label="Cache Firefox";paths=@(Get-OptiBrowserCachePaths 'firefox')}
        @{id="brave";cat="Navigateurs";label="Cache Brave";paths=@(Get-OptiBrowserCachePaths 'brave')}
        @{id="opera";cat="Navigateurs";label="Cache Opera";paths=@(Get-OptiBrowserCachePaths 'opera')}
        @{id="wu_dl";cat="Avance";label="Mises a jour Windows";paths=@("C:\Windows\SoftwareDistribution\Download")}
        @{id="prefetch";cat="Avance";label="Cache Prefetch";paths=@("C:\Windows\Prefetch");optional=$true}
        @{id="minidump";cat="Avance";label="Dump memoire";paths=@("C:\Windows\Minidump")}
        @{id="delivery";cat="Avance";label="Delivery Optimization";paths=@("C:\Windows\SoftwareDistribution\DeliveryOptimization")}
        @{id="d3d";cat="Avance";label="Cache DirectX";paths=@("$env:LOCALAPPDATA\D3DSCache")}
        @{id="teams";cat="Avance";label="Cache Teams";paths=@("$env:APPDATA\Microsoft\Teams\Cache")}
        @{id="logs";cat="Avance";label="Journaux erreurs";paths=@("$env:SystemRoot\Logs")}
        @{id="wu_cache";cat="Windows";label="Cache Windows Update";paths=@("C:\Windows\SoftwareDistribution\Download","C:\Windows\SoftwareDistribution\DataStore\Logs")}
        @{id="upgrade_logs";cat="Windows";label="Journaux mise a niveau Windows";paths=@("C:\Windows\Panther","C:\Windows\Logs\MoSetup")}
        @{id="downloaded_prog";cat="Windows";label="Fichiers de programmes telecharges";paths=@("C:\Windows\Downloaded Program Files")}
        @{id="wer";cat="Windows";label="Rapports d erreurs Windows";paths=@("$env:ProgramData\Microsoft\Windows\WER\ReportArchive","$env:ProgramData\Microsoft\Windows\WER\ReportQueue","$env:ProgramData\Microsoft\Windows\WER\Temp")}
        @{id="shader_cache";cat="Avance";label="Cache de nuanceur DirectX";paths=@("$env:LOCALAPPDATA\Microsoft\DirectX Shader Cache")}
        @{id="winold";cat="Avance";label="Windows.old (ancienne installation)";paths=@();special="winold";warn="Vous ne pourrez plus revenir a la version precedente de Windows apres suppression"}
    )
    $results = foreach($c in $cats){
        $sz = [long]0
        if($c.special -eq "recycle"){
            try{$sh=New-Object -ComObject Shell.Application;$rb=$sh.Namespace(0xA);$sz=[long]($rb.Items()|ForEach-Object{try{[long]$_.ExtendedProperty("System.Size")}catch{0}}|Measure-Object -Sum).Sum}catch{$sz=0}
        } elseif($c.special -eq "winold"){
            $wp = "$env:SystemDrive\Windows.old"
            if(Test-Path $wp -EA SilentlyContinue){ $sz = Get-FolderSize $wp }
        } else {
            foreach($p in $c.paths){if(Test-Path $p){$sz += Get-FolderSize $p}}
        }
        $isWarn = [bool]$c.warn
        [PSCustomObject]@{id=$c.id;cat=$c.cat;label=$c.label;size=$sz;sizeStr=(Format-Size $sz);checked=(-not $isWarn -and -not $c.optional);warn=$(if($isWarn){[string]$c.warn}else{""})}
    }
    $cleanable = @($results | Where-Object { -not $_.warn })
    $total = [long]($cleanable | Measure-Object -Property size -Sum).Sum
    $ram = Get-RamData
    $score = 100
    if($total -gt 5GB){$score-=25}elseif($total -gt 1GB){$score-=15}elseif($total -gt 100MB){$score-=5}
    if($ram.pct -gt 85){$score-=20}elseif($ram.pct -gt 65){$score-=8}
    $wo = $results | Where-Object { $_.id -eq 'winold' } | Select-Object -First 1
    @{total=(Format-Size $total);totalBytes=$total;items=@($results);score=[math]::Max(40,$score);ramPct=$ram.pct;winoldSize=$(if($wo){$wo.sizeStr}else{'0 B'})}
}

function Invoke-Cleaning($selected){
    $cleaned = [long]0
    $map = @{
        temp_win=@($env:TEMP,"C:\Windows\Temp")
        thumbnails=@("$env:LOCALAPPDATA\Microsoft\Windows\Explorer")
        recent=@("$env:APPDATA\Microsoft\Windows\Recent")
        chrome=@(Get-OptiBrowserCachePaths 'chrome')
        edge=@(Get-OptiBrowserCachePaths 'edge')
        firefox=@(Get-OptiBrowserCachePaths 'firefox')
        brave=@(Get-OptiBrowserCachePaths 'brave')
        opera=@(Get-OptiBrowserCachePaths 'opera')
        wu_dl=@("C:\Windows\SoftwareDistribution\Download")
        prefetch=@("C:\Windows\Prefetch")
        minidump=@("C:\Windows\Minidump")
        delivery=@("C:\Windows\SoftwareDistribution\DeliveryOptimization")
        d3d=@("$env:LOCALAPPDATA\D3DSCache")
        teams=@("$env:APPDATA\Microsoft\Teams\Cache")
        logs=@("$env:SystemRoot\Logs")
        wu_cache=@("C:\Windows\SoftwareDistribution\Download","C:\Windows\SoftwareDistribution\DataStore\Logs")
        upgrade_logs=@("C:\Windows\Panther","C:\Windows\Logs\MoSetup")
        downloaded_prog=@("C:\Windows\Downloaded Program Files")
        wer=@("$env:ProgramData\Microsoft\Windows\WER\ReportArchive","$env:ProgramData\Microsoft\Windows\WER\ReportQueue","$env:ProgramData\Microsoft\Windows\WER\Temp")
        shader_cache=@("$env:LOCALAPPDATA\Microsoft\DirectX Shader Cache")
    }
    # 27/10/2026 : version gratuite = la moitie de ce qui est trouve (par categories), le reste avec Premium
    $limitedBytes = [long]0
    $isProC = $false; try{ $isProC = [bool](Test-IsPro) }catch{}
    if(-not $isProC){
        $sizes = @{}
        foreach($id in @($selected)){
            $s = [long]0
            if($id -eq 'winold'){ if(Test-Path "$env:SystemDrive\Windows.old" -EA SilentlyContinue){ $s = [long](Get-FolderSize "$env:SystemDrive\Windows.old") } }
            elseif($map.ContainsKey($id)){ foreach($p in $map[$id]){ if($p -and (Test-Path $p -EA SilentlyContinue)){ try{ $s += [long](Get-FolderSize $p) }catch{} } } }
            $sizes[[string]$id] = $s
        }
        $total = [long]0; foreach($v in $sizes.Values){ $total += [long]$v }
        $cap = [long]($total / 2); $acc = [long]0; $keep = @()
        foreach($k in @($sizes.Keys | Sort-Object { -[long]$sizes[$_] })){
            if($acc + [long]$sizes[$k] -le $cap){ $keep += $k; $acc += [long]$sizes[$k] }
        }
        if(-not $keep.Count -and $sizes.Count){ $keep = @(@($sizes.Keys | Sort-Object { [long]$sizes[$_] })[0]); $acc = [long]$sizes[$keep[0]] }
        $limitedBytes = [long]($total - $acc)
        $selected = $keep
    }
    foreach($id in $selected){
        if($id -eq "recycle"){try{Clear-RecycleBin -Force -EA SilentlyContinue}catch{};continue}
        if($id -eq "winold"){
            $wp = "$env:SystemDrive\Windows.old"
            if(Test-Path $wp -EA SilentlyContinue){
                $cleaned += Get-FolderSize $wp
                try{ Remove-PathHard $wp | Out-Null }catch{}
            }
            continue
        }
        if($map.ContainsKey($id)){
            foreach($p in $map[$id]){
                if(-not $p){ continue }
                $pn = ([string]$p).TrimEnd('\')
                if($pn -match '(?i)\\Mozilla\\Firefox\\Profiles$' -or $pn -match '(?i)\\User Data$' -or $pn -match '(?i)^[a-z]:$'){ continue }
                if(Test-Path $p){$cleaned += Get-FolderSize $p;Get-ChildItem $p -Force -EA SilentlyContinue | Remove-Item -Force -Recurse -EA SilentlyContinue}
            }
        }
    }
    try {
        $logDir = "$env:LOCALAPPDATA\OptiPC"
        if(-not(Test-Path $logDir)){[System.IO.Directory]::CreateDirectory($logDir) | Out-Null}
        $logFile = "$logDir\clean.log"
        $dt = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
        $line = "[$dt] Nettoyage automatique : $(Format-Size $cleaned) liberes"
        Add-Content $logFile $line -EA SilentlyContinue
        if(Test-Path $logFile){
            $lines = Get-Content $logFile -EA SilentlyContinue
            if($lines.Count -gt 200){ $lines | Select-Object -Last 200 | Set-Content $logFile -EA SilentlyContinue }
        }
    } catch {}
    @{cleaned=(Format-Size $cleaned);cleanedBytes=$cleaned;success=$true;limitedBytes=$limitedBytes;limited=(Format-Size $limitedBytes)}
}

function Get-DiskInfoData {
    # .NET DriveInfo - fonctionne dans tous les contextes (runspaces, jobs...)
    $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object {$_.DriveType -eq 'Fixed' -and $_.IsReady} | ForEach-Object {
        $total = $_.TotalSize
        $free  = $_.AvailableFreeSpace
        $used  = $total - $free
        $pct   = if($total -gt 0){[math]::Round(($used/$total)*100)}else{0}
        @{letter=$_.Name.TrimEnd('\');total=(Format-Size $total);free=(Format-Size $free);used=(Format-Size $used);pct=$pct;freeBytes=$free;totalBytes=$total}
    })
    @{drives=$drives}
}
function Get-StartupItems {
    $items = @()
    
    # ── Clés Run du registre (avec statut depuis StartupApproved) ──
    $regPairs = @(
        @{run="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ap="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"},
        @{run="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ap="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"},
        @{run="HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; ap="HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"}
    )
    foreach($pair in $regPairs){
        $rp = $pair.run; $ap = $pair.ap
        if(Test-Path $rp){
            $props = Get-ItemProperty $rp -EA SilentlyContinue
            if($props){
                $props.PSObject.Properties | Where-Object{$_.Name -notmatch "^PS"} | ForEach-Object{
                    $name = $_.Name
                    $enabled = $true
                    if(Test-Path $ap){
                        try{
                            $apVal = (Get-ItemProperty -Path $ap -Name $name -EA Stop).$name
                            if($apVal -and $apVal.Length -ge 1){ $enabled = ($apVal[0] -ne 3) }
                        }catch{}
                    }
                    $items += @{name=$name;command=[string]$_.Value;regPath=$rp;enabled=$enabled}
                }
            }
        }
    }
    
    # ── Éléments désactivés dans StartupApproved mais plus dans Run ──
    # (Task Manager les montre quand même)
    $apKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"
    )
    $existingNames = $items | ForEach-Object{$_.name}
    foreach($apKey in $apKeys){
        if(Test-Path $apKey){
            $apProps = Get-ItemProperty $apKey -EA SilentlyContinue
            if($apProps){
                $apProps.PSObject.Properties | Where-Object{$_.Name -notmatch "^PS"} | ForEach-Object{
                    $name = $_.Name
                    if($existingNames -notcontains $name){
                        $apVal = $_.Value
                        $enabled = $true
                        if($apVal -and $apVal.Length -ge 1){ $enabled = ($apVal[0] -ne 3) }
                        $items += @{name=$name;command="";regPath=$apKey;enabled=$enabled}
                    }
                }
            }
        }
    }
    
    # ── Dossier Startup utilisateur ──
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if(Test-Path $startupFolder){
        Get-ChildItem $startupFolder -Filter "*.lnk" -EA SilentlyContinue | ForEach-Object{
            $lnkName = $_.BaseName
            if(($items | ForEach-Object{$_.name}) -notcontains $lnkName){
                $items += @{name=$lnkName;command=$_.FullName;regPath="Startup Folder";enabled=$true}
            }
        }
    }
    
    @($items)
}

function Toggle-StartupItem($name,$regPath,$enable){
    try{
        # Déterminer la bonne clé StartupApproved selon regPath
        $ap = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
        if($regPath -match "HKLM" -and $regPath -match "WOW6432"){
            $ap = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
        }elseif($regPath -match "HKLM"){
            $ap = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
        }
        
        if(-not(Test-Path $ap)){New-Item $ap -Force -EA SilentlyContinue | Out-Null}
        
        # byte[0]: 2 = activé, 3 = désactivé (convention Windows Task Manager)
        $val = if($enable){[byte[]](2,0,0,0,0,0,0,0,0,0,0,0)}else{[byte[]](3,0,0,0,0,0,0,0,0,0,0,0)}
        Set-ItemProperty -Path $ap -Name $name -Value $val -Type Binary -Force -EA SilentlyContinue
        
        @{success=$true;ok=$true;msg=if($enable){"Activé au démarrage"}else{"Désactivé du démarrage"}}
    }catch{
        @{success=$false;ok=$false;msg=$_.Exception.Message}
    }
}

function Get-Apps {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $apps = [System.Collections.ArrayList]::new()
    $seen = @{}
    foreach($p in $paths){
        if(-not(Test-Path $p -EA SilentlyContinue)){continue}
        try {
            Get-ChildItem $p -EA SilentlyContinue | ForEach-Object {
                try {
                    $pr = Get-ItemProperty $_.PSPath -EA SilentlyContinue
                    if(-not $pr -or -not $pr.DisplayName){ return }
                    $name = [string]$pr.DisplayName
                    if(-not $name -or $seen[$name]){ return }
                    $uns = [string]$pr.UninstallString
                    if(-not $uns){ return }
                    $seen[$name] = $true
                    $szBytes = if($pr.EstimatedSize){ [long]$pr.EstimatedSize * 1024 } else { [long]0 }
                    $szStr   = if($szBytes -gt 0){ Format-Size $szBytes } else { "?" }
                    [void]$apps.Add(@{
                        name            = $name
                        version         = [string]$pr.DisplayVersion
                        publisher       = [string]$pr.Publisher
                        size            = $szStr
                        uninstallString = $uns
                    })
                } catch {}
            }
        } catch {}
    }
    @($apps | Sort-Object { [string]$_.name })
}
function Invoke-Uninstall($uns){
    try{
        if($uns -match "(?i)msiexec"){
            $g = ""; if($uns -match "(\{[0-9A-Fa-f-]{36}\})"){$g=$matches[1]}
            if($g){Start-Process msiexec -ArgumentList "/x $g /quiet /norestart" -Wait -EA SilentlyContinue}
            else{Start-Process msiexec -ArgumentList (($uns -replace "(?i)msiexec\.exe\s*","").Trim()) -Wait -EA SilentlyContinue}
        } else {Start-Process $uns -Wait -EA SilentlyContinue}
        @{success=$true}
    }catch{@{success=$false;error=$_.Exception.Message}}
}
function ForceRemove-App($name,$uns){
    try{
        Get-Process -EA SilentlyContinue | Where-Object{$_.ProcessName -match [regex]::Escape(($name -split " ")[0])} | Stop-Process -Force -EA SilentlyContinue
        if($uns){Invoke-Uninstall $uns | Out-Null}
        @("$env:ProgramFiles\$name","${env:ProgramFiles(x86)}\$name","$env:LOCALAPPDATA\$name","$env:APPDATA\$name") | ForEach-Object {
            if(Test-Path -LiteralPath $_){Grant-OptiAdminAccess $_ $true;Remove-Item -LiteralPath $_ -Force -Recurse -EA SilentlyContinue}
        }
        @{success=$true}
    }catch{@{success=$false;error=$_.Exception.Message}}
}
function Get-BigFiles {
    $files = @()
    try{
        Get-ChildItem "C:\" -Recurse -File -Force -EA SilentlyContinue | Where-Object{$_.Length -gt 50MB} | Sort-Object Length -Descending | Select-Object -First 100 | ForEach-Object {
            $files += @{path=$_.FullName;name=$_.Name;dir=$_.DirectoryName;size=$_.Length;sizeStr=(Format-Size $_.Length)}
        }
    }catch{}
    @($files)
}
function Find-Duplicates {
    $files = Get-ChildItem "$env:USERPROFILE" -Recurse -File -Force -EA SilentlyContinue | Where-Object{$_.Length -gt 500KB}
    $result = @()
    $bySize = $files | Group-Object Length | Where-Object{$_.Count -gt 1}
    foreach($g in $bySize){
        $hashed = $g.Group | ForEach-Object{$h=(Get-FileHash $_.FullName -Algorithm MD5 -EA SilentlyContinue).Hash;if($h){@{f=$_;h=$h}}}
        $byHash = $hashed | Where-Object{$_} | Group-Object h | Where-Object{$_.Count -gt 1}
        foreach($bh in $byHash){
            $result += @{hash=$bh.Name;count=$bh.Count;size=$bh.Group[0].f.Length;sizeStr=(Format-Size $bh.Group[0].f.Length);waste=(Format-Size($bh.Group[0].f.Length*($bh.Count-1)));files=@($bh.Group|ForEach-Object{@{path=$_.f.FullName;name=$_.f.Name}})}
        }
    }
    @($result)
}
function Get-SysInfo {
    try{
        $os   = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
        $cpu  = Get-CimInstance Win32_Processor -EA SilentlyContinue | Select-Object -First 1
        $gpu  = Get-CimInstance Win32_VideoController -EA SilentlyContinue | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS -EA SilentlyContinue
        $cs   = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
        $disk = Get-CimInstance Win32_DiskDrive -EA SilentlyContinue | Select-Object -First 1
        $up   = if($os -and $os.LastBootUpTime){((Get-Date)-$os.LastBootUpTime)}else{[timespan]0}
        $ip   = (Get-NetIPAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object{$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        @{
            os=if($os){$os.Caption}else{"N/A"};build=if($os){$os.BuildNumber}else{"?"};arch=if($os){$os.OSArchitecture}else{"?"}
            cpu=if($cpu){$cpu.Name}else{"N/A"};cpuCores=if($cpu){$cpu.NumberOfCores}else{0}
            gpu=if($gpu){$gpu.Caption}else{"N/A"};ram=if($cs){Format-Size $cs.TotalPhysicalMemory}else{"N/A"}
            diskModel=if($disk){$disk.Model}else{"N/A"};diskSize=if($disk){Format-Size $disk.Size}else{"N/A"}
            manufacturer=if($cs){$cs.Manufacturer}else{"N/A"};model=if($cs){$cs.Model}else{"N/A"}
            bios=if($bios){$bios.SMBIOSBIOSVersion}else{"N/A"}
            uptime="$([math]::Floor($up.TotalHours))h $($up.Minutes)m"
            ip=if($ip){$ip}else{"N/A"};hostname=$env:COMPUTERNAME;user=$env:USERNAME
        }
    }catch{@{error="Erreur lecture systeme"}}
}
function Get-OptiExeFromCommand($cmd){
    $c = ([string]$cmd).Trim()
    if(-not $c){ return $null }
    $c = [Environment]::ExpandEnvironmentVariables($c)
    if($c -match '^\s*"([^"]+)"'){ return $matches[1] }
    if($c -match '^\s*(.+?\.(exe|cmd|bat))(\s|$)'){ return $matches[1] }
    $null
}
function ConvertTo-OptiNativeRegPath($k){
    $x = ([string]$k) -replace '^(?i)Microsoft\.PowerShell\.Core\\Registry::',''
    $x = $x -replace '^(?i)HKLM:\\?','HKEY_LOCAL_MACHINE\' -replace '^(?i)HKCU:\\?','HKEY_CURRENT_USER\'
    $x.TrimEnd('\')
}
function Scan-Registry {
    # Ne signale QUE les logiciels fantomes : nom affiche present, mais
    # desinstalleur ET dossier d'installation disparus du disque.
    # Les cles sans nom (anciennement "(entree vide) / Nom manquant") sont des
    # entrees techniques normales de Windows : elles ne sont plus signalees.
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $skipExe = '(?i)\\(msiexec|rundll32|cmd|powershell|pwsh|wscript|cscript|explorer|regsvr32|dllhost)\.exe$'
    $invalid = [System.Collections.ArrayList]::new()
    $scanned = 0
    foreach($p in $paths){
        if(-not(Test-Path $p -EA SilentlyContinue)){ continue }
        foreach($key in @(Get-ChildItem $p -EA SilentlyContinue)){
            $scanned++
            try{
                $pr = Get-ItemProperty -LiteralPath $key.PSPath -EA SilentlyContinue
                if(-not $pr){ continue }
                $n = ([string]$pr.DisplayName).Trim()
                if(-not $n){ continue }
                if($pr.SystemComponent -eq 1){ continue }
                if($n -match '^(KB\d+|Update for|Security Update|Hotfix|Mise a jour)'){ continue }
                $cmd = [string]$pr.UninstallString
                if(-not $cmd){ $cmd = [string]$pr.QuietUninstallString }
                if(-not $cmd){ continue }
                if($cmd -match '(?i)msiexec'){ continue }
                $exe = Get-OptiExeFromCommand $cmd
                if(-not $exe){ continue }
                try{ if(-not [IO.Path]::IsPathRooted($exe)){ continue } }catch{ continue }
                if($exe -match $skipExe -or $exe -match '(?i)\\WindowsApps\\'){ continue }
                if(Test-Path -LiteralPath $exe -EA SilentlyContinue){ continue }
                $loc = ([string]$pr.InstallLocation).Trim().Trim('"')
                if($loc -and (Test-Path -LiteralPath $loc -EA SilentlyContinue)){ continue }
                [void]$invalid.Add(@{key=[string]$key.PSPath;name=$n;issue="Logiciel absent";detail="Desinstalleur introuvable : $exe"})
            } catch { continue }
        }
    }
    @{count=$invalid.Count;items=@($invalid);scanned=$scanned}
}
function Clean-RegistryKeys($keys){
    $allowed = '^(?i)HKEY_(LOCAL_MACHINE|CURRENT_USER)\\SOFTWARE\\(WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\Uninstall\\[^\\]+$'
    $bdir = "$env:LOCALAPPDATA\OptiPC\RegBackup"
    try{ if(-not(Test-Path $bdir)){ [System.IO.Directory]::CreateDirectory($bdir) | Out-Null } }catch{}
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $ok = 0; $failed = 0; $i = 0
    foreach($k in @($keys)){
        $nat = ConvertTo-OptiNativeRegPath $k
        # Securite : on ne supprime jamais rien en dehors des cles "Uninstall"
        if($nat -notmatch $allowed){ $failed++; continue }
        $psp = "Registry::$nat"
        if(-not(Test-Path -LiteralPath $psp)){ $ok++; continue }
        $i++
        $bf = Join-Path $bdir ("{0}_{1:D3}.reg" -f $stamp, $i)
        $saved = $false
        try{ reg.exe export "$nat" "$bf" /y 2>&1 | Out-Null; $saved = (Test-Path -LiteralPath $bf) }catch{}
        if(-not $saved){ $failed++; continue }   # pas de sauvegarde = pas de suppression
        try{ Remove-Item -LiteralPath $psp -Recurse -Force -EA Stop }catch{}
        if(Test-Path -LiteralPath $psp){ $failed++ } else { $ok++ }
    }
    @{cleaned=$ok;failed=$failed;success=($failed -eq 0);backupDir=$bdir}
}
function Get-ServicesStatus {
    $svcs = @(
        @{name="DiagTrack";label="Telemetrie Windows";desc="Envoie vos donnees a Microsoft"}
        @{name="dmwappushservice";label="Collecte Microsoft";desc="Remontee d informations complementaire"}
        @{name="XblAuthManager";label="Xbox (Connexion)";desc="Inutile si vous ne jouez pas"}
        @{name="XblGameSave";label="Xbox (Sauvegardes)";desc="Sauvegarde cloud Xbox"}
        @{name="XboxNetApiSvc";label="Xbox (Reseau)";desc="Fonctions reseau Xbox"}
        @{name="Fax";label="Service Fax";desc="Envoi et reception de fax"}
        @{name="RemoteRegistry";label="Acces registre distant";desc="Acces externe a votre registre"}
        @{name="SysMain";label="Prechauffage apps";desc="Pre-charge les apps en memoire"}
        @{name="WSearch";label="Recherche Windows";desc="Indexe vos fichiers"}
    )
    foreach($s in $svcs){
        $svc = Get-Service $s.name -EA SilentlyContinue
        $s.status  = if($svc){$svc.Status.ToString()}else{"Absent"}
        $s.enabled = $svc -and $svc.Status -eq "Running"
        $s.present = $null -ne $svc
    }
    @($svcs)
}
function Toggle-ServiceItem($name,$enable){
    try{
        if($enable){Set-Service $name -StartupType Automatic -EA SilentlyContinue;Start-Service $name -EA SilentlyContinue}
        else{Stop-Service $name -Force -EA SilentlyContinue;Set-Service $name -StartupType Disabled -EA SilentlyContinue}
        @{success=$true}
    }catch{@{success=$false;error=$_.Exception.Message}}
}
function Get-PowerPlanCatalog {
    @(
        @{guid='a1841308-3541-4fab-bc81-f71556f20b4a';icon='battery';name='Economie d energie';desc='Autonomie maximale, ventilateur plus calme'}
        @{guid='381b4222-f694-41f0-9685-ff5bb260df2e';icon='balance';name='Equilibre';desc='Le bon compromis au quotidien (recommande)'}
        @{guid='8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c';icon='rocket';name='Performances elevees';desc='Le PC donne tout, consomme un peu plus'}
    )
}
function Get-ActivePlanGuid {
    $g = ''
    try {
        $cur = (powercfg /getactivescheme 2>&1) -join ' '
        if($cur -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'){ $g = $matches[1].ToLower() }
    } catch {}
    $g
}
function Get-PowerPlans {
    # On lit la liste reelle des modes installes : sur beaucoup de PC recents
    # (Modern Standby, portables OEM) un ou plusieurs modes standards sont absents.
    # Ils seront recrees a la volee au moment du clic.
    $installed = @{}
    try {
        foreach($l in @(powercfg /list 2>&1)){
            $t = [string]$l
            if($t -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'){
                $g = $matches[1].ToLower()
                $nm = ''
                if($t -match '\(([^)]*)\)'){ $nm = $matches[1].Trim() }
                $installed[$g] = $nm
            }
        }
    } catch {}

    $active = Get-ActivePlanGuid
    $plans = @()
    foreach($k in (Get-PowerPlanCatalog)){
        $plans += @{
            guid      = $k.guid
            icon      = $k.icon
            name      = $k.name
            desc      = $k.desc
            installed = [bool]$installed.ContainsKey($k.guid)
            active    = ($active -eq $k.guid)
        }
    }
    $customName = ''
    if($active -and (@($plans | Where-Object { $_.active }).Count -eq 0)){
        if($installed.ContainsKey($active)){ $customName = $installed[$active] }
        if(-not $customName){ $customName = 'Mode personnalise' }
    }
    @{ plans=@($plans); currentGuid=$active; customName=$customName; ok=$true }
}
function Set-ActivePowerPlan($guid){
    if(-not $guid){ return @{success=$false;error='Mode d alimentation inconnu'} }
    $g = ([string]$guid).Trim().ToLower()
    if($g -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){
        return @{success=$false;error='Mode d alimentation inconnu'}
    }
    # 1) Le mode existe-t-il sur ce PC ?
    $exists = $false
    try { $exists = (((powercfg /list 2>&1) | Out-String).ToLower() -like "*$g*") } catch {}
    # 2) Sinon on le recree depuis le modele Windows correspondant
    if(-not $exists){
        try { powercfg -duplicatescheme $g 2>&1 | Out-Null } catch {}
    }
    $msg = ''
    try { $msg = ((powercfg /setactive $g 2>&1) | Out-String).Trim() } catch { $msg = $_.Exception.Message }
    Start-Sleep -Milliseconds 250
    $now = Get-ActivePlanGuid
    if($now -eq $g){
        @{success=$true;currentGuid=$now}
    } else {
        $err = if($msg){ $msg } else { 'Windows a refuse le changement de mode (strategie imposee par le fabricant ou par l entreprise).' }
        @{success=$false;currentGuid=$now;error=$err}
    }
}
function Invoke-SystemRepair($action){
    $out = switch($action){
        "search" {
            Restart-Service WSearch -Force -EA SilentlyContinue
            "Recherche Windows redemarre."
        }
        "sfc"    {
            sfc /scannow 2>&1|Out-Null
            "SFC termine. Voir C:\Windows\Logs\CBS\CBS.log"
        }
        "dism"   {
            DISM /Online /Cleanup-Image /RestoreHealth 2>&1|Out-Null
            "DISM termine. Image Windows reparee."
        }
        "winsxs_analyze" {
            $out = (DISM /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String)
            $rec = "inconnue"
            if($out -match '(?im)^\s*(Reclaimable Packages|Packages r.cup.rables)\s*:\s*(\d+)'){ $rec = $matches[2] }
            $sz = ""
            if($out -match '(?im)^\s*(Actual Size of Component Store|Taille r.elle du magasin de composants)\s*:\s*(.+)$'){ $sz = ($matches[2]).Trim() }
            $adv = ""
            if($out -match '(?im)(Component Store Cleanup Recommended|Nettoyage du magasin de composants recommand.)\s*:\s*(Yes|Oui)'){ $adv = " - Nettoyage recommande." }
            "Magasin de composants : $sz. Paquets recuperables : $rec.$adv"
        }
        "winsxs_clean" {
            DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-Null
            "Anciennes mises a jour Windows supprimees. Vous ne pourrez plus desinstaller les mises a jour deja installees."
        }
        "wsreset"{
            # Arreter le Store
            Stop-Process -Name WinStore.App -Force -EA SilentlyContinue
            Start-Sleep -Milliseconds 800
            # Vider le cache du Store sans ouvrir la fenetre
            $cacheP = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"
            if(Test-Path $cacheP){ Get-ChildItem $cacheP -Force -EA SilentlyContinue | Remove-Item -Force -Recurse -EA SilentlyContinue }
            # Reinitialiser les donnees du Store
            $dataP = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\cache"
            if(Test-Path $dataP){ Get-ChildItem $dataP -Force -EA SilentlyContinue | Remove-Item -Force -Recurse -EA SilentlyContinue }
            # wsreset en arriere-plan silencieux
            Start-Process wsreset.exe -WindowStyle Hidden
            "Cache du Microsoft Store vide avec succes."
        }
        default  {"Action inconnue"}
    }
    @{output=$out;success=$true}
}
function Set-VisualFX($mode){
    $reg  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    $adv  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $desk = "HKCU:\Control Panel\Desktop"
    if($mode -eq "reduce"){
        if(Test-Path $reg){Set-ItemProperty $reg "VisualFXSetting" 2 -EA SilentlyContinue}
        Set-ItemProperty $desk "DragFullWindows" "0" -EA SilentlyContinue
        Set-ItemProperty $desk "MenuShowDelay" "0" -EA SilentlyContinue
        Set-ItemProperty $adv "TaskbarAnimations" 0 -EA SilentlyContinue
    } else {
        if(Test-Path $reg){Set-ItemProperty $reg "VisualFXSetting" 0 -EA SilentlyContinue}
        Set-ItemProperty $desk "DragFullWindows" "1" -EA SilentlyContinue
        Set-ItemProperty $desk "MenuShowDelay" "400" -EA SilentlyContinue
        Set-ItemProperty $adv "TaskbarAnimations" 1 -EA SilentlyContinue
    }
    @{success=$true}
}
function Set-PagefileConfig($mode){
    try{
        $cs = Get-WmiObject Win32_ComputerSystem -EA SilentlyContinue
        if(-not $cs){return @{success=$false;error="WMI inaccessible"}}
        switch($mode){
            "auto"{$cs.AutomaticManagedPagefile=$true;$cs.Put()|Out-Null}
            "2gb" {$cs.AutomaticManagedPagefile=$false;$cs.Put()|Out-Null;$pf=Get-WmiObject Win32_PageFileSetting -EA SilentlyContinue;if(-not$pf){$pf=([wmiclass]"Win32_PageFileSetting").CreateInstance();$pf.Name="C:\pagefile.sys"};$pf.InitialSize=2048;$pf.MaximumSize=4096;$pf.Put()|Out-Null}
            "4gb" {$cs.AutomaticManagedPagefile=$false;$cs.Put()|Out-Null;$pf=Get-WmiObject Win32_PageFileSetting -EA SilentlyContinue;if(-not$pf){$pf=([wmiclass]"Win32_PageFileSetting").CreateInstance();$pf.Name="C:\pagefile.sys"};$pf.InitialSize=4096;$pf.MaximumSize=8192;$pf.Put()|Out-Null}
        }
        @{success=$true;note="Redemarrage requis pour appliquer."}
    }catch{@{success=$false;error=$_.Exception.Message}}
}
function Invoke-SecureDelete($path,$passes){
    if(-not $path -or -not(Test-Path $path)){return @{success=$false;error="Chemin introuvable"}}
    $log = @()
    $appName = [IO.Path]::GetFileNameWithoutExtension($path)
    $isDir = Test-Path $path -PathType Container

    # ETAPE 1 : Tuer tous les processus lies au fichier / dossier
    $killed = 0
    Get-Process -EA SilentlyContinue | Where-Object {
        $pn = $_.ProcessName
        try {
            $pn -match [regex]::Escape($appName) -or
            ($_.MainModule.FileName -like "*$appName*")
        } catch { $pn -match [regex]::Escape($appName) }
    } | ForEach-Object {
        try { $_.Kill(); $killed++ } catch {}
    }
    if($killed -gt 0){ $log += "$killed processus stoppe(s)" }
    Start-Sleep -Milliseconds 500

    # ETAPE 2 : Arreter et supprimer les services lies
    $svcStopped = 0
    Get-Service -EA SilentlyContinue | Where-Object {
        $_.DisplayName -match [regex]::Escape($appName) -or
        $_.ServiceName -match [regex]::Escape($appName)
    } | ForEach-Object {
        try {
            Stop-Service $_.ServiceName -Force -EA SilentlyContinue
            $svcPath = (Get-WmiObject Win32_Service -Filter "Name='$($_.ServiceName)'" -EA SilentlyContinue).PathName
            if($svcPath -like "*$appName*" -or $svcPath -like "*$path*"){
                sc.exe delete $_.ServiceName 2>&1 | Out-Null
            }
            $svcStopped++
        } catch {}
    }
    if($svcStopped -gt 0){ $log += "$svcStopped service(s) arrete(s)" }

    # ETAPE 3 : Nettoyer les cles de registre qui referent au chemin
    $regCleaned = 0
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SYSTEM\CurrentControlSet\Services"
    )
    foreach($rp in $regPaths){
        if(-not(Test-Path $rp)){continue}
        Get-ChildItem $rp -EA SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty $_.PSPath -EA SilentlyContinue
            $refersToPath = ($props | Select-Object -ExpandProperty * -EA SilentlyContinue | Where-Object { $_ -is [string] -and ($_ -like "*$appName*" -or $_ -like "*$([IO.Path]::GetDirectoryName($path))*") })
            if($refersToPath){
                try { Remove-Item $_.PSPath -Recurse -Force -EA SilentlyContinue; $regCleaned++ } catch {}
            }
        }
    }
    if($regCleaned -gt 0){ $log += "$regCleaned cle(s) registre supprimee(s)" }

    # ETAPE 4 : Prendre possession totale (admin)
    Grant-OptiAdminAccess $path $isDir
    $log += "Prise de possession effectuee"

    # ETAPE 5 : Supprimer attributs protection
    try {
        if($isDir){
            attrib -R -H -S "$path\*" /S /D 2>&1 | Out-Null
        } else {
            attrib -R -H -S "$path" 2>&1 | Out-Null
        }
    } catch {}

    # ETAPE 6 : Supprimer par force (3 methodes en cascade)
    $deleted = $false
    try {
        Remove-Item $path -Force -Recurse -EA Stop
        $deleted = $true
    } catch {}

    if(-not $deleted){
        try {
            if($isDir){ cmd /c "rd /s /q `"$path`"" 2>&1 | Out-Null }
            else { cmd /c "del /f /s /q `"$path`"" 2>&1 | Out-Null }
            if(-not(Test-Path $path)){ $deleted = $true }
        } catch {}
    }

    if(-not $deleted){
        # Planifier suppression au prochain redemarrage
        try {
            $nul = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\Session Manager", $true)
            $existing = $nul.GetValue("PendingFileRenameOperations")
            $newEntry = [string[]]("\??\$path", "")
            if($existing){ $nul.SetValue("PendingFileRenameOperations", ($existing + $newEntry), "MultiString") }
            else { $nul.SetValue("PendingFileRenameOperations", $newEntry, "MultiString") }
            $log += "Suppression planifiee au prochain redemarrage"
            return @{success=$true;pending=$true;log=$log;message="Supprime au redemarrage"}
        } catch {}
    }

    if($deleted){ $log += "Suppression reussie" }
    @{success=$deleted;log=$log;message=if($deleted){"Supprime avec succes"}else{"Echec - redemarrez et reessayez"}}
}
function Get-ChromeData {
    $paths = @(Get-OptiBrowserCachePaths 'chrome')
    $total = [long]0
    foreach($p in $paths){ if(Test-Path $p){ $total += Get-FolderSize $p } }
    @{size=$total;sizeStr=(Format-Size $total);paths=$paths}
}
function Get-FirefoxData {
    $total = [long]0; $paths = @(Get-OptiBrowserCachePaths 'firefox')
    foreach($p in $paths){ $total += Get-FolderSize $p }
    @{size=$total;sizeStr=(Format-Size $total);paths=$paths}
}
function Get-OperaData {
    $paths = @(Get-OptiBrowserCachePaths 'opera')
    $total = [long]0
    foreach($p in $paths){ if(Test-Path $p){ $total += Get-FolderSize $p } }
    @{size=$total;sizeStr=(Format-Size $total);paths=$paths}
}
function Get-BrowserSizes {
    $chrome = Get-ChromeData
    $edgeSz = [long]0; foreach($ep in @(Get-OptiBrowserCachePaths 'edge')){ $edgeSz += Get-FolderSize $ep }
    $edge = @{sizeStr=(Format-Size $edgeSz)}
    $firefox = Get-FirefoxData; $opera = Get-OperaData
    @{chrome=$chrome;edge=$edge;firefox=$firefox;opera=$opera}
}
function Clear-BrowserCache($browsers) {
    $cleaned = [long]0
    if($browsers -contains "chrome"){
        $d = Get-ChromeData
        foreach($p in $d.paths){ if(Test-Path $p){ $cleaned += Get-FolderSize $p; Get-ChildItem $p -Force -EA SilentlyContinue | Remove-Item -Force -Recurse -EA SilentlyContinue } }
    }
    if($browsers -contains "edge"){
        foreach($p in @(Get-OptiBrowserCachePaths 'edge')){ if(Test-Path $p){ $cleaned += Get-FolderSize $p; Get-ChildItem $p -Force -EA SilentlyContinue | Remove-Item -Force -Recurse -EA SilentlyContinue } }
    }
    if($browsers -contains "firefox"){
        $d = Get-FirefoxData
        foreach($p in $d.paths){ if(Test-Path $p){ $cleaned += Get-FolderSize $p; Get-ChildItem $p -Force -EA SilentlyContinue | Remove-Item -Force -Recurse -EA SilentlyContinue } }
    }
    if($browsers -contains "opera"){
        $d = Get-OperaData
        foreach($p in $d.paths){ if(Test-Path $p){ $cleaned += Get-FolderSize $p; Get-ChildItem $p -Force -EA SilentlyContinue | Remove-Item -Force -Recurse -EA SilentlyContinue } }
    }
    @{cleaned=(Format-Size $cleaned);cleanedBytes=$cleaned;success=$true}
}
function Register-RebootDelete($p) {
    try {
        $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            "SYSTEM\CurrentControlSet\Control\Session Manager", $true)
        if($regKey) {
            $existing = $regKey.GetValue("PendingFileRenameOperations")
            $ntPath = "\??\$p"
            $newEntries = [string[]]($ntPath, "")
            if($existing -and $existing.Count -gt 0) {
                $regKey.SetValue("PendingFileRenameOperations",
                    ($existing + $newEntries), "MultiString")
            } else {
                $regKey.SetValue("PendingFileRenameOperations",
                    $newEntries, "MultiString")
            }
            $regKey.Close()
            return $true
        }
    } catch {}
    return $false
}
function Get-OptiYesLetter {
    # takeown /D attend la lettre de la langue de Windows : O en francais, Y en anglais.
    # Avec "Y" sur un Windows francais, takeown refuse la commande.
    try{
        switch([System.Globalization.CultureInfo]::InstalledUICulture.TwoLetterISOLanguageName){
            'fr' {'O'} 'es' {'S'} 'it' {'S'} 'pt' {'S'} 'de' {'J'} 'nl' {'J'} default {'Y'}
        }
    }catch{ 'Y' }
}
function Invoke-OptiCmd([string]$exe, [string]$arguments, [int]$timeoutMs = 20000){
    # Lance un outil Windows (takeown, icacls, attrib, sc, cmd) SANS jamais
    # bloquer OptiPC : au-dela du delai, l'outil est arrete. Avant, un seul
    # outil qui attendait une reponse suffisait a figer la suppression.
    try{
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = $arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $pr = [System.Diagnostics.Process]::Start($psi)
        try{ $pr.StandardInput.Close() }catch{}
        $o = $pr.StandardOutput.ReadToEndAsync(); $e = $pr.StandardError.ReadToEndAsync()
        if(-not $pr.WaitForExit($timeoutMs)){
            try{ $pr.Kill() }catch{}
            return -1
        }
        return $pr.ExitCode
    }catch{ return -2 }
}

function Grant-OptiAdminAccess($path, $recurse){
    # Groupe Administrateurs designe par son SID : "Administrators" n'existe
    # pas sur un Windows francais (il s'appelle "Administrateurs").
    $yes = Get-OptiYesLetter
    $t = if($recurse){ 120000 } else { 15000 }
    if($recurse){ [void](Invoke-OptiCmd 'takeown.exe' "/f `"$path`" /a /r /d $yes" $t) }
    else        { [void](Invoke-OptiCmd 'takeown.exe' "/f `"$path`" /a" $t) }
    if($recurse){ [void](Invoke-OptiCmd 'icacls.exe' "`"$path`" /grant *S-1-5-32-544:F /t /c /q" $t) }
    else        { [void](Invoke-OptiCmd 'icacls.exe' "`"$path`" /grant *S-1-5-32-544:F /c /q" $t) }
    [void](Invoke-OptiCmd 'attrib.exe' "-R -S -H `"$path`"" 10000)
    if($recurse){ [void](Invoke-OptiCmd 'attrib.exe' "-R -S -H `"$path\*`" /S /D" $t) }
}
function Invoke-ForceDelete($path) {
    $path = ([string]$path).Trim().Trim('"').Trim()
    if(-not $path){ return @{success=$false;error="Aucun chemin indique"} }
    try{ $path = [IO.Path]::GetFullPath($path) }catch{ return @{success=$false;error="Chemin invalide : $path"} }
    if($path.Length -gt 3){ $path = $path.TrimEnd('\') }
    # -LiteralPath partout : un nom contenant [ ] (ex. "photo [1].jpg") etait introuvable
    if(-not(Test-Path -LiteralPath $path)){ return @{success=$false;error="Chemin introuvable : $path"} }
    $low = $path.ToLower()
    $sysRoot = ([string]$env:SystemRoot).TrimEnd('\').ToLower()
    $underWin = $sysRoot -and ($low -eq $sysRoot -or $low.StartsWith($sysRoot + '\'))
    if($underWin -or -not (Test-SafeToDelete $path) -or (Test-UnderSelfDir $path)){
        return @{success=$false;error="Emplacement protege : suppression refusee pour ne pas endommager Windows"}
    }
    $item  = Get-Item -LiteralPath $path -Force -EA SilentlyContinue
    $isDir = [bool]($item -and $item.PSIsContainer)
    $log   = "$env:TEMP\optipc_force_log.txt"
    try{[IO.File]::WriteAllText($log,"",[Text.Encoding]::UTF8)}catch{}
    $WL   = {param($m)try{[IO.File]::AppendAllText($log,(Get-Date -F 'HH:mm:ss')+" $m`n",[Text.Encoding]::UTF8)}catch{}}
    $gone = { -not (Test-Path -LiteralPath $path) }

    $sz = 0; $nf = 0
    try{
        if($isDir){ $sz = Get-FolderSize $path }
        elseif($item){ $sz = $item.Length }
    }catch{}
    & $WL "Cible : $path"
    & $WL ("Type : " + $(if($isDir){"dossier"}else{"fichier"}) + " - " + (Format-Size $sz))
    # Etape 0 (16/09/2026) : essai direct. Une photo, un document... partent
    # en une fraction de seconde : inutile de sortir l'artillerie lourde
    # (analyse de tous les processus et services) qui gelait les PC lents.
    & $WL "Etape 1/6 - Suppression directe..."
    try{
        if($item){ try{ $item.Attributes = 'Normal' }catch{} }
        Remove-Item -LiteralPath $path -Force -Recurse -EA Stop
    }catch{ & $WL "Element bloque : $($_.Exception.Message)" }
    if(& $gone){ & $WL "OK - supprime"; return @{success=$true;message="Supprime avec succes"} }

    # Seuls un programme, une bibliotheque ou un dossier peuvent etre
    # verrouilles par un processus ou un service en cours d'execution.
    $ext = ([IO.Path]::GetExtension($path)).ToLower()
    $canRun = $isDir -or (@('.exe','.dll','.sys','.com','.scr','.ocx','.cpl','.msi','.bat','.cmd','.ps1','.vbs','.jar') -contains $ext)

    # Etape 1 : arreter UNIQUEMENT ce qui s'execute depuis ce fichier / dossier.
    # (L'ancienne version tuait tout processus dont le NOM contenait le nom du
    # fichier : supprimer "s.txt" pouvait tuer csrss, svchost... => ecran bleu.)
    $prefix = $low + '\'
    if($canRun){ & $WL "Etape 2/6 - Recherche des programmes et services qui utilisent l'element..." }
    else { & $WL "Etape 2/6 - Aucun programme ne peut utiliser ce type de fichier : etape ignoree" }
    if($canRun){ try{
        foreach($p in (Get-Process -EA SilentlyContinue)){
            if($p.Id -eq $PID){ continue }
            $pp = $null; try{ $pp = [string]$p.Path }catch{}
            if(-not $pp){ continue }
            $pl = $pp.ToLower()
            if(($isDir -and $pl.StartsWith($prefix)) -or (-not $isDir -and $pl -eq $low)){
                [void](Invoke-OptiCmd 'taskkill.exe' "/F /T /PID $($p.Id)" 10000)
                & $WL "Process tue : $($p.ProcessName)"
            }
        }
    }catch{} }
    if($canRun){ try{
        foreach($sv in (Get-CimInstance Win32_Service -OperationTimeoutSec 15 -EA SilentlyContinue)){
            $sp = (([string]$sv.PathName) -replace '"','').ToLower()
            if(-not $sp){ continue }
            if(($isDir -and $sp.StartsWith($prefix)) -or (-not $isDir -and $sp.StartsWith($low))){
                # sc.exe n'attend pas : Stop-Service pouvait bloquer indefiniment
                [void](Invoke-OptiCmd 'sc.exe' "stop `"$($sv.Name)`"" 10000)
                [void](Invoke-OptiCmd 'sc.exe' "config `"$($sv.Name)`" start= disabled" 10000)
                & $WL "Service arrete : $($sv.DisplayName)"
            }
        }
    }catch{}
    Start-Sleep -Milliseconds 300 }

    # Etape 2 : droits
    & $WL "Etape 3/6 - Prise de possession (droits administrateur)..."
    Grant-OptiAdminAccess $path $isDir

    # Etape 3 : PowerShell
    & $WL "Etape 4/6 - Suppression apres prise de possession..."
    try{ Remove-Item -LiteralPath $path -Force -Recurse -EA Stop }catch{}
    if(& $gone){ & $WL "OK - supprime"; return @{success=$true;message="Supprime avec succes"} }

    # Etape 4 : CMD (chemin normal puis chemin long \\?\)
    & $WL "Toujours present - Etape 5/6 - Suppression par l'invite de commandes..."
    $lp = if($path.StartsWith('\\')){ $path } else { "\\?\$path" }
    foreach($cp in @($path, $lp)){
        try{
            if($isDir){ [void](Invoke-OptiCmd 'cmd.exe' "/c rd /s /q `"$cp`"" 120000) }
            else      { [void](Invoke-OptiCmd 'cmd.exe' "/c del /f /q /a `"$cp`"" 15000) }
        }catch{}
        if(& $gone){ & $WL "OK - via CMD"; return @{success=$true;message="Supprime via CMD"} }
    }

    # Etape 5 : Robocopy (dossiers)
    if($isDir){
        & $WL "Robocopy : vidage du dossier..."
        try{
            $tmp = "$env:TEMP\optipc_e_$(Get-Random)"
            [System.IO.Directory]::CreateDirectory($tmp) | Out-Null
            [void](Invoke-OptiCmd 'robocopy.exe' "`"$tmp`" `"$path`" /MIR /NFL /NDL /NJH /NJS /R:0 /W:0" 180000)
            Remove-Item -LiteralPath $tmp -Force -Recurse -EA SilentlyContinue
            Remove-Item -LiteralPath $path -Force -Recurse -EA SilentlyContinue
        }catch{}
        if(& $gone){ & $WL "OK - via Robocopy"; return @{success=$true;message="Supprime via Robocopy"} }
    }

    # Etape 6 : element par element, le reste au redemarrage
    & $WL "Etape 6/6 - Suppression element par element (le reste au redemarrage)..."
    $del = 0; $lock = 0
    if($isDir){
        $files = @(Get-ChildItem -LiteralPath $path -Recurse -Force -File -EA SilentlyContinue)
        & $WL "Total: $($files.Count) fichier(s)"
        foreach($f in $files){
            try{ Remove-Item -LiteralPath $f.FullName -Force -EA Stop; $del++ }
            catch{ if(Register-RebootDelete $f.FullName){ $lock++; if($lock -le 20){ & $WL "Programme au redemarrage : $($f.Name)" } } }
        }
        $dirs = @(Get-ChildItem -LiteralPath $path -Recurse -Force -Directory -EA SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)
        foreach($d in $dirs){
            try{ Remove-Item -LiteralPath $d.FullName -Force -EA Stop }
            catch{ [void](Register-RebootDelete $d.FullName) }
        }
        try{ Remove-Item -LiteralPath $path -Force -EA Stop }catch{}
        if(-not (& $gone)){ if(Register-RebootDelete $path){ $lock++ } }
    } else {
        if(Register-RebootDelete $path){ $lock++ }
    }
    if(& $gone){ & $WL "OK - $del fichier(s)"; return @{success=$true;message="Supprime ($del fichier(s))"} }
    if($lock -gt 0){
        $m = "Element verrouille par Windows : suppression programmee au prochain redemarrage"
        if($del -gt 0){ $m = "$del fichier(s) supprime(s), le reste au prochain redemarrage" }
        & $WL "OK - $m"
        return @{success=$true;message=$m;rebootPending=$true}
    }
    & $WL "ECHEC"
    return @{success=$false;error="Impossible de supprimer - redemarrez le PC et reessayez"}
}
function Set-CleaningSchedule($frequency, $time) {
    $cfgDir  = "$env:LOCALAPPDATA\OptiPC"
    $cfgFile = "$cfgDir\schedule.json"
    if(-not(Test-Path $cfgDir)){ [System.IO.Directory]::CreateDirectory($cfgDir) | Out-Null }
    if($frequency -eq "remove"){
        Remove-Item $cfgFile -Force -EA SilentlyContinue
        return @{success=$true;message="Planification supprimee"}
    }
    $st = if($time -and $time -match "^\d{2}:\d{2}$"){ $time } else { "03:00" }
    $cfg = @{frequency=$frequency;time=$st;lastRun=""} | ConvertTo-Json
    [IO.File]::WriteAllText($cfgFile, $cfg, [Text.Encoding]::UTF8)
    return @{success=$true;message="Planification activee : $frequency a $st"}
}
function Get-CleaningSchedule {
    $cfgFile = "$env:LOCALAPPDATA\OptiPC\schedule.json"
    if(-not(Test-Path $cfgFile)){ return @{enabled=$false;frequency="remove"} }
    try {
        $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
        return @{enabled=$true;frequency=$cfg.frequency;time=$cfg.time}
    } catch { return @{enabled=$false;frequency="remove"} }
}
function Invoke-ScheduledClean {
    try {
        $r = Invoke-Cleaning @(Get-OptiAutoCleanIds)
        $logFile = "$env:LOCALAPPDATA\OptiPC\clean.log"
        $dt = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
        Add-Content $logFile "[$dt] Nettoyage planifie : $($r.cleaned) liberes" -EA SilentlyContinue
        return @{cleaned=$r.cleaned;success=$true}
    } catch {
        return @{success=$false;error=$_.Exception.Message}
    }
}

function Get-CleanLog {
    $logFile = "$env:LOCALAPPDATA\OptiPC\clean.log"
    if(-not(Test-Path $logFile)){ return @{lines=@()} }
    # Avant : lecture du fichier ENTIER toutes les 3 minutes (il grossissait
    # d'une ligne par minute), et lignes renvoyees sous forme d'objets.
    $lines = [string[]]@()
    try{
        $fi = New-Object IO.FileInfo($logFile)
        if($fi.Length -gt 1MB){
            $keep = @([IO.File]::ReadAllLines($logFile,[Text.Encoding]::UTF8) | Where-Object { $_ -notmatch '\[VERIF\]' } | Select-Object -Last 500)
            [IO.File]::WriteAllLines($logFile, [string[]]$keep, [Text.Encoding]::UTF8)
        }
        $fs = [IO.File]::Open($logFile,'Open','Read','ReadWrite')
        try{
            if($fs.Length -gt 65536){ [void]$fs.Seek(-65536,'End') }
            $txt = (New-Object IO.StreamReader($fs,[Text.Encoding]::UTF8)).ReadToEnd()
        } finally { $fs.Close() }
        $lines = [string[]]@($txt -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '\[VERIF\]' } | Select-Object -Last 50 | ForEach-Object { [string]$_ })
    }catch{}
    @{lines=$lines}
}
function Get-DiskCategories {
    # Analyse rapide et bornee dans le temps : ne peut plus "echouer" silencieusement.
    # On parcourt nous-memes l arborescence (System.IO) au lieu de Get-ChildItem -Recurse,
    # qui ne peut pas etre interrompu et partait en timeout sur les gros profils.
    $sw        = [System.Diagnostics.Stopwatch]::StartNew()
    $budgetMs  = 22000
    $maxFiles  = 250000

    $extMap = @{}
    $def = @{
        Photos    = @('.jpg','.jpeg','.png','.gif','.bmp','.tiff','.tif','.webp','.raw','.heic','.cr2','.nef','.svg')
        Videos    = @('.mp4','.avi','.mkv','.mov','.wmv','.flv','.m4v','.webm','.ts','.mpg','.mpeg','.vob','.3gp')
        Music     = @('.mp3','.flac','.wav','.aac','.ogg','.wma','.m4a','.opus','.mid','.aiff')
        Documents = @('.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.csv','.odt','.ods','.rtf','.epub','.pub','.one')
        Archives  = @('.zip','.rar','.7z','.tar','.gz','.bz2','.iso','.img','.cab','.msi','.exe')
    }
    foreach($c in $def.Keys){ foreach($e in $def[$c]){ $extMap[$e] = $c } }

    $order = @('Documents','Photos','Videos','Music','Archives','Autres')
    $sizes = @{}
    foreach($k in $order){ $sizes[$k] = [long]0 }

    # Dossiers personnels, y compris les variantes redirigees vers OneDrive
    $candidates = New-Object System.Collections.Generic.List[string]
    $up = $env:USERPROFILE
    if(-not $up){ $up = $env:HOME }
    if($up){
        foreach($n in @('Documents','Downloads','Desktop','Pictures','Videos','Music')){
            $candidates.Add((Join-Path $up $n))
        }
    }
    foreach($n in @('Documents','Bureau','Desktop','Images','Pictures','Videos','Vid' + [char]0xE9 + 'os','Music','Musique','Downloads','T' + [char]0xE9 + 'l' + [char]0xE9 + 'chargements')){
        foreach($od in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)){
            if($od){ $candidates.Add((Join-Path $od $n)) }
        }
    }

    $roots = @()
    $seen  = @{}
    foreach($c in $candidates){
        if(-not $c){ continue }
        try { $full = [System.IO.Path]::GetFullPath($c) } catch { continue }
        $key = $full.ToLower()
        if($seen.ContainsKey($key)){ continue }
        if(-not [System.IO.Directory]::Exists($full)){ continue }
        $seen[$key] = $true
        $roots += $full
    }

    $fileCount = 0
    $errCount  = 0
    $partial   = $false

    foreach($root in $roots){
        if($sw.ElapsedMilliseconds -ge $budgetMs){ $partial = $true; break }
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($root)
        while($stack.Count -gt 0){
            if($sw.ElapsedMilliseconds -ge $budgetMs -or $fileCount -ge $maxFiles){ $partial = $true; break }
            $dir = $stack.Pop()
            try {
                $di = New-Object System.IO.DirectoryInfo $dir
                foreach($f in $di.EnumerateFiles()){
                    $fileCount++
                    $len = 0
                    try { $len = [long]$f.Length } catch { $len = 0 }
                    $ext = $f.Extension
                    if($ext){ $ext = $ext.ToLower() }
                    $cat = $null
                    if($ext -and $extMap.ContainsKey($ext)){ $cat = $extMap[$ext] }
                    if(-not $cat){ $cat = 'Autres' }
                    $sizes[$cat] += $len
                    if(($fileCount % 4000) -eq 0 -and $sw.ElapsedMilliseconds -ge $budgetMs){ $partial = $true; break }
                }
                foreach($sub in $di.EnumerateDirectories()){
                    try {
                        if(($sub.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0){ continue }
                    } catch { continue }
                    $stack.Push($sub.FullName)
                }
            } catch { $errCount++ }
        }
    }

    $result = @()
    foreach($k in $order){
        $result += @{ name=$k; size=$sizes[$k]; sizeStr=(Format-Size $sizes[$k]) }
    }
    $totalBytes = [long]0
    foreach($r in $result){ $totalBytes += [long]$r.size }

    @{
        ok         = $true
        categories = $result
        total      = (Format-Size $totalBytes)
        totalBytes = $totalBytes
        scanned    = $fileCount
        folders    = @($roots).Count
        partial    = $partial
        elapsed    = [int]($sw.ElapsedMilliseconds / 1000)
        skipped    = $errCount
    }
}
function Stop-ProcessById($pidNum){
    try{
        $pidInt = [int]$pidNum
        $sysProcs = @('System','Idle','Registry','smss','csrss','wininit','services','lsass','MemCompression')
        $p = Get-Process -Id $pidInt -EA SilentlyContinue
        if(-not $p){ return @{success=$true;message="Processus déjà terminé"} }
        $pName = $p.ProcessName
        if($sysProcs -contains $pName){ return @{success=$false;error="Processus système protégé : $pName"} }

        # Méthode 1 : taskkill /F /T (kill process ET ses enfants, comme Gestionnaire des tâches)
        $result = cmd /c "taskkill /F /T /PID $pidInt 2>&1"
        Start-Sleep -Milliseconds 600
        $check = Get-Process -Id $pidInt -EA SilentlyContinue
        if(-not $check){ return @{success=$true;name=$pName;message="$pName terminé"} }

        # Méthode 2 : Stop-Process force
        Stop-Process -Id $pidInt -Force -EA SilentlyContinue
        Start-Sleep -Milliseconds 500
        $check2 = Get-Process -Id $pidInt -EA SilentlyContinue
        if(-not $check2){ return @{success=$true;name=$pName;message="$pName terminé"} }

        # Méthode 3 : wmic (dernier recours)
        $wmic = cmd /c "wmic process where processid=$pidInt delete 2>&1"
        Start-Sleep -Milliseconds 500
        $check3 = Get-Process -Id $pidInt -EA SilentlyContinue
        if(-not $check3){ return @{success=$true;name=$pName;message="$pName terminé"} }

        return @{success=$false;error="$pName : accès refusé par Windows"}
    } catch {
        return @{success=$false;error=$_.Exception.Message}
    }
}
function Get-OptiPCPubKeySpki {
    # Cle PUBLIQUE de H2OCONSULTING - FZCO (format standard SPKI/X.509, celle
    # d'un fichier "-----BEGIN PUBLIC KEY-----", sans les lignes BEGIN/END).
    # Elle ne permet que de VERIFIER une licence, jamais d'en fabriquer.
    # La cle privee correspondante reste sur le serveur (variable
    # LICENSE_PRIVATE_KEY dans Railway). Regeneree le 14/09/2026 (2e fois)
    # suite a la perte de la cle precedente avant son installation reussie
    # sur Railway.
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwKIywxBtJ/gluJ5G/5B1s31wXjH9E9GlJlYv62M3QbFZ7P1WX0smHRfk9EyXjKC7pooYRySKSjaKNBjYWXsNPP9CCshJLQcRIqbiwqg/ZVQg2kXvi6xKlnu3Dm7wzKzUeQvtaALQT2X9V7Hb9hVN43p768ZxSjImRwmbXU6NjEo55OAS1wx/bVhLiBDsAIQSHuGjftCRDnip6SZAn56aFxciF4eACet/SF0Bae44XGg8LWBVxW1e8HkqMenBQqNMEtp2vu4V4Rpvoo6odHrQU8txe7szx7FMH7t0jvpA7ZgUtuhTDDV+Wy15bCrQO2LXjoKS3fHUiCj5OZQcf0J+vQIDAQAB'
}

function Get-LicenseTokenFile { "$env:LOCALAPPDATA\OptiPC\license.token" }
function Get-LicenseMetaFile  { "$env:LOCALAPPDATA\OptiPC\license.meta" }

function ConvertFrom-B64Url($s) {
    $t = ([string]$s).Replace('-','+').Replace('_','/')
    switch($t.Length % 4){ 2 { $t += '==' } 3 { $t += '=' } }
    [Convert]::FromBase64String($t)
}

function New-OptiPCRsaVerifier {
    # PowerShell 5.1 (Windows PowerShell, .NET Framework) et PowerShell 7
    # (.NET moderne) n'exposent pas RSA de la meme facon. Sur du Windows
    # PowerShell 5.1 avec un .NET Framework pas assez recent,
    # ImportSubjectPublicKeyInfo() n'existe carrement pas (confirme le
    # 14/09/2026 sur un poste client : erreur "ne contient pas de methode").
    # On essaie d'abord la methode moderne, puis on retombe sur la
    # reconstruction manuelle du module/exposant RSA (marche partout,
    # y compris sur les tres vieilles versions de .NET Framework).
    $der = [Convert]::FromBase64String((Get-OptiPCPubKeySpki))
    foreach($mode in @('cng','aes','default')){
        try {
            $rsa = $null
            if($mode -eq 'cng'){
                $rsa = New-Object System.Security.Cryptography.RSACng
            } elseif($mode -eq 'aes'){
                $csp = New-Object System.Security.Cryptography.CspParameters 24
                $csp.Flags = [System.Security.Cryptography.CspProviderFlags]::UseMachineKeyStore
                $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider $csp
            } else {
                $rsa = [System.Security.Cryptography.RSA]::Create()
            }
            $bytesRead = 0
            $rsa.ImportSubjectPublicKeyInfo($der, [ref]$bytesRead)
            return $rsa
        } catch {}
    }

    # Repli universel : module (n) et exposant (e) RSA extraits une fois
    # pour toutes de la cle publique SPKI ci-dessus, encodes en base64.
    # Ça fonctionne avec RSAParameters sur toutes les versions de .NET,
    # meme les plus anciennes.
    try {
        $modulusB64  = 'wKIywxBtJ/gluJ5G/5B1s31wXjH9E9GlJlYv62M3QbFZ7P1WX0smHRfk9EyXjKC7pooYRySKSjaKNBjYWXsNPP9CCshJLQcRIqbiwqg/ZVQg2kXvi6xKlnu3Dm7wzKzUeQvtaALQT2X9V7Hb9hVN43p768ZxSjImRwmbXU6NjEo55OAS1wx/bVhLiBDsAIQSHuGjftCRDnip6SZAn56aFxciF4eACet/SF0Bae44XGg8LWBVxW1e8HkqMenBQqNMEtp2vu4V4Rpvoo6odHrQU8txe7szx7FMH7t0jvpA7ZgUtuhTDDV+Wy15bCrQO2LXjoKS3fHUiCj5OZQcf0J+vQ=='
        $exponentB64 = 'AQAB'
        $rsaParams = New-Object System.Security.Cryptography.RSAParameters
        $rsaParams.Modulus  = [Convert]::FromBase64String($modulusB64)
        $rsaParams.Exponent = [Convert]::FromBase64String($exponentB64)
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportParameters($rsaParams)
        return $rsa
    } catch {}

    $null
}

function Test-OptiPCSignatureState($bodyText, $sigBytes) {
    # Renvoie 'valide', 'invalide' ou 'moteur_absent'.
    # Cette distinction est capitale et manquait jusqu'ici : une signature
    # REFUSEE signifie jeton falsifie (on refuse la licence), alors qu'un
    # MOTEUR DE VERIFICATION indisponible (vieux .NET Framework, fournisseur
    # RSA non accessible sous certains comptes Windows) ne dit strictement
    # rien sur le jeton. Les confondre revenait a refuser la licence d'un
    # client qui avait pourtant paye - et dont le poste etait deja consomme
    # cote serveur.
    $rsa = New-OptiPCRsaVerifier
    if(-not $rsa){ return 'moteur_absent' }
    try {
        $data = [Text.Encoding]::UTF8.GetBytes([string]$bodyText)
        $alg  = [System.Security.Cryptography.HashAlgorithmName]::SHA256
        $pad  = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        if($rsa.VerifyData($data, $sigBytes, $alg, $pad)){ return 'valide' }
        return 'invalide'
    } catch { return 'moteur_absent' }
    finally { try { $rsa.Dispose() } catch {} }
}

function Test-OptiPCSignature($bodyText, $sigBytes) {
    (Test-OptiPCSignatureState $bodyText $sigBytes) -eq 'valide'
}

function Get-OptiPCEpochNow {
    # ─────────────────────────────────────────────────────────────────────
    # BUG MAJEUR CORRIGE LE 15/09/2026 - la panne "plus rien ne marche".
    # Le code ecrivait :
    #     [int][double]::Parse( (...).TotalSeconds )
    # [double]::Parse lit la chaine AVEC LA LANGUE DE WINDOWS. Sur un
    # Windows FRANCAIS, le separateur decimal est la virgule : la chaine
    # "1789430034.759" produite par PowerShell y est jugee invalide et la
    # methode leve une exception. Read-OptiPCToken plantait donc net, ET
    # UNIQUEMENT UNE FOIS QU'UNE LICENCE VALIDE EXISTAIT sur le poste (sans
    # jeton, la fonction sort avant cette ligne). D'ou le symptome : tant
    # que les cles ne marchaient pas, le logiciel fonctionnait ; des que
    # l'activation a marche, toutes les routes touchant a la licence se
    # sont mises a repondre 500 (etat Pro, controle serveur, mise en
    # quarantaine et suppression des menaces).
    # On ne convertit plus aucun nombre en texte : on demande directement
    # l'heure Unix a .NET.
    # ─────────────────────────────────────────────────────────────────────
    try { return [int][System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } catch {}
    try { return [int][Math]::Floor(((Get-Date).ToUniversalTime() - (New-Object DateTime 1970,1,1)).TotalSeconds) } catch {}
    0
}

function Read-OptiPCToken {
    # Lit le jeton stocke, verifie la SIGNATURE, la DATE et l'ORDINATEUR.
    # Tant que ces trois controles ne passent pas, le poste reste en gratuit.
    # Cette fonction ne doit JAMAIS lever d'exception : elle est appelee par
    # l'etat Pro, le controle serveur et les fonctions de securite. Une
    # exception ici mettait hors service toutes ces routes d'un coup.
    try {
    $f = Get-LicenseTokenFile
    if(-not(Test-Path $f)){ return @{valid=$false;reason='absent'} }
    $tok = ''
    try { $tok = ([IO.File]::ReadAllText($f,[Text.Encoding]::UTF8)).Trim() } catch {}
    if(-not $tok -or $tok -notmatch '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$'){ return @{valid=$false;reason='illisible'} }
    $parts = $tok.Split('.')
    $sigState = 'invalide'
    try { $sigState = Test-OptiPCSignatureState $parts[0] (ConvertFrom-B64Url $parts[1]) } catch { $sigState = 'moteur_absent' }
    if($sigState -eq 'invalide'){
        return @{valid=$false;reason='signature'}
    }
    $p = $null
    try { $p = [Text.Encoding]::UTF8.GetString((ConvertFrom-B64Url $parts[0])) | ConvertFrom-Json } catch {}
    if(-not $p){ return @{valid=$false;reason='contenu'} }
    $now = Get-OptiPCEpochNow
    if($now -gt 0 -and [int]$p.exp -le $now){ return @{valid=$false;reason='expire';payload=$p} }
    $mid = ''
    try { $mid = Get-MachineFingerprint } catch {}
    if($p.mid -and $mid -and ([string]$p.mid -ne [string]$mid)){ return @{valid=$false;reason='autre_ordinateur';payload=$p} }
    @{valid=$true;payload=$p;token=$tok;unverified=($sigState -ne 'valide')}
    } catch {
        @{valid=$false;reason='erreur_locale';error=[string]$_.Exception.Message}
    }
}

function Test-IsPro {
    try { [bool](Read-OptiPCToken).valid } catch { $false }
}

function Save-OptiPCToken($token, $extra) {
    $d = "$env:LOCALAPPDATA\OptiPC"
    if(-not(Test-Path $d)){ [System.IO.Directory]::CreateDirectory($d) | Out-Null }
    [IO.File]::WriteAllText((Get-LicenseTokenFile), [string]$token, [Text.Encoding]::UTF8)
    if($extra){
        try { ($extra | ConvertTo-Json -Compress) | Out-File (Get-LicenseMetaFile) -Encoding UTF8 -Force } catch {}
    }
}

function Clear-OptiPCLicense {
    foreach($f in @((Get-LicenseTokenFile),(Get-LicenseMetaFile),"$env:LOCALAPPDATA\OptiPC\license.key")){
        try { Remove-Item $f -Force -EA SilentlyContinue } catch {}
    }
}

function Invoke-ActivateLicense($key) {
    # ACTIVATION EN LIGNE : le serveur seul decide. Une cle qui n'existe pas
    # dans votre base est refusee, quelle que soit sa forme.
    #
    # ─────────────────────────────────────────────────────────────────────
    # REFONTE DU 15/09/2026 - REGLE D'OR : cette fonction ne doit JAMAIS
    # lever d'exception.
    #
    # Bug constate en production (preuve dans les journaux reseau Railway du
    # 15/09/2026 a 01:23:38 : POST /v1/activate -> HTTP 200 en 71 ms, poste
    # enregistre cote serveur) : l'activation REUSSISSAIT cote serveur, puis
    # une erreur purement locale survenait ensuite (ecriture du jeton, moteur
    # RSA indisponible, WMI capricieux). Cette exception remontait jusqu'au
    # petit serveur HTTP local d'OptiPC, qui repondait alors 500 SANS corps ;
    # l'interface tombait dans son "catch", affichait seulement le bandeau
    # "Erreur connexion" et LAISSAIT A L'ECRAN le message d'erreur de la
    # tentative precedente - typiquement "Cette cle n'existe pas".
    # Resultat pour le client : sa cle etait bien consommee dans le tableau
    # de bord, mais le logiciel lui affichait que la cle n'existait pas.
    # ─────────────────────────────────────────────────────────────────────
    try {
        $k = ([string]$key).ToUpper().Trim()
        if(-not $k){ return @{isPro=$false;message="Entrez votre cle."} }
        $mid = ''
        try { $mid = Get-MachineFingerprint } catch {}
        $osName = ''
        try { $osName = [string](Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue).Caption } catch {}
        $ver = ''
        try { $ver = [string](Get-OptiPCVersion) } catch {}
        $body = @{ key=$k; machine_id=$mid; hostname=$env:COMPUTERNAME; os=$osName; app_version=$ver }
        $r = Invoke-OptiPCWeb ((Get-OptiPCApiBase) + '/v1/activate') 'POST' $body 25
        if(-not $r.ok){
            if($r.status -eq 404){ return @{isPro=$false;message="Cette cle n'existe pas. Verifiez votre email d'achat, ou appelez le 05 54 54 23 43."} }
            if($r.status -eq 409){ return @{isPro=$false;message="Cette cle est deja utilisee sur un autre ordinateur. Liberez-le, ou appelez le 05 54 54 23 43."} }
            if($r.status -eq 403){ return @{isPro=$false;message="Cet abonnement n'est plus actif. Appelez le 05 54 54 23 43."} }
            if($r.status -eq 400){ return @{isPro=$false;message="Cle invalide. Format attendu : ST-XXXX-XXXX-XXXX."} }
            if($r.serverMessage){ return @{isPro=$false;message=[string]$r.serverMessage} }
            if($r.status -gt 0){ return @{isPro=$false;message="Le serveur d'activation a refuse la demande (code $($r.status)). Appelez le 05 54 54 23 43."} }
            return @{isPro=$false;offline=$true;message="Impossible de joindre le serveur d'activation : $($r.error)"}
        }
        $d = $r.data
        if(-not $d.token){ return @{isPro=$false;message=[string]$d.message} }

        # Le serveur a accepte la cle et consomme le poste : la licence est
        # ACQUISE. On enregistre le jeton tout de suite, pour qu'aucun incident
        # local ne puisse faire perdre au client une activation deja payee.
        $saved = $true
        try {
            Save-OptiPCToken $d.token @{
                activated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
                key_display  = ($k.Substring(0,[Math]::Min(7,$k.Length)) + '-****-****')
                plan         = [string]$d.plan
                period       = [string]$d.billing_period
                period_end   = [string]$d.current_period_end
            }
        } catch { $saved = $false }

        # Revalidation locale. Une signature REFUSEE = jeton falsifie : on
        # refuse. Tout autre alea local (moteur RSA absent d'un vieux .NET,
        # empreinte machine instable) ne remet pas en cause un jeton qui vient
        # d'arriver par une liaison HTTPS avec notre propre serveur : on
        # active, et les controles suivants (demarrage, heartbeat) feront foi.
        # Avant, ces cas effacaient la licence alors que le poste restait
        # consomme cote serveur - le client perdait sa cle pour rien.
        $reason = ''
        try {
            $chk = Read-OptiPCToken
            if(-not $chk.valid){ $reason = [string]$chk.reason }
        } catch { $reason = 'exception' }
        if($reason -eq 'signature'){
            Clear-OptiPCLicense
            return @{isPro=$false;message="La licence recue n'a pas pu etre verifiee (signature refusee). Appelez le 05 54 54 23 43."}
        }
        if(-not $saved){
            return @{isPro=$false;message="Votre licence a bien ete validee par le serveur, mais OptiPC n'a pas pu l'enregistrer sur cet ordinateur. Fermez OptiPC, rouvrez-le, puis ressaisissez la cle. Si cela recommence, appelez le 05 54 54 23 43."}
        }
        @{
            isPro=$true; message="Licence activee"
            activated_at=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'); days_active=0
            seats_used=[int]$d.seats_used; seats_max=[int]$d.seats_max
            warning=[string]$d.warning; period_end=[string]$d.current_period_end
            local_check=$(if($reason){ $reason } else { 'ok' })
        }
    } catch {
        # Filet ultime : on renvoie TOUJOURS une reponse lisible, jamais une
        # exception qui ferait repondre 500 au serveur local.
        $__m = ''
        try { $__m = [string]$_.Exception.Message } catch {}
        # Le jeton a peut-etre ete enregistre avant l'incident : dans ce cas
        # la licence est reellement active, on le dit au lieu d'afficher une
        # erreur trompeuse.
        $__pro = $false
        try { $__pro = [bool](Test-IsPro) } catch {}
        if($__pro){
            return @{
                isPro=$true; message="Licence activee"
                activated_at=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'); days_active=0
                local_check='recuperee_apres_incident'
            }
        }
        @{isPro=$false;message="L'activation s'est interrompue sur cet ordinateur ($__m). Fermez OptiPC, rouvrez-le et ressaisissez la cle, ou appelez le 05 54 54 23 43."}
    }
}

function Invoke-LicenseHeartbeat($force) {
    # Controle silencieux : renouvelle le jeton et applique immediatement une
    # desactivation faite depuis votre tableau de bord.
    try {
    $st = Read-OptiPCToken
    if(-not $st.valid -and $st.reason -ne 'expire'){ return @{checked=$false} }
    $tok = ''
    try { $tok = ([IO.File]::ReadAllText((Get-LicenseTokenFile),[Text.Encoding]::UTF8)).Trim() } catch {}
    if(-not $tok){ return @{checked=$false} }

    $stamp = "$env:LOCALAPPDATA\OptiPC\heartbeat.stamp"
    if(-not $force){
        $days = 3
        try { if($st.payload -and $st.payload.hb){ $days = [int]$st.payload.hb } } catch {}
        if(Test-Path $stamp){
            try {
                $last = [datetime]::Parse(([IO.File]::ReadAllText($stamp)).Trim())
                if(((Get-Date) - $last).TotalDays -lt $days){ return @{checked=$false;reason='trop_tot'} }
            } catch {}
        }
    }
    $r = Invoke-OptiPCWeb ((Get-OptiPCApiBase) + '/v1/heartbeat') 'POST' @{ token=$tok; app_version=(Get-OptiPCVersion) } 20
    try { [IO.File]::WriteAllText($stamp,(Get-Date -Format 'o'),[Text.Encoding]::UTF8) } catch {}
    if(-not $r.ok){
        # Hors ligne : on ne coupe rien, le jeton reste valable jusqu'a sa date.
        if($r.status -eq 403 -or $r.status -eq 404){
            Clear-OptiPCLicense
            return @{checked=$true;revoked=$true;message="Votre licence a ete desactivee."}
        }
        return @{checked=$true;offline=$true}
    }
    if($r.data.token){ Save-OptiPCToken $r.data.token $null }
    # 26/10/2026 : date de fin tenue a jour (licence prolongee depuis le CRM de SecureeTech)
    try {
      if($r.data.current_period_end){
        $mf = Get-LicenseMetaFile
        if(Test-Path $mf){
          $m = Get-Content $mf -Raw | ConvertFrom-Json
          $fin = $r.data.current_period_end
          if($fin -is [datetime]){ $fin = $fin.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
          $m | Add-Member -NotePropertyName period_end -NotePropertyValue ([string]$fin) -Force
          [IO.File]::WriteAllText($mf, ($m | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)
        }
      }
    } catch {}
    @{checked=$true;status=[string]$r.data.subscription_status;warning=[string]$r.data.warning}
    } catch {
        # Un controle de licence qui echoue ne doit jamais rien couper.
        @{checked=$false;error=[string]$_.Exception.Message}
    }
}

function Invoke-RevokeLicense {
    # Libere le poste cote serveur PUIS efface la licence locale, pour que la
    # cle puisse etre reutilisee sur un autre ordinateur.
    try {
    $tok = ''
    try { $tok = ([IO.File]::ReadAllText((Get-LicenseTokenFile),[Text.Encoding]::UTF8)).Trim() } catch {}
    $served = $false
    if($tok){
        $r = Invoke-OptiPCWeb ((Get-OptiPCApiBase) + '/v1/deactivate') 'POST' @{ token=$tok } 20
        $served = [bool]$r.ok
    }
    Clear-OptiPCLicense
    @{success=$true;server=$served;message=$(if($served){"Poste libere. Vous pouvez utiliser votre cle sur un autre ordinateur."}else{"Licence retiree de cet ordinateur."})}
    } catch {
        try { Clear-OptiPCLicense } catch {}
        @{success=$true;server=$false;message="Licence retiree de cet ordinateur."}
    }
}

function Get-LicenseStatus {
    try {
    $st = Read-OptiPCToken
    $res = @{ isPro=[bool]$st.valid; plan=$(if($st.valid){'PRO'}else{'FREE'}); reason=[string]$st.reason }
    if($st.valid){
        $mf = Get-LicenseMetaFile
        if(Test-Path $mf){
            try {
                $m = Get-Content $mf -Raw | ConvertFrom-Json
                $res.activated_at = [string]$m.activated_at
                $res.key_display  = [string]$m.key_display
                $res.period       = [string]$m.period
                $res.period_end   = [string]$m.period_end
                $res.trial        = [bool]$m.trial
                try { $res.days_active = [int]([datetime]::Now - [datetime]::Parse($m.activated_at)).TotalDays } catch {}
            } catch {}
        }
        try { $res.expires_at = ([datetime]'1970-01-01').AddSeconds([int]$st.payload.exp).ToString('yyyy-MM-dd') } catch {}
    }
    # Essai gratuit termine : on le signale pour proposer l'abonnement.
    if(-not $st.valid -and $st.reason -eq 'expire'){
        try {
            $m2 = Get-Content (Get-LicenseMetaFile) -Raw | ConvertFrom-Json
            if([bool]$m2.trial){ $res.trialEnded = $true }
        } catch {}
    }
    try {
        if(Test-Path "$env:LOCALAPPDATA\OptiPC\trial.used"){
            $res.trialUsed = $true
            if(-not $st.valid){ $res.trialEnded = $true }
        }
    } catch {}
    $res
    } catch {
        # Jamais de 500 sur l'etat de licence : l'interface doit toujours
        # pouvoir demarrer, meme si la licence est illisible.
        @{ isPro=$false; plan='FREE'; reason='erreur_locale'; error=[string]$_.Exception.Message }
    }
}
# ══════════════════════════════════════════════════════════════════════════
#  ESSAI PRO GRATUIT (5 jours) DEMANDE AUTOMATIQUEMENT PAR LE LOGICIEL
#  Le serveur de licences (/v1/optipc/trial) genere une cle d'essai de 5 jours,
#  puis OptiPC l'active aussitot : aucun formulaire, le client n'a rien a faire.
#  Un seul essai par ordinateur (controle cote serveur sur l'identifiant de poste).
# ══════════════════════════════════════════════════════════════════════════
function Get-OptiPCCrmBase { 'https://crm-secureetech.up.railway.app' }

function Invoke-StartTrial($prenom, $email, $telephone, $rappel, $nom = '', $newsletter = 'non') {
    try {
        if(Test-IsPro){ return @{ok=$false;message="La version Pro est deja active sur cet ordinateur."} }
        $mid = ''
        try { $mid = Get-MachineFingerprint } catch {}
        $ver = ''
        try { $ver = [string](Get-OptiPCVersion) } catch {}
        # Depuis la 2.1 (19/10/2026) : essai automatique, sans formulaire. Le serveur de
        # licences cree une cle d'essai de 5 jours, une seule fois par ordinateur.
        $body = @{
            product     = 'optipc'
            machine_id  = $mid
            hostname    = $env:COMPUTERNAME
            app_version = $ver
        }
        $r = Invoke-OptiPCWeb ((Get-OptiPCApiBase) + '/v1/optipc/trial') 'POST' $body 30
        if(-not $r.ok){
            $msg = ''
            try { if($r.server){ $j = $r.server | ConvertFrom-Json; if($j.message){ $msg = [string]$j.message } elseif($j.erreur){ $msg = [string]$j.erreur } } } catch {}
            if(-not $msg){
                if($r.status -gt 0){ $msg = "Le serveur a refuse la demande (code $($r.status)). Appelez le 05 54 54 23 43." }
                else { $msg = "Impossible de joindre le serveur. Verifiez votre connexion internet, puis reessayez." }
            }
            if($r.status -eq 409){ try { [System.IO.Directory]::CreateDirectory("$env:LOCALAPPDATA\OptiPC") | Out-Null; [IO.File]::WriteAllText("$env:LOCALAPPDATA\OptiPC\trial.used", (Get-Date -Format 'o')) } catch {} }
            return @{ok=$false;message=$msg;already=($r.status -eq 409)}
        }
        $cle = [string]$r.data.key
        if(-not $cle){ return @{ok=$false;message="La cle d'essai n'a pas pu etre generee. Appelez le 05 54 54 23 43."} }
        $act = Invoke-ActivateLicense $cle
        if(-not $act.isPro -or -not (Test-IsPro)){
            return @{ok=$false;cle=$cle;message=("Votre cle d'essai est $cle, mais l'activation a echoue : " + [string]$act.message)}
        }
        # On marque la licence comme ESSAI (affichage de la date de fin, puis
        # proposition d'abonnement quand l'essai est termine).
        try {
            $mf = Get-LicenseMetaFile
            $m = @{}
            if(Test-Path $mf){
                $o = Get-Content $mf -Raw | ConvertFrom-Json
                foreach($p in $o.PSObject.Properties){ $m[$p.Name] = $p.Value }
            }
            $m.trial = $true
            $m.trial_days = [int]$r.data.days
            ($m | ConvertTo-Json -Compress) | Out-File $mf -Encoding UTF8 -Force
        } catch {}
        try { [System.IO.Directory]::CreateDirectory("$env:LOCALAPPDATA\OptiPC") | Out-Null; [IO.File]::WriteAllText("$env:LOCALAPPDATA\OptiPC\trial.used", (Get-Date -Format 'o')) } catch {}
        $st = Get-LicenseStatus
        $st.ok = $true
        $st.days = [int]$r.data.days
        $st
    } catch {
        @{ok=$false;message="L'essai n'a pas pu demarrer sur cet ordinateur : $($_.Exception.Message)"}
    }
}

function Get-SecurityStatus {
    $r=@{defEnabled=$false;defSigAge=-1;fwOk=$false;uacOk=$true;ssOk=$true;otherAV=$false;otherAVName=""}
    try{$mp=Get-MpComputerStatus -EA SilentlyContinue
        if($mp){$r.defEnabled=[bool]$mp.RealTimeProtectionEnabled
            if($mp.AntivirusSignatureAge -ne $null){$r.defSigAge=[int]$mp.AntivirusSignatureAge}}}catch{}
    try{
        $avList=Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -EA SilentlyContinue |
            Where-Object{$_.displayName -notmatch 'Windows Defender|Microsoft Defender|WindowsDefender'}
        if(($avList|Measure-Object).Count -gt 0){
            $r.otherAV=$true
            $r.otherAVName=($avList | Select-Object -ExpandProperty displayName) -join ", "
            # Si autre AV actif, Defender desactive est normal
            if(-not $r.defEnabled){ $r.defEnabled = $true }
        }
    }catch{}
    try{$fw=Get-NetFirewallProfile -EA SilentlyContinue
        $r.fwOk=(@($fw|Where-Object{$_.Enabled}).Count -ge 3)}catch{}
    try{$uac=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -EA SilentlyContinue).EnableLUA
        $r.uacOk=($uac -eq 1)}catch{}
    # 2.0 : valeur absente = reglage par defaut de Windows (SmartScreen actif).
    # La V1 signalait a tort "SmartScreen desactive" sur ces PC.
    try{$ss=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -EA SilentlyContinue).SmartScreenEnabled
        $pol=$null; try{$pol=(Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -EA SilentlyContinue).EnableSmartScreen}catch{}
        $r.ssOk=($ss -ne 'Off' -and $pol -ne 0)}catch{}
    $r
}
function Invoke-MalwareScan {
    $thr=[System.Collections.ArrayList]::new()
    try{$dth=Get-MpThreatDetection -EA SilentlyContinue|Select-Object -First 10
        foreach($t in $dth){$nm='Malware'
            try{$ti=Get-MpThreat -ThreatID $t.ThreatID -EA SilentlyContinue|Select-Object -First 1
                if($ti){$nm=[string]$ti.ThreatName}}catch{}
            $pth=if($t.Resources){[string](@($t.Resources)[0])}else{'Inconnu'}
            [void]$thr.Add(@{cat='Defender';sev='critical';name=$nm;path=$pth;detail='Windows Defender';canDel=$true})}}catch{}
    try{$bad=@('xmrig','cryptominer','keylogger','remcos','njrat','asyncrat','darkcomet','mimikatz','cobalt','quasar','nanocore')
        Get-Process -EA SilentlyContinue|ForEach-Object{$n=$_.ProcessName.ToLower()
            foreach($b in $bad){if($n -match $b){[void]$thr.Add(@{cat='Processus';sev='critical';name="Malware: $($_.ProcessName)";path="PID $($_.Id)";detail='Processus malveillant';canDel=$false});break}}}}catch{}
    try{@('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')|ForEach-Object{
        if(-not(Test-Path $_)){return}
        $p=Get-ItemProperty $_ -EA SilentlyContinue;if(-not $p){return}
        $p.PSObject.Properties|Where-Object{$_.MemberType -eq 'NoteProperty' -and $_.Name -notmatch '^PS'}|ForEach-Object{
            $val=[string]$_.Value;$exe=$null
            if($val -match '"([^"]+\.exe)"'){$exe=$matches[1]}
            elseif($val -match '([A-Za-z]:\\[^\s"]+\.exe)'){$exe=$matches[1]}
            if($exe -and ($exe -match '\\Temp\\' -or $exe -match '\\AppData\\Roaming\\[^\\]+\.exe$')){
                $trust=$exe -match 'Microsoft|Google|Mozilla|Slack|Discord|Teams|Zoom|Spotify|Adobe|OneDrive|Dropbox'
                if(-not $trust){[void]$thr.Add(@{cat='Demarrage';sev='high';name="Suspect: $($_.Name)";path=$exe;detail='Programme au demarrage inhabituel';canDel=$true})}
            }}}}catch{}
    try{$dl="$env:USERPROFILE\Downloads"
        if(Test-Path $dl){$be=@('.scr','.pif','.vbs','.bat','.cmd','.hta')
            Get-ChildItem $dl -File -EA SilentlyContinue|Where-Object{$be -contains $_.Extension.ToLower()}|Select-Object -First 5|ForEach-Object{
                [void]$thr.Add(@{cat='Fichier';sev='medium';name="Risque: $($_.Name)";path=$_.FullName;detail='Fichier executable dangereux';canDel=$true})}}}catch{}
    try{$hosts=Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -EA SilentlyContinue
        $s=@($hosts|Where-Object{$_ -notmatch '^\s*#' -and $_ -match '\d' -and $_ -notmatch '127\.0\.0\.1\s+localhost' -and $_ -notmatch '^\s*::1\s'})
        if($s.Count -gt 0){[void]$thr.Add(@{cat='Reseau';sev='medium';name="Hosts modifie ($($s.Count))";path="$env:SystemRoot\System32\drivers\etc\hosts";detail='Redirections suspectes';canDel=$false})}}catch{}
    $__wl=@(Get-WhiteList); $thr=@($thr | Where-Object { -not (Test-OptiIgnored $_ $__wl) })
    $score=100;foreach($t in $thr){$score-=if($t.sev -eq 'critical'){25}elseif($t.sev -eq 'high'){15}else{8}}
    $score=[Math]::Max(0,[Math]::Min(100,$score))
    @{threats=@($thr);score=$score;count=$thr.Count;ts=(Get-Date -Format 'HH:mm:ss')}
}
function Do-SecurityFix {
    param($action)
    switch($action){
        'enable_defender'    {try{Set-MpPreference -DisableRealtimeMonitoring $false -EA SilentlyContinue;@{ok=$true;msg='Defender reactive'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        'update_defender'    {try{Update-MpSignature -EA SilentlyContinue;@{ok=$true;msg='MAJ Defender lancee'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        'enable_firewall'    {try{Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -EA SilentlyContinue;@{ok=$true;msg='Pare-feu reactive'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        'defender_scan'      {try{Start-MpScan -ScanType QuickScan -EA SilentlyContinue;@{ok=$true;msg='Scan demarre'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        'flush_dns'          {try{Clear-DnsClientCache -EA SilentlyContinue;@{ok=$true;msg='DNS vide'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        'reset_firewall'     {try{netsh advfirewall reset 2>$null;@{ok=$true;msg='Pare-feu reinitialise'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        'open_update'        {try{Start-Process 'ms-settings:windowsupdate' -EA SilentlyContinue;@{ok=$true;msg='Windows Update ouvert'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        'enable_uac'         {try{Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1 -Type DWord -EA Stop;@{ok=$true;msg='Controle des comptes reactive (redemarrage necessaire)'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        'enable_smartscreen' {try{Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name SmartScreenEnabled -Value 'Warn' -EA Stop
                                  $pk='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; if((Get-ItemProperty $pk -EA SilentlyContinue).EnableSmartScreen -eq 0){ Set-ItemProperty $pk -Name EnableSmartScreen -Value 1 -Type DWord -EA SilentlyContinue }
                                  @{ok=$true;msg='SmartScreen reactive'}}catch{@{ok=$false;msg=$_.Exception.Message}}}
        default              {@{ok=$false;msg='Action inconnue'}}
    }
}
function Get-AccessStatus {
    $r=@{cam=$true;mic=$true;tel=$true}
    try{$v=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' -EA SilentlyContinue).Value;$r.cam=($v -ne 'Deny')}catch{}
    try{$v=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone' -EA SilentlyContinue).Value;$r.mic=($v -ne 'Deny')}catch{}
    try{$v=(Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -EA SilentlyContinue).AllowTelemetry;$r.tel=($v -ne 0 -and $v -ne $null)}catch{}
    $r
}
function Set-AccessCtrl {
    param($feature,$enable)
    switch($feature){
        'cam'{$v=if($enable){'Allow'}else{'Deny'};try{Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' -Name Value -Value $v -EA SilentlyContinue;@{ok=$true}}catch{@{ok=$false}}}
        'mic'{$v=if($enable){'Allow'}else{'Deny'};try{Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone' -Name Value -Value $v -EA SilentlyContinue;@{ok=$true}}catch{@{ok=$false}}}
        'tel'{$v=if($enable){1}else{0};$k='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            try{if(-not(Test-Path $k)){New-Item $k -Force -EA SilentlyContinue|Out-Null}
                Set-ItemProperty $k -Name AllowTelemetry -Value $v -EA SilentlyContinue
                if(-not $enable){Stop-Service DiagTrack -Force -EA SilentlyContinue}
                @{ok=$true}}catch{@{ok=$false}}}
        default{@{ok=$false}}
    }
}
function Invoke-AntiTracking {
    $n=0
    @("$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cookies",
      "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History",
      "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cookies",
      "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History")|ForEach-Object{
        try{if(Test-Path $_){Remove-Item $_ -Force -EA SilentlyContinue;$n++}}catch{}}
    try{Stop-Service DiagTrack -Force -EA SilentlyContinue;Set-Service DiagTrack -StartupType Disabled -EA SilentlyContinue}catch{}
    @{ok=$true;cleaned=$n;msg="$n fichiers de tracking supprimes"}
}
function Remove-ThreatItem {
    param($path)
    try{if(Test-Path $path -EA SilentlyContinue){Remove-Item $path -Force -EA SilentlyContinue;@{ok=$true;msg='Supprime'}}else{@{ok=$false;msg='Introuvable'}}}catch{@{ok=$false;msg=$_.Exception.Message}}
}
function Open-ThreatPath {
    param($path)
    try{
        # Si c'est un chemin Windows Defender ou un nom d'AV, ouvrir Securite Windows
        if($path -match 'Windows Defender|Microsoft Defender|Defender' -or -not(Test-Path $path -EA SilentlyContinue)){
            Start-Process 'windowsdefender:' -EA SilentlyContinue
            @{ok=$true;msg='Securite Windows ouverte'}
        } else {
            $dir=Split-Path $path -Parent -EA SilentlyContinue
            if($dir -and (Test-Path $dir)){Start-Process 'explorer.exe' -ArgumentList "/select,`"$path`"" -EA SilentlyContinue}
            else{Start-Process 'explorer.exe' -EA SilentlyContinue}
            @{ok=$true}
        }
    }catch{@{ok=$false}}
}


$SCAN_PHASES=@{'1'='Windows Defender et Menaces';'2'='Processus en memoire';'3'='Programmes indesirables';'4'='Registre Demarrage';'5'='Taches planifiees';'6'='Services Windows';'7'='Fichiers dangereux';'8'='Reseau et Hosts';'9'='Navigateurs';'10'='WMI Persistance';'11'='IFEO Hijacking';'12'='DLL suspectes';'13'='Indicateurs Rootkit';'14'='Crypto Miners';'15'='Adware et Trackers';'16'='Ransomware';'17'='Score final'}

function Start-ScanSession($mode){
    if($mode -ne 'quick'){ $mode = 'full' }
    $plan = Get-ScanPlan $mode
    $SF = Get-ScanStateFile
    $RF = Get-ScanResultFile
    foreach($f in @($SF,$RF,"$env:TEMP\optipc_defpid.txt","$env:TEMP\optipc_defstart.txt",(Get-ScanStopFlag))){
        try{ if(Test-Path $f){ Remove-Item $f -Force -EA SilentlyContinue } }catch{}
    }
    $st = @{phase=0;total=$plan.Count;mode=$mode;threats='[]';log='[]';files=0;start=(Get-Date -Format 'o')}
    # Ecriture verifiee : si elle echoue, on le dit au lieu de laisser
    # l'analyse tourner dans le vide.
    $ok = $false; $err = ''
    try {
        [IO.File]::WriteAllText($SF, ($st | ConvertTo-Json -Compress), [Text.Encoding]::UTF8)
        $ok = (Test-Path $SF)
    } catch { $err = $_.Exception.Message }
    if(-not $ok){
        if(-not $err){ $err = "Impossible de creer le fichier de travail de l'analyse." }
        return @{started=$false;total=$plan.Count;mode=$mode;error=$err;workdir=(Get-ScanWorkDir)}
    }
    @{started=$true;total=$plan.Count;mode=$mode;workdir=(Get-ScanWorkDir)}
}

function Invoke-ScanPhase([int]$ph){
    $thr = New-Object System.Collections.ArrayList
    $fi  = 0
    $wl  = @(Get-WhiteList)
    function ThrAdd($C,$S,$N,$P,$D,$Del=$false){
        if(Test-OptiIgnored @{name=$N;path=$P} $wl){ return }
        # Nos propres logiciels (OptiPC, Vigilance...) ne sont jamais des menaces
        if(("$P $N") -match '(?i)\\SecureeTech\\|\\OptiPC\\|OptiPC\.(exe|ps1)|Vigilance\.(exe|ps1)'){ return }
        [void]$thr.Add(@{cat=$C;sev=$S;name=$N;path=$P;detail=$D;canDel=$Del})
    }
    function SafePath($p){ if($p){ ($p -replace '"','').Trim() } else { '' } }

    switch($ph){

    1 {
        $otherAV = $false; $avName = ''
        try{
            $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -EA SilentlyContinue |
                    Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' })
            if($av.Count -gt 0){ $otherAV = $true; $avName = ($av.displayName -join ', ') }
        }catch{}
        try{
            $mp = Get-MpComputerStatus -EA Stop
            $fi += 6
            if(-not $mp.RealTimeProtectionEnabled -and -not $otherAV){
                ThrAdd 'Securite' 'critical' 'Aucun antivirus actif' 'Protection temps reel' 'Windows Defender est desactive et aucun autre antivirus n a ete detecte : votre PC n est pas protege'
            }
            if($mp.RealTimeProtectionEnabled){
                if($mp.AntivirusSignatureAge -gt 14){ ThrAdd 'Defender' 'high' "Base antivirus obsolete ($($mp.AntivirusSignatureAge) jours)" 'Windows Defender' 'Les definitions de virus n ont pas ete mises a jour depuis plus de 2 semaines' }
                elseif($mp.AntivirusSignatureAge -gt 7){ ThrAdd 'Defender' 'medium' 'Base antivirus a mettre a jour' 'Windows Defender' 'Mise a jour des definitions recommandee' }
            }
            if($mp.PSObject.Properties.Name -contains 'IsTamperProtected' -and -not $mp.IsTamperProtected){
                ThrAdd 'Securite' 'low' 'Protection contre les falsifications desactivee' 'Windows Defender' 'La protection anti-alteration de Defender est inactive'
            }
        }catch{ ThrAdd 'Securite' 'medium' 'Verification antivirus impossible' 'Windows Defender' 'Impossible de lire l etat de la protection' }

        try{
            $pref = Get-MpPreference -EA SilentlyContinue
            if($pref){
                $fi += 4
                foreach($ex in @($pref.ExclusionPath)){
                    if(-not $ex){ continue }
                    if($ex -match '(?i)^[a-z]:\\?$' -or $ex -match '(?i)\\(users|windows|temp|appdata|downloads)\\?$' -or $ex -match '(?i)^[a-z]:\\users\\?$'){
                        ThrAdd 'Securite' 'critical' "Exclusion antivirus dangereuse : $ex" $ex 'Un dossier entier est exclu de l analyse antivirus - technique frequemment utilisee par les virus pour se cacher' 
                    } else {
                        ThrAdd 'Securite' 'low' "Exclusion antivirus : $ex" $ex 'Ce dossier n est pas analyse par l antivirus. Verifiez que vous en etes bien a l origine'
                    }
                }
                if($pref.DisableRealtimeMonitoring){ ThrAdd 'Securite' 'critical' 'Analyse en temps reel desactivee' 'Windows Defender' 'La surveillance permanente est coupee' }
                if($pref.DisableBehaviorMonitoring){ ThrAdd 'Securite' 'high' 'Surveillance comportementale desactivee' 'Windows Defender' 'La detection des comportements suspects est coupee' }
            }
        }catch{}

        try{
            $fw = @(Get-NetFirewallProfile -EA SilentlyContinue)
            $fi += $fw.Count
            $off = @($fw | Where-Object { -not $_.Enabled })
            if($off.Count -gt 0){ ThrAdd 'Securite' 'high' 'Pare-feu desactive' 'Pare-feu Windows' ("Profils inactifs : " + ($off.Name -join ', ')) }
        }catch{}
        try{
            $uac = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -EA SilentlyContinue).EnableLUA
            if($uac -ne 1){ ThrAdd 'Securite' 'high' 'Controle des comptes (UAC) desactive' 'UAC' 'Les programmes peuvent obtenir les droits administrateur sans vous demander' }
        }catch{}
    }

    2 {
        try{
            foreach($td in @(Get-MpThreatDetection -EA SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 30)){
                $fi++
                $tn = 'Menace detectee'
                try{ $ti = Get-MpThreat -ThreatID $td.ThreatID -EA SilentlyContinue | Select-Object -First 1; if($ti){ $tn = [string]$ti.ThreatName } }catch{}
                $tp = if($td.Resources){ [string](@($td.Resources)[0]) } else { 'Inconnu' }
                $tp = $tp -replace '^file:_',''
                $act = [string]$td.ThreatStatusID
                $sev = if($act -eq '2' -or $act -eq '3'){'medium'}else{'critical'}
                $st  = if($sev -eq 'medium'){'Menace deja neutralisee par Defender'}else{'Menace ACTIVE detectee par Windows Defender - action requise'}
                ThrAdd 'Malware' $sev $tn $tp "$st (detectee le $($td.InitialDetectionTime))" $true
            }
        }catch{}
    }

    3 {
        try{
            $mpc = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
            if(-not(Test-Path $mpc)){
                $plat = Get-ChildItem "$env:ProgramData\Microsoft\Windows Defender\Platform" -Directory -EA SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
                if($plat){ $mpc = Join-Path $plat.FullName 'MpCmdRun.exe' }
            }
            if($mpc -and (Test-Path $mpc)){
                [IO.File]::WriteAllText("$env:TEMP\optipc_defstart.txt",(Get-Date -Format 'o'),[Text.Encoding]::UTF8)
                $pp = Start-Process $mpc -ArgumentList '-Scan','-ScanType','1' -WindowStyle Hidden -PassThru -EA SilentlyContinue
                if($pp){ [IO.File]::WriteAllText("$env:TEMP\optipc_defpid.txt",[string]$pp.Id,[Text.Encoding]::UTF8) }
            }
        }catch{}
        Start-Sleep -Milliseconds 400
    }

    4 {
        $malN = @('xmrig','cryptominer','keylogger','remcos','njrat','asyncrat','darkcomet','mimikatz','cobaltstrike','quasar','nanocore','trickbot','emotet','azorult','redline','raccoon','vidar','lokibot','formbook','agenttesla','netwire','warzone','dcrat','venomrat','stealc','amadey','smokeloader','gh0st','plugx','blackmatter')
        $sysP = @{'svchost.exe'='c:\windows\system32\svchost.exe';'lsass.exe'='c:\windows\system32\lsass.exe';'explorer.exe'='c:\windows\explorer.exe';'csrss.exe'='c:\windows\system32\csrss.exe';'winlogon.exe'='c:\windows\system32\winlogon.exe';'services.exe'='c:\windows\system32\services.exe';'spoolsv.exe'='c:\windows\system32\spoolsv.exe';'taskhostw.exe'='c:\windows\system32\taskhostw.exe'}
        try{
            $procs = @(Get-Process -EA SilentlyContinue | Where-Object { $_.Id -gt 4 })
            $fi = $procs.Count
            $sigChecked = 0
            foreach($p in $procs){
                $nl = $p.ProcessName.ToLower()
                $pp = ''
                try{ $pp = [string]$p.Path }catch{}
                foreach($b in $malN){ if($nl -match [regex]::Escape($b)){ ThrAdd 'Malware' 'critical' "Virus actif : $($p.ProcessName)" $(if($pp){$pp}else{"PID $($p.Id)"}) 'Programme malveillant connu en cours d execution sur votre PC'; break } }
                if($sysP.ContainsKey("$nl.exe") -or $sysP.ContainsKey($nl)){
                    $expect = $sysP["$nl.exe"]; if(-not $expect){ $expect = $sysP[$nl] }
                    if($pp -and $expect -and $pp.ToLower() -ne $expect){
                        ThrAdd 'Rootkit' 'critical' "Usurpation de processus systeme : $($p.ProcessName)" $pp "Un programme se fait passer pour $($p.ProcessName) depuis un emplacement anormal"
                    }
                }
                if($pp -and $pp -match '\\AppData\\Local\\Temp\\|\\AppData\\Roaming\\[^\\]+\.exe$|\\Users\\Public\\|\\Windows\\Temp\\'){
                    if($sigChecked -lt 40){
                        $sigChecked++
                        $si = Get-SigInfo $pp
                        if(-not $si.valid -and -not (Test-TrustedVendor $pp)){
                            ThrAdd 'Suspect' 'high' "Programme non signe en execution : $($p.ProcessName)" $pp 'Lance depuis un dossier temporaire, sans signature numerique'
                        }
                    }
                }
            }
        }catch{}
    }

    5 {
        try{
            $seen = @{}
            $procs = @(Get-Process -EA SilentlyContinue | Where-Object { $_.Id -gt 4 } | Select-Object -First 90)
            foreach($p in $procs){
                $mods = @()
                try{ $mods = @($p.Modules | Select-Object -First 60) }catch{ continue }
                foreach($m in $mods){
                    $mp = [string]$m.FileName
                    if(-not $mp){ continue }
                    if($seen[$mp]){ continue }
                    $seen[$mp] = $true
                    $fi++
                    if($mp -match '\\AppData\\|\\Temp\\|\\Users\\Public\\|\\ProgramData\\'){
                        if(Test-TrustedVendor $mp){ continue }
                        $si = Get-SigInfo $mp
                        if(-not $si.valid){
                            ThrAdd 'DLL' 'high' "Bibliotheque non signee chargee : $($m.ModuleName)" $mp "Chargee par $($p.ProcessName) depuis un dossier utilisateur - technique de detournement de DLL"
                        }
                    }
                }
            }
        }catch{}
    }

    6 {
        try{
            $conns = @(Get-NetTCPConnection -State Established -EA SilentlyContinue)
            $fi = $conns.Count
            $lol = @('powershell','pwsh','cmd','wscript','cscript','mshta','regsvr32','rundll32','bitsadmin','certutil','msbuild','installutil','mshta')
            $minerPorts = @(3333,4444,5555,7777,8333,9999,14433,45700)
            foreach($c in $conns){
                $pr = Get-Process -Id $c.OwningProcess -EA SilentlyContinue
                if(-not $pr){ continue }
                $pn = $pr.ProcessName.ToLower()
                if(($lol -contains $pn) -and ($c.RemotePort -notin @(80,443,8080,8443,53))){
                    ThrAdd 'Reseau' 'high' "Connexion sortante anormale : $($pr.ProcessName)" "$($c.RemoteAddress):$($c.RemotePort)" 'Un outil systeme Windows communique avec un serveur externe sur un port inhabituel'
                }
                if($minerPorts -contains $c.RemotePort){
                    ThrAdd 'Miner' 'critical' "Connexion vers un pool de minage : $($pr.ProcessName)" "$($c.RemoteAddress):$($c.RemotePort)" 'Port utilise par les logiciels de minage de cryptomonnaie'
                }
            }
        }catch{}
    }

    7 {
        $runK = @(
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
        )
        foreach($rk in $runK){
            if(-not(Test-Path $rk -EA SilentlyContinue)){ continue }
            try{
                $pr = Get-ItemProperty $rk -EA SilentlyContinue
                if(-not $pr){ continue }
                $pr.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notmatch '^PS' } | ForEach-Object {
                    $fi++
                    $val = [string]$_.Value
                    if($val -match '(?i)(powershell|cmd\.exe|mshta|wscript|cscript|rundll32).*(-enc|frombase64|hidden|http)'){
                        ThrAdd 'Persistance' 'critical' "Commande cachee au demarrage : $($_.Name)" $val "Cle : $rk - Une commande masquee se lance a chaque demarrage" $false
                        return
                    }
                    $exe = $null
                    if($val -match '"([^"]+\.(exe|dll|vbs|bat|cmd|js|ps1|scr))"'){ $exe = $matches[1] }
                    elseif($val -match '([A-Za-z]:\\[^\s"]+\.(exe|dll|vbs|bat|cmd|js|ps1|scr))'){ $exe = $matches[1] }
                    if($exe -and $exe -match '\\Temp\\|\\AppData\\Roaming\\[^\\]+\.(exe|vbs|bat|js|scr)$|\\Users\\Public\\|\\AppData\\Local\\Temp\\'){
                        if(Test-TrustedVendor $exe){ return }
                        $si = Get-SigInfo $exe
                        if($si.valid){ return }
                        $sev = 'high'
                        ThrAdd 'Persistance' $sev "Demarrage automatique suspect : $($_.Name)" $exe "Cle : $rk - Programme lance au demarrage depuis un dossier temporaire" $true
                    }
                }
            }catch{}
        }
    }

    8 {
        try{
            $wl1 = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            $p = Get-ItemProperty $wl1 -EA SilentlyContinue
            $fi += 3
            if($p){
                if($p.Shell -and ([string]$p.Shell).ToLower().Trim() -ne 'explorer.exe'){
                    ThrAdd 'Persistance' 'critical' 'Shell Windows detourne' ([string]$p.Shell) 'Le programme lance a l ouverture de session a ete remplace'
                }
                if($p.Userinit -and ([string]$p.Userinit) -notmatch '(?i)^c:\\windows\\system32\\userinit\.exe,?\s*$'){
                    ThrAdd 'Persistance' 'critical' 'Userinit detourne' ([string]$p.Userinit) 'Un programme supplementaire se lance a l ouverture de session'
                }
            }
        }catch{}
        foreach($k in @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows')){
            try{
                $p = Get-ItemProperty $k -EA SilentlyContinue
                $fi++
                if($p -and $p.AppInit_DLLs -and ([string]$p.AppInit_DLLs).Trim()){
                    ThrAdd 'Persistance' 'critical' 'AppInit_DLLs actif' ([string]$p.AppInit_DLLs) 'Une DLL est injectee dans tous les programmes qui demarrent - technique de virus'
                }
            }catch{}
        }
        try{
            $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCertDlls'
            if(Test-Path $k){
                $p = Get-ItemProperty $k -EA SilentlyContinue
                $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                    ThrAdd 'Persistance' 'critical' "AppCertDll : $($_.Name)" ([string]$_.Value) 'DLL chargee dans chaque nouveau processus'
                }
            }
        }catch{}
    }

    9 {
        try{
            $tasks = @(Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '^\\Microsoft\\' })
            $fi = $tasks.Count
            foreach($t in $tasks){
                foreach($a in $t.Actions){
                    $exe = SafePath ([string]$a.Execute)
                    $arg = [string]$a.Arguments
                    if(-not $exe){ continue }
                    if("$exe $arg" -match '(?i)(-enc\s+[A-Za-z0-9+/]{30,}|FromBase64String|DownloadString|-w\s+hidden|-windowstyle\s+hidden)'){
                        ThrAdd 'Persistance' 'critical' "Tache planifiee malveillante : $($t.TaskName)" "$exe $arg" 'Execute une commande cachee ou encodee a intervalles reguliers' 
                        continue
                    }
                    if($exe -match '\\Temp\\|\\AppData\\|\\Users\\Public\\|\\ProgramData\\' -and -not (Test-TrustedVendor $exe)){
                        $si = Get-SigInfo $exe
                        if($si.valid){ continue }   # editeur identifie (Opera, Google...) : mise a jour normale
                        $sev = 'high'
                        ThrAdd 'Persistance' $sev "Tache planifiee suspecte : $($t.TaskName)" $exe "Programme lance automatiquement depuis $(Split-Path $exe -Parent)" $true
                    }
                }
            }
        }catch{}
    }

    10 {
        try{
            $svcs = @(Get-WmiObject Win32_Service -EA SilentlyContinue | Where-Object { $_.PathName })
            $fi = $svcs.Count
            $checked = 0
            foreach($s in $svcs){
                $sp = SafePath ([string]$s.PathName)
                $spFile = $sp
                if($spFile -match '^([A-Za-z]:\\[^\s]+\.exe)'){ $spFile = $matches[1] }
                if($sp -match '\\Temp\\|\\AppData\\|\\Users\\Public\\'){
                    ThrAdd 'Service' 'high' "Service installe dans un dossier utilisateur : $($s.Name)" $sp 'Les services legitimes ne s installent jamais dans AppData ou Temp'
                    continue
                }
                # Seul le chemin de l'EXECUTABLE compte (pas les arguments) : "C:\Windows\system32\svchost.exe -k netsvcs"
                # n'est PAS une faille. Avant, chaque service svchost etait signale (des centaines de fausses alertes).
                $__pn = ([string]$s.PathName).Trim()
                $__exe = if($__pn -match '^([A-Za-z]:\\.*?\.exe)'){ $matches[1] } else { '' }
                if($__exe -and $__pn -notmatch '^"' -and $__exe -match '\s' -and $__exe -notmatch '(?i)^[A-Za-z]:\\Windows\\'){
                    ThrAdd 'Service' 'low' "Chemin de service non protege : $($s.Name)" $sp 'Chemin contenant des espaces sans guillemets (faille d elevation de privileges)'
                }
                if($s.State -eq 'Running' -and $checked -lt 45 -and (Test-Path $spFile -EA SilentlyContinue)){
                    $checked++
                    if(Test-TrustedVendor $spFile){ continue }
                    $si = Get-SigInfo $spFile
                    if($si.status -eq 'HashMismatch'){
                        ThrAdd 'Service' 'critical' "Service modifie : $($s.Name)" $spFile 'Le fichier du service ne correspond plus a sa signature numerique'
                    } elseif(-not $si.valid -and -not $s.Description){
                        ThrAdd 'Service' 'medium' "Service non signe : $($s.Name)" $spFile 'Service sans signature numerique ni description'
                    }
                }
            }
        }catch{}
    }

    11 {
        try{
            foreach($f in @(Get-WmiObject -Namespace root\subscription -Class __EventFilter -EA SilentlyContinue)){
                $fi++
                ThrAdd 'Rootkit' 'critical' "Persistance WMI : $($f.Name)" 'WMI __EventFilter' "Mecanisme de demarrage furtif (MITRE T1546.003). Requete : $($f.Query)"
            }
            foreach($c in @(Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -EA SilentlyContinue)){
                $fi++
                ThrAdd 'Rootkit' 'critical' "Execution WMI : $($c.Name)" 'WMI CommandLineEventConsumer' "Commande executee automatiquement : $($c.CommandLineTemplate)"
            }
            foreach($c in @(Get-WmiObject -Namespace root\subscription -Class ActiveScriptEventConsumer -EA SilentlyContinue)){
                $fi++
                ThrAdd 'Rootkit' 'critical' "Script WMI : $($c.Name)" 'WMI ActiveScriptEventConsumer' 'Script execute automatiquement par WMI'
            }
        }catch{}
    }

    12 {
        try{
            foreach($base in @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options')){
                if(-not(Test-Path $base)){ continue }
                foreach($k in (Get-ChildItem $base -EA SilentlyContinue)){
                    $fi++
                    $d = Get-ItemProperty $k.PSPath -Name Debugger -EA SilentlyContinue
                    if($d -and $d.Debugger -and ([string]$d.Debugger) -notmatch '(?i)vsjitdebugger|drwtsn32|windbg|ntsd|AeDebug'){
                        ThrAdd 'Rootkit' 'critical' "Detournement IFEO : $($k.PSChildName)" ([string]$d.Debugger) "Chaque lancement de $($k.PSChildName) declenche un autre programme"
                    }
                    $g = Get-ItemProperty $k.PSPath -Name GlobalFlag -EA SilentlyContinue
                    if($g -and $g.GlobalFlag -eq 512){
                        ThrAdd 'Rootkit' 'high' "Surveillance de sortie de processus : $($k.PSChildName)" ([string]$k.PSPath) 'Technique SilentProcessExit utilisee pour la persistance'
                    }
                }
            }
        }catch{}
    }

    13 {
        try{
            $base = 'HKCU:\SOFTWARE\Classes\CLSID'
            if(Test-Path $base){
                foreach($k in (Get-ChildItem $base -EA SilentlyContinue | Select-Object -First 400)){
                    $fi++
                    $ip = Join-Path $k.PSPath 'InprocServer32'
                    if(-not(Test-Path $ip -EA SilentlyContinue)){ continue }
                    $v = (Get-ItemProperty $ip -EA SilentlyContinue).'(default)'
                    if(-not $v){ continue }
                    $v = SafePath ([string]$v)
                    if($v -match '\\AppData\\|\\Temp\\|\\ProgramData\\|\\Users\\Public\\'){
                        ThrAdd 'Rootkit' 'high' "Detournement COM : $($k.PSChildName)" $v 'Un composant Windows a ete remplace par une DLL situee dans un dossier utilisateur'
                    }
                }
            }
        }catch{}
    }

    14 {
        $prefs = @(
            @{n='Chrome'; p="$env:LOCALAPPDATA\Google\Chrome\User Data\Default"},
            @{n='Edge';   p="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"},
            @{n='Brave';  p="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"}
        )
        foreach($b in $prefs){
            $pf = Join-Path $b.p 'Preferences'
            if(-not(Test-Path $pf)){ continue }
            $fi++
            try{
                $j = [IO.File]::ReadAllText($pf) | ConvertFrom-Json
                $hp = [string]$j.homepage
                if($hp -and $hp.Length -gt 5 -and $hp -notmatch '(?i)google|bing|duckduckgo|yahoo|qwant|ecosia|startpage|about:|newtab|msn\.com'){
                    ThrAdd 'Navigateur' 'high' "Page d accueil $($b.n) detournee" $hp 'Votre page de demarrage a ete modifiee par un programme tiers'
                }
                if($j.session -and $j.session.startup_urls){
                    foreach($u in @($j.session.startup_urls)){
                        if($u -and $u -notmatch '(?i)google|bing|duckduckgo|yahoo|qwant|ecosia|msn\.com'){
                            ThrAdd 'Navigateur' 'medium' "Site force au demarrage de $($b.n)" ([string]$u) 'Ce site s ouvre automatiquement a chaque lancement du navigateur'
                        }
                    }
                }
            }catch{}
            $ed = Join-Path $b.p 'Extensions'
            if(Test-Path $ed){
                foreach($e in (Get-ChildItem $ed -Directory -EA SilentlyContinue)){
                    $fi++
                    $mf = Get-ChildItem $e.FullName -Recurse -Filter 'manifest.json' -EA SilentlyContinue | Select-Object -First 1
                    if(-not $mf){ continue }
                    try{
                        $mj = [IO.File]::ReadAllText($mf.FullName) | ConvertFrom-Json
                        $perms = @($mj.permissions) + @($mj.host_permissions)
                        $risky = @($perms | Where-Object { $_ -match '(?i)<all_urls>|\*://\*/\*|webRequestBlocking|proxy|debugger|nativeMessaging' })
                        if($risky.Count -ge 2){
                            $nm = [string]$mj.name
                            if($nm -match '^__MSG') { $nm = $e.Name }
                            ThrAdd 'Navigateur' 'medium' "Extension $($b.n) a droits eleves : $nm" $e.FullName ("Autorisations sensibles : " + (($risky | Select-Object -First 3) -join ', ') + ". Supprimez-la si vous ne la connaissez pas")
                        }
                    }catch{}
                }
            }
        }
    }

    15 {
        foreach($d in @("$env:USERPROFILE\Desktop","$env:PUBLIC\Desktop","$env:APPDATA\Microsoft\Windows\Start Menu\Programs","$env:APPDATA\Microsoft\Internet Explorer\Quick Launch")){
            if(-not(Test-Path $d)){ continue }
            try{
                $sh = New-Object -ComObject WScript.Shell
                foreach($l in (Get-ChildItem $d -Recurse -Filter '*.lnk' -EA SilentlyContinue | Select-Object -First 150)){
                    $fi++
                    try{
                        $sc = $sh.CreateShortcut($l.FullName)
                        $tg = [string]$sc.TargetPath
                        $ar = [string]$sc.Arguments
                        if($tg -match '(?i)(chrome|msedge|firefox|brave|opera)\.exe$' -and $ar -match '(?i)https?://'){
                            ThrAdd 'Navigateur' 'high' "Raccourci navigateur detourne : $($l.BaseName)" "$tg $ar" 'Ce raccourci force l ouverture d un site web au lancement du navigateur (adware)'
                        }
                        if($ar -match '(?i)(-enc\s+[A-Za-z0-9+/]{20,}|FromBase64String|mshta\s+http|-w\s+hidden)'){
                            ThrAdd 'Malware' 'critical' "Raccourci piege : $($l.BaseName)" "$tg $ar" 'Le raccourci execute une commande cachee'
                        }
                    }catch{}
                }
            }catch{}
        }
    }

    16 {
        try{
            $hf = "$env:SystemRoot\System32\drivers\etc\hosts"
            $lines = @(Get-Content $hf -EA SilentlyContinue | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' })
            $fi += $lines.Count
            $block = @(); $redir = @(); $secBlocked = @()
            foreach($l in $lines){
                if($l -match '^\s*([0-9a-fA-F\.:]+)\s+(\S+)'){
                    $ip = $matches[1]; $host2 = $matches[2]
                    if($ip -match '^(0\.0\.0\.0|127\.0\.0\.1|::1|::)$'){
                        # Seuls les serveurs de MISE A JOUR DE SECURITE comptent. Les listes anti-pub /
                        # anti-telemetrie (vortex.data.microsoft.com, telemetry...) sont courantes et sans danger.
                        if($host2 -match '(?i)(windowsupdate|update\.microsoft|download\.microsoft|definitionupdates|wdcp\.microsoft|wdcpalt|smartscreen|security\.microsoft|update\.(kaspersky|avast|avg|eset|bitdefender|norton|mcafee|malwarebytes|avira)|(kaspersky|avast|eset|bitdefender|norton|mcafee|malwarebytes|avira)\.(com|net)$)' -and $host2 -notmatch '(?i)(telemetry|vortex|watson|data\.microsoft|settings-win|feedback|(^|\.)ads?\.)'){
                            $secBlocked += $host2
                        } else { $block += $l }
                    } elseif($host2 -ne 'localhost'){ $redir += $l }
                }
            }
            if($secBlocked.Count -gt 0){
                ThrAdd 'Reseau' 'critical' "Mises a jour de securite bloquees ($($secBlocked.Count))" $hf ("Le fichier Hosts empeche votre PC de contacter les serveurs de securite : " + (($secBlocked | Select-Object -First 3) -join ', '))
            }
            if($redir.Count -gt 0){
                ThrAdd 'Reseau' 'high' "Redirections DNS dans le fichier Hosts ($($redir.Count))" $hf ("Des sites sont rediriges vers d autres serveurs. Exemple : " + ($redir[0]))
            }
        }catch{}
        try{
            $ps = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
            $p = Get-ItemProperty $ps -EA SilentlyContinue
            $fi++
            if($p -and $p.ProxyEnable -eq 1 -and $p.ProxyServer){
                ThrAdd 'Reseau' 'high' "Proxy actif : $($p.ProxyServer)" $ps 'Tout votre trafic internet passe par ce serveur. Si vous ne l avez pas configure, il s agit probablement d un detournement'
            }
            if($p -and $p.AutoConfigURL){
                ThrAdd 'Reseau' 'critical' "Script de proxy automatique : $($p.AutoConfigURL)" $ps 'Un fichier distant controle vos connexions internet (technique de vol de donnees bancaires)'
            }
        }catch{}
        try{
            foreach($n in @(Get-DnsClientServerAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.ServerAddresses })){
                $fi++
                foreach($s in $n.ServerAddresses){
                    if($s -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.)'){ continue }
                    if($s -notmatch '^(8\.8\.|8\.8\.4\.4|1\.1\.1\.1|1\.0\.0\.1|9\.9\.9\.9|208\.67\.|149\.112\.|94\.140\.|80\.67\.|80\.10\.|212\.27\.)'){
                        ThrAdd 'Reseau' 'medium' "Serveur DNS inhabituel : $s" "Interface $($n.InterfaceAlias)" 'Un serveur DNS non standard est configure. Il peut rediriger vos sites vers de fausses pages'
                    }
                }
            }
        }catch{}
    }

    17 {
        try{
            $since = (Get-Date).AddDays(-180)
            foreach($c in @(Get-ChildItem Cert:\LocalMachine\Root -EA SilentlyContinue)){
                $fi++
                if($c.NotBefore -lt $since){ continue }
                if($c.Subject -match '(?i)Microsoft|VeriSign|DigiCert|GlobalSign|Comodo|Sectigo|Thawte|GeoTrust|Baltimore|Entrust|Go Daddy|Certum|Let.s Encrypt|ISRG|USERTrust|AAA Certificate|Starfield|Amazon|Google Trust'){ continue }
                ThrAdd 'Certificat' 'high' "Certificat racine recent non reconnu" ([string]$c.Subject) "Installe le $($c.NotBefore.ToString('dd/MM/yyyy')). Un certificat racine permet d intercepter vos connexions securisees (banque, e-mail)"
            }
        }catch{}
    }

    18 { $r = Invoke-DeepFolderScan @("$env:USERPROFILE\Downloads","$env:USERPROFILE\Telechargements") 4000 6 120 'Telechargements'
         foreach($t in $r.threats){ [void]$thr.Add($t) }; $fi = $r.files }

    19 { $r = Invoke-DeepFolderScan @("$env:USERPROFILE\Desktop","$env:USERPROFILE\Documents","$env:USERPROFILE\Bureau") 6000 6 120 'Bureau'
         foreach($t in $r.threats){ [void]$thr.Add($t) }; $fi = $r.files }

    20 { $r = Invoke-DeepFolderScan @("$env:APPDATA") 8000 4 150 'AppData Roaming'
         foreach($t in $r.threats){ [void]$thr.Add($t) }; $fi = $r.files }

    21 { $r = Invoke-DeepFolderScan @("$env:LOCALAPPDATA") 9000 3 150 'AppData Local'
         foreach($t in $r.threats){ [void]$thr.Add($t) }; $fi = $r.files }

    22 { $r = Invoke-DeepFolderScan @("$env:TEMP","$env:SystemRoot\Temp") 6000 4 100 'Temporaires'
         foreach($t in $r.threats){ [void]$thr.Add($t) }; $fi = $r.files }

    23 { $r = Invoke-DeepFolderScan @("$env:ProgramData","$env:PUBLIC") 6000 4 120 'ProgramData'
         foreach($t in $r.threats){ [void]$thr.Add($t) }; $fi = $r.files }

    24 { $r = Invoke-ScriptScan @("$env:USERPROFILE\Downloads","$env:APPDATA","$env:LOCALAPPDATA\Temp","$env:ProgramData","$env:PUBLIC","$env:USERPROFILE\Desktop") 600
         foreach($t in $r.threats){ [void]$thr.Add($t) }; $fi = $r.files }

    25 {
        $mN = @('xmrig','ethminer','cpuminer','cgminer','bfgminer','minerd','nheqminer','claymore','phoenixminer','t-rex','gminer','nbminer','teamredminer','lolminer','srbminer','xmr-stak','nicehash','trexminer')
        try{
            foreach($p in (Get-Process -EA SilentlyContinue)){
                $fi++
                $n = $p.ProcessName.ToLower()
                foreach($m in $mN){ if($n -match [regex]::Escape($m)){ $pp=''; try{$pp=[string]$p.Path}catch{}; ThrAdd 'Miner' 'critical' "Mineur de cryptomonnaie : $($p.ProcessName)" $(if($pp){$pp}else{"PID $($p.Id)"}) 'Votre PC est utilise pour miner de la cryptomonnaie : surchauffe, lenteurs et facture d electricite'; break } }
            }
        }catch{}
        try{
            foreach($cfg in (Get-ChildItem "$env:APPDATA","$env:LOCALAPPDATA","$env:ProgramData" -Recurse -Depth 3 -Filter 'config.json' -File -EA SilentlyContinue | Select-Object -First 60)){
                $fi++
                $t = ''
                try{ $t = [IO.File]::ReadAllText($cfg.FullName) }catch{ continue }
                if($t -match '(?i)"(pools|algo|randomx|stratum)"' -and $t -match '(?i)stratum\+tcp'){
                    ThrAdd 'Miner' 'critical' "Configuration de minage detectee" $cfg.FullName 'Fichier de configuration d un logiciel de minage de cryptomonnaie' $true
                }
            }
        }catch{}
    }

    26 {
        try{
            $sE = @('.locked','.encrypted','.crypt','.locky','.cerber','.zepto','.thor','.aaa','.vvv','.micro','.wncry','.wcry','.djvu','.stop','.phobos','.makop','.mallox','.basta')
            $enc = @(Get-ChildItem "$env:USERPROFILE" -Recurse -File -Force -EA SilentlyContinue -Depth 4 | Where-Object { $sE -contains $_.Extension.ToLower() } | Select-Object -First 8)
            $fi += 200
            foreach($e in $enc){ ThrAdd 'Ransomware' 'critical' "Fichier chiffre : $($e.Name)" $e.FullName 'Extension utilisee par les rancongiciels. NE PAYEZ PAS - deconnectez le PC d internet et faites appel a un professionnel' }
            foreach($rn in @('DECRYPT','README_','HOW_TO_DECRYPT','YOUR_FILES','RESTORE_FILES','_readme.txt')){
                foreach($f in (Get-ChildItem "$env:USERPROFILE" -Filter "*$rn*" -File -EA SilentlyContinue -Depth 3 | Select-Object -First 2)){
                    $fi++
                    ThrAdd 'Ransomware' 'critical' "Note de rancon : $($f.Name)" $f.FullName 'Message laisse par un rancongiciel'
                }
            }
            $sh = (vssadmin list shadows 2>&1 | Out-String)
            if($sh -match '(?i)Aucun|No items found'){
                ThrAdd 'Ransomware' 'low' 'Aucun point de restauration disponible' 'Copies fantomes (VSS)' 'Vous ne pourrez pas restaurer vos fichiers en cas de probleme. Activez la protection du systeme'
            }
        }catch{}
    }

    27 {
        try{
            $wmiP = @(Get-WmiObject Win32_Process -EA SilentlyContinue | Select-Object -ExpandProperty ProcessId)
            $psP  = @(Get-Process -EA SilentlyContinue | Select-Object -ExpandProperty Id)
            $fi   = $wmiP.Count
            foreach($h in @($psP | Where-Object { $_ -notin $wmiP -and $_ -gt 4 } | Select-Object -First 4)){
                ThrAdd 'Rootkit' 'critical' "Processus masque : PID $h" "PID $h" 'Ce processus se cache des outils Windows : indicateur fort de rootkit'
            }
        }catch{}
        try{
            $drv = @(Get-CimInstance Win32_SystemDriver -EA SilentlyContinue | Where-Object { $_.State -eq 'Running' })
            $fi += $drv.Count
            $ck = 0
            foreach($d in $drv){
                $p = SafePath ([string]$d.PathName)
                if(-not $p){ continue }
                if($p -match '\\AppData\\|\\Temp\\|\\Users\\'){
                    ThrAdd 'Rootkit' 'critical' "Pilote charge depuis un dossier utilisateur : $($d.Name)" $p 'Les pilotes fonctionnent au coeur de Windows. Un pilote installe dans un dossier utilisateur est tres anormal'
                    continue
                }
                if($ck -lt 30 -and (Test-Path $p -EA SilentlyContinue)){
                    $ck++
                    if(Test-TrustedVendor $p){ continue }
                    $si = Get-SigInfo $p
                    if(-not $si.valid){ ThrAdd 'Rootkit' 'high' "Pilote non signe : $($d.Name)" $p 'Pilote systeme sans signature numerique valide' }
                }
            }
        }catch{}
    }

    28 {
        $pupL = @('AnyTech365','PC Optimizer Pro','RegClean Pro','Driver Booster','Driver Easy','Smart Driver','MySearchDial','Conduit','Search Protect','Babylon','Delta Search','Sweetpacks','iLivid','Yontoo','Optimizer Pro','DriverUpdate','SlimDrivers','DriverReviver','PC SpeedScan','Registry Mechanic','Advanced SystemCare','IObit','BrowseFox','WebSaver','SaveSense','Wajam','Mindspark','OneSafe','Reimage','Restoro','PC Repair','MacKeeper','Segurazo','Total AV','Wondershare Driver','Auslogics','WinZip Driver','Systweak','PCProtect','SpyHunter','Ashampoo WinOptimizer','MyPCBackup','Weknow','Bytefence','Cheetah Mobile','Baidu','Hao123','Yandex Browser')
        foreach($rp in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')){
            if(-not(Test-Path $rp)){ continue }
            try{
                foreach($k in (Get-ChildItem $rp -EA SilentlyContinue)){
                    $fi++
                    $pr = Get-ItemProperty $k.PSPath -EA SilentlyContinue
                    if(-not $pr -or -not $pr.DisplayName){ continue }
                    foreach($pu in $pupL){
                        if([string]$pr.DisplayName -match [regex]::Escape($pu)){
                            ThrAdd 'PUP' 'medium' "Logiciel indesirable : $($pr.DisplayName)" ([string]$k.PSPath) "Programme connu pour ralentir le PC, afficher des publicites ou reclamer un abonnement inutile (version $($pr.DisplayVersion)). Desinstallez-le depuis l onglet Mes applications"
                            break
                        }
                    }
                }
            }catch{}
        }
    }

    29 {
        try{
            foreach($u in @(Get-LocalUser -EA SilentlyContinue)){
                $fi++
                if($u.Name -match '(?i)^(Guest|Invite)$' -and $u.Enabled){
                    ThrAdd 'Compte' 'medium' 'Compte Invite active' "Utilisateur $($u.Name)" 'Le compte Invite permet un acces sans mot de passe. Il devrait rester desactive'
                }
            }
            $admins = @(Get-LocalGroupMember -Group 'Administrateurs' -EA SilentlyContinue)
            if(-not $admins){ $admins = @(Get-LocalGroupMember -Group 'Administrators' -EA SilentlyContinue) }
            $fi += $admins.Count
            if($admins.Count -gt 3){
                ThrAdd 'Compte' 'low' "$($admins.Count) comptes administrateurs" 'Groupe Administrateurs' ("Verifiez cette liste : " + (($admins | ForEach-Object { $_.Name }) -join ', '))
            }
        }catch{}
        try{
            $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -EA SilentlyContinue).fDenyTSConnections
            $fi++
            if($rdp -eq 0){
                ThrAdd 'Reseau' 'high' 'Bureau a distance (RDP) active' 'Terminal Server' 'Votre PC accepte les connexions a distance. Desactivez-le si vous ne l utilisez pas : c est une porte d entree frequente'
            }
        }catch{}
        try{
            foreach($s in @(Get-SmbShare -EA SilentlyContinue | Where-Object { $_.Name -notmatch '\$$' })){
                $fi++
                ThrAdd 'Reseau' 'low' "Dossier partage sur le reseau : $($s.Name)" ([string]$s.Path) 'Ce dossier est accessible depuis le reseau local'
            }
        }catch{}
    }

    30 {
        $since = (Get-Date).AddDays(-21)
        try{
            foreach($e in @(Get-WinEvent -FilterHashtable @{LogName='System';Id=7045;StartTime=$since} -MaxEvents 40 -EA SilentlyContinue)){
                $fi++
                $m = [string]$e.Message
                if($m -match '(?i)(\\Temp\\|\\AppData\\|powershell|cmd\.exe\s+/c|-enc\s)'){
                    ThrAdd 'Persistance' 'high' 'Service installe recemment de maniere suspecte' 'Journal System (7045)' (($m -split "`n" | Select-Object -First 3) -join ' ')
                }
            }
        }catch{}
        try{
            foreach($e in @(Get-WinEvent -FilterHashtable @{LogName='Security';Id=4720;StartTime=$since} -MaxEvents 20 -EA SilentlyContinue)){
                $fi++
                ThrAdd 'Compte' 'medium' 'Nouveau compte utilisateur cree recemment' 'Journal Security (4720)' ("Cree le $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm')). Si vous n en etes pas a l origine, c est alarmant")
            }
            foreach($e in @(Get-WinEvent -FilterHashtable @{LogName='Security';Id=1102;StartTime=$since} -MaxEvents 5 -EA SilentlyContinue)){
                $fi++
                ThrAdd 'Securite' 'high' 'Journal de securite efface' 'Journal Security (1102)' ("Efface le $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm')) : technique employee pour effacer les traces d une intrusion")
            }
        }catch{}
    }

    31 {
        $startFile = "$env:TEMP\optipc_defstart.txt"
        $pidFile   = "$env:TEMP\optipc_defpid.txt"
        $started = $null
        try{ if(Test-Path $startFile){ $started = [datetime]::Parse([IO.File]::ReadAllText($startFile,[Text.Encoding]::UTF8)) } }catch{}
        try{
            if(Test-Path $pidFile){
                $dp = [int]([IO.File]::ReadAllText($pidFile,[Text.Encoding]::UTF8))
                $w = 0
                while($w -lt 180000){
                    $pr = Get-Process -Id $dp -EA SilentlyContinue
                    if(-not $pr){ break }
                    Start-Sleep -Milliseconds 1000
                    $w += 1000
                    $fi += 40
                }
                Remove-Item $pidFile -Force -EA SilentlyContinue
            }
        }catch{}
        try{
            foreach($td in @(Get-MpThreatDetection -EA SilentlyContinue | Sort-Object InitialDetectionTime -Descending | Select-Object -First 20)){
                if($started -and $td.InitialDetectionTime -lt $started){ continue }
                $tn = 'Menace detectee par Defender'
                try{ $ti = Get-MpThreat -ThreatID $td.ThreatID -EA SilentlyContinue | Select-Object -First 1; if($ti){ $tn = [string]$ti.ThreatName } }catch{}
                $tp = if($td.Resources){ ([string](@($td.Resources)[0])) -replace '^file:_','' } else { 'Inconnu' }
                ThrAdd 'Malware' 'critical' "Windows Defender : $tn" $tp 'Detectee par le moteur antivirus officiel de Microsoft pendant cette analyse' $true
            }
        }catch{}
    }

    32 { Start-Sleep -Milliseconds 250 }

    }
    return @{threats=@($thr);files=$fi}
}

function Step-ScanPoll {
    try {
        if(Test-Path (Get-ScanStopFlag)){
            foreach($f in @((Get-ScanStateFile),(Get-ScanResultFile),(Get-ScanStopFlag))){
                try{ Remove-Item $f -Force -EA SilentlyContinue }catch{}
            }
            return @{done=$true;cancelled=$true;score=0;threats=@();files=0;phases=0;duration='0s';critical=0;high=0}
        }
        $SF = Get-ScanStateFile
        $RF = Get-ScanResultFile
        if(Test-Path $RF){
            try{
                $j = [System.IO.File]::ReadAllText($RF,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
                if($j -and $null -ne $j.Score){
                    $__wl = @(Get-WhiteList)
                    $th = @($j.Menaces | Where-Object { $_ -and -not (Test-OptiIgnored $_ $__wl) } | ForEach-Object { @{cat=[string]$_.cat;sev=[string]$_.sev;name=[string]$_.name;path=[string]$_.path;detail=[string]$_.detail;canDel=[bool]$_.canDel} })
                    return @{done=$true;score=(Get-OptiThreatScore $th);threats=$th;files=[int]$j.Files;phases=[int]$j.Phases;duration=[string]$j.Duree;critical=[int]$j.Critical;high=[int]$j.High}
                }
            }catch{}
        }
        if(-not(Test-Path $SF)){
            return @{done=$false;running=$true;phase=0;total=15;phaseName='Initialisation...';log=@();threats=0;files=0;nostate=$true}
        }
        $state = [System.IO.File]::ReadAllText($SF,[System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if(-not $state){ return @{done=$false;running=$true;phase=0;total=15;phaseName='Initialisation...';log=@();threats=0;files=0} }

        $mode = [string]$state.mode
        $plan = Get-ScanPlan $mode
        $tot  = $plan.Count
        $next = [int]$state.phase + 1
        if($next -gt $tot){ $next = $tot }
        $def  = $plan[$next-1]
        $pName = [string]$def.name

        # Une phase qui echoue ne doit PAS figer l'analyse a 0 % : on note
        # l'erreur dans le journal et on passe a la phase suivante.
        $result = $null
        try {
            $result = Invoke-ScanPhase ([int]$def.id)
        } catch {
            try {
                $__ld = "$env:LOCALAPPDATA\OptiPC"
                if(-not(Test-Path $__ld)){ [System.IO.Directory]::CreateDirectory($__ld) | Out-Null }
                [System.IO.File]::AppendAllText("$__ld\errors.log",
                    ("[{0}] PHASE {1} ({2}) : {3}`r`n" -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), [int]$def.id, $pName, $_.Exception.Message),
                    [Text.Encoding]::UTF8)
            } catch {}
        }
        if($null -eq $result){ $result = @{threats=@();files=0} }
        if($null -eq $result.threats){ $result = @{threats=@();files=[int]$result.files} }

        $allThr = New-Object System.Collections.ArrayList
        if($state.threats -and $state.threats -ne '[]'){
            try{
                $ex = $state.threats | ConvertFrom-Json
                foreach($t in @($ex)){ if($t){ [void]$allThr.Add(@{cat=[string]$t.cat;sev=[string]$t.sev;name=[string]$t.name;path=[string]$t.path;detail=[string]$t.detail;canDel=[bool]$t.canDel}) } }
            }catch{}
        }
        foreach($t in $result.threats){
            $dup = $false
            foreach($e in $allThr){ if($e.name -eq $t.name -and $e.path -eq $t.path){ $dup = $true; break } }
            if(-not $dup){ [void]$allThr.Add($t) }
        }
        $allFiles = [int]$state.files + [int]$result.files

        $logArr = New-Object System.Collections.ArrayList
        if($state.log -and $state.log -ne '[]'){
            try{ foreach($l in @($state.log | ConvertFrom-Json)){ [void]$logArr.Add([string]$l) } }catch{}
        }
        if(-not $logArr.Contains($pName)){ [void]$logArr.Add($pName) }

        if($next -ge $tot){
            $__wl = @(Get-WhiteList)
            $__kept = New-Object System.Collections.ArrayList
            foreach($t in $allThr){ if(-not (Test-OptiIgnored $t $__wl)){ [void]$__kept.Add($t) } }
            $allThr = $__kept
            $score = Get-OptiThreatScore $allThr
            $dur = '{0:mm}m{0:ss}s' -f ((Get-Date) - ([datetime]::Parse([string]$state.start)))
            $rep = @{
                Score=$score; Files=$allFiles; Phases=$tot; Duree=$dur; Menaces=@($allThr)
                Critical=([int]@($allThr | Where-Object { $_.sev -eq 'critical' }).Count)
                High=([int]@($allThr | Where-Object { $_.sev -eq 'high' }).Count)
            }
            try{ $rep | ConvertTo-Json -Depth 6 -Compress | Out-File $RF -Encoding UTF8 -Force }catch{}
            $th = @($allThr | ForEach-Object { @{cat=[string]$_.cat;sev=[string]$_.sev;name=[string]$_.name;path=[string]$_.path;detail=[string]$_.detail;canDel=[bool]$_.canDel} })
            return @{done=$true;score=$score;threats=$th;files=$allFiles;phases=$tot;duration=$dur;critical=[int]$rep.Critical;high=[int]$rep.High}
        }

        $newSt = @{
            phase=$next; total=$tot; mode=$mode
            threats=($allThr | ConvertTo-Json -Compress -Depth 4)
            log=($logArr | ConvertTo-Json -Compress)
            files=$allFiles; start=[string]$state.start
        }
        try{ $newSt | ConvertTo-Json -Compress | Out-File $SF -Encoding UTF8 -Force }catch{}
        return @{done=$false;running=$true;phase=$next;total=$tot;phaseName=$pName;log=@($logArr);threats=$allThr.Count;files=$allFiles}
    }catch{
        # Avant : on renvoyait phase=0, donc la barre restait bloquee a 0 %
        # indefiniment et l'erreur reelle n'apparaissait nulle part.
        # Desormais on journalise, on conserve la progression et on avance.
        $__msg = $_.Exception.Message
        try {
            $__ld = "$env:LOCALAPPDATA\OptiPC"
            if(-not(Test-Path $__ld)){ [System.IO.Directory]::CreateDirectory($__ld) | Out-Null }
            [System.IO.File]::AppendAllText("$__ld\errors.log",
                ("[{0}] SCAN POLL : {1}`r`n" -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), $__msg),
                [Text.Encoding]::UTF8)
        } catch {}
        $__ph = 0; $__tt = 15
        $__sf = Get-ScanStateFile
        try {
            $__sx = [System.IO.File]::ReadAllText($__sf,[Text.Encoding]::UTF8) | ConvertFrom-Json
            $__ph = [int]$__sx.phase; $__tt = [int]$__sx.total
            if($__tt -lt 1){ $__tt = 15 }
            # On fait avancer d'une phase pour ne jamais rester bloque.
            $__sx.phase = [Math]::Min($__ph + 1, $__tt)
            $__sx | ConvertTo-Json -Compress | Out-File $__sf -Encoding UTF8 -Force
            $__ph = [int]$__sx.phase
        } catch {}
        return @{done=$false;running=$true;phase=$__ph;total=$__tt;phaseName='Analyse en cours...';log=@();threats=0;files=0;err=$__msg}
    }
}

function Get-VirtMemInfo {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -EA Stop
        $pf = Get-CimInstance Win32_PageFileUsage -EA SilentlyContinue | Select-Object -First 1
        if ($pf) {
            return @{
                totalMB = [int]$pf.AllocatedBaseSize
                usedMB  = [int]$pf.CurrentUsage
                path    = [string]$pf.Name
                auto    = $false
            }
        }
        return @{totalMB=0;usedMB=0;path='Automatique';auto=$true}
    } catch {
        return @{totalMB=0;usedMB=0;path='Inconnu';auto=$true}
    }
}

function Get-OptiCacheFile($name){ "$env:TEMP\optipc_cache_$name.json" }
function Get-OptiCache($name,$maxAgeSec){
    try{
        $f = Get-OptiCacheFile $name
        if(-not(Test-Path $f)){ return $null }
        $o = [IO.File]::ReadAllText($f,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if(-not $o -or -not $o.ts){ return $null }
        if(((Get-Date) - [datetime]::Parse($o.ts)).TotalSeconds -lt $maxAgeSec){ return $o.data }
    }catch{}
    $null
}
function Set-OptiCache($name,$data){
    try{
        $f = Get-OptiCacheFile $name
        $tmp = "$f.tmp$(Get-Random)"
        (@{ts=(Get-Date -Format 'o');data=$data} | ConvertTo-Json -Depth 10 -Compress) | Out-File $tmp -Encoding UTF8 -Force
        Move-Item $tmp $f -Force -EA SilentlyContinue
        if(Test-Path $tmp){ Remove-Item $tmp -Force -EA SilentlyContinue }
    }catch{}
}

function Initialize-OptiPerf {
    # Mesure directe par le noyau Windows (GlobalMemoryStatusEx / GetSystemTimes).
    # Avant : deux requetes WMI a chaque rafraichissement. Sur un PC lent, WMI
    # (processus WmiPrvSE) se mettait a consommer lui-meme du processeur, et
    # le graphique mesurait... la charge provoquee par la mesure.
    if('OptiPerf' -as [type]){ return $true }
    try{
        Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class OptiPerf {
  [StructLayout(LayoutKind.Sequential)] public class MEMSTAT {
    public uint dwLength = (uint)Marshal.SizeOf(typeof(MEMSTAT)); public uint dwMemoryLoad;
    public ulong ullTotalPhys; public ulong ullAvailPhys; public ulong ullTotalPageFile; public ulong ullAvailPageFile;
    public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual; }
  [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MEMSTAT m);
  [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
  static long _i, _k, _u; static int _last; static readonly object _lk = new object();
  public static ulong[] Mem(){ var m = new MEMSTAT(); GlobalMemoryStatusEx(m); return new ulong[]{ m.ullTotalPhys, m.ullAvailPhys }; }
  static long _sp; static long _st; static int _slast;
  public static int SelfCpu(){
    lock(_lk){
      var p = System.Diagnostics.Process.GetCurrentProcess();
      long cpu = p.TotalProcessorTime.Ticks, now = DateTime.UtcNow.Ticks;
      if(_st > 0 && now > _st){
        double v = 100.0 * (cpu - _sp) / ((now - _st) * Environment.ProcessorCount);
        _slast = (int)Math.Round(Math.Max(0, Math.Min(100, v)));
      }
      _sp = cpu; _st = now; return _slast;
    }
  }
  public static long SelfMem(){ var p = System.Diagnostics.Process.GetCurrentProcess(); p.Refresh(); return p.PrivateMemorySize64; }
  public static int Cpu(){
    lock(_lk){
      long i,k,u; if(!GetSystemTimes(out i,out k,out u)) return _last;
      long di=i-_i, dt=(k-_k)+(u-_u); _i=i; _k=k; _u=u;
      if(dt>0){ _last=(int)Math.Round(100.0*(dt-di)/dt); if(_last<0)_last=0; if(_last>100)_last=100; }
      return _last;
    }
  }
}
"@ -EA Stop
        [void][OptiPerf]::Cpu()
        return $true
    }catch{ return $false }
}

function Get-RamLite {
    try {
        if(Initialize-OptiPerf){
            $m = [OptiPerf]::Mem()
            $tot  = [math]::Round($m[0]/1MB); $free = [math]::Round($m[1]/1MB)
            $used = $tot - $free
            $pct  = if($tot -gt 0){[math]::Round(($used/$tot)*100)}else{0}
            $cpu  = [OptiPerf]::Cpu()
            return @{totalMB=$tot;freeMB=$free;usedMB=$used;pct=$pct;cpuPct=$cpu;total=(Format-Size ([long]$tot*1MB));used=(Format-Size ([long]$used*1MB))}
        }
        $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -EA SilentlyContinue
        if(-not $os){ return @{totalMB=0;freeMB=0;usedMB=0;pct=0;cpuPct=0;total='0 B';used='0 B'} }
        $tot  = [math]::Round($os.TotalVisibleMemorySize/1024)
        $free = [math]::Round($os.FreePhysicalMemory/1024)
        $used = $tot - $free
        $pct  = if($tot -gt 0){[math]::Round(($used/$tot)*100)}else{0}
        $cpu  = 0
        @{totalMB=$tot;freeMB=$free;usedMB=$used;pct=$pct;cpuPct=$cpu;total=(Format-Size ([long]$tot*1MB));used=(Format-Size ([long]$used*1MB))}
    } catch { @{totalMB=0;freeMB=0;usedMB=0;pct=0;cpuPct=0;total='0 B';used='0 B'} }
}

function Get-TempCached {
    $raw = Get-OptiCache 'temp' 60
    if($raw){ return @{celsius=$raw.celsius;available=$raw.available;label=$raw.label} }
    $raw2 = Get-OptiCache 'tempdead' 600
    if($raw2){ return @{celsius=-1;available=$false;label='N/A'} }

    $r = @{celsius=-1;available=$false;label='N/A'}
    try {
        $zones = @(Get-CimInstance -Namespace "root/WMI" -ClassName MSAcpi_ThermalZoneTemperature -OperationTimeoutSec 4 -EA Stop)
        if($zones.Count -gt 0){
            $z = $zones | Where-Object { $_.InstanceName -match 'CPU|TZ0|CPUZ|THM' } | Select-Object -First 1
            if(-not $z){ $z = $zones[0] }
            $c = [math]::Round(($z.CurrentTemperature/10) - 273.15, 1)
            if($c -gt 5 -and $c -lt 115){ $r = @{celsius=$c;available=$true;label="$c" + [char]176 + "C"} }
        }
    } catch {}
    if(-not $r.available){
        try {
            $tz = Get-CimInstance -Namespace "root/CIMV2" -ClassName Win32_PerfFormattedData_Counters_ThermalZoneInformation -EA Stop | Select-Object -First 1
            if($tz -and $tz.HighPrecisionTemperature){
                $c = [math]::Round($tz.HighPrecisionTemperature/10 - 273.15, 1)
                if($c -gt 5 -and $c -lt 115){ $r = @{celsius=$c;available=$true;label="$c" + [char]176 + "C"} }
            }
        } catch {}
    }
    if($r.available){ Set-OptiCache 'temp' $r } else { Set-OptiCache 'tempdead' @{dead=$true} }
    $r
}

function Get-PerfData {
    $ram = Get-RamLite
    $tmp = Get-TempCached
    $dsk = Get-OptiCache 'disk' 20
    if(-not $dsk){
        try{ $dsk = (Get-DiskInfoData).drives }catch{ $dsk = @() }
        Set-OptiCache 'disk' $dsk
    }
    $net = 'Deconnecte'
    try{ if([System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()){ $net = 'Connecte' } }catch{}
    $self = $null
    try{ if(Initialize-OptiPerf){ $self = @{cpu=[OptiPerf]::SelfCpu(); mem=(Format-Size ([OptiPerf]::SelfMem()))} } }catch{}
    @{ram=$ram;temp=$tmp;drives=@($dsk);net=$net;self=$self}
}

function Invoke-BrowsePicker($kind){
    # Selecteur natif execute dans un runspace STA du meme processus :
    # aucun processus PowerShell cache, aucun -EncodedCommand, aucun fichier temporaire.
    $isFile = ($kind -eq 'file')
    $rs = $null; $ps = $null
    try{
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = [System.Threading.ApartmentState]::STA
        $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            param($isFile)
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            if(-not ('OptiW.Fg' -as [type])){
                Add-Type -Namespace OptiW -Name Fg -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);' -EA SilentlyContinue
            }
            $owner = New-Object System.Windows.Forms.Form
            $owner.TopMost = $true
            $owner.ShowInTaskbar = $false
            $owner.FormBorderStyle = 'None'
            $owner.Opacity = 0.01
            $owner.Size = New-Object System.Drawing.Size(1,1)
            $owner.StartPosition = 'CenterScreen'
            $owner.Show()
            $owner.Activate()
            try{ [OptiW.Fg]::SetForegroundWindow($owner.Handle) | Out-Null }catch{}
            $res = 'CANCELLED'
            try {
                if($isFile){
                    $d = New-Object System.Windows.Forms.OpenFileDialog
                    $d.Title = 'OptiPC - Selectionnez le fichier a supprimer'
                    $d.Filter = 'Tous les fichiers (*.*)|*.*'
                    $d.CheckFileExists = $true
                    $d.Multiselect = $false
                    # Ouvrir sur le dossier de l'utilisateur, jamais dans le dossier temporaire
                    # (le dossier courant d'OptiPC.exe est souvent %TEMP%).
                    $d.InitialDirectory = [Environment]::GetFolderPath('UserProfile')
                    $d.RestoreDirectory = $true
                    $d.AutoUpgradeEnabled = $true
                    if($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK){ $res = $d.FileName }
                } else {
                    $d = New-Object System.Windows.Forms.FolderBrowserDialog
                    $d.Description = 'OptiPC - Selectionnez le dossier a supprimer'
                    $d.ShowNewFolderButton = $false
                    $d.RootFolder = [System.Environment+SpecialFolder]::MyComputer
                    $d.SelectedPath = [Environment]::GetFolderPath('UserProfile')
                    if($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK){ $res = $d.SelectedPath }
                }
            } catch { $res = 'CANCELLED' }
            try { $owner.Close() } catch {}
            $res
        }).AddArgument($isFile)
        $out = $ps.Invoke()
        $val = if($out -and $out.Count -gt 0){ ([string]$out[$out.Count-1]).Trim() } else { 'CANCELLED' }
        if($val -eq 'CANCELLED' -or $val -eq ''){ return @{success=$false;path='';cancelled=$true} }
        return @{success=$true;path=$val}
    }catch{
        return @{success=$false;path='';error=$_.Exception.Message}
    }finally{
        try{ if($ps){$ps.Dispose()} }catch{}
        try{ if($rs){$rs.Close(); $rs.Dispose()} }catch{}
    }
}

function Test-SafeToDelete($p){
    if(-not $p){ return $false }
    $n = ([string]$p).Trim().TrimEnd('\').ToLower()
    if($n.Length -lt 12){ return $false }
    if($n -match '^[a-z]:\\?$'){ return $false }
    $protected = @(
        "$env:SystemRoot", "$env:SystemDrive\", "$env:ProgramFiles", "${env:ProgramFiles(x86)}",
        "$env:ProgramData", "$env:LOCALAPPDATA", "$env:APPDATA", "$env:USERPROFILE",
        "$env:SystemDrive\Users", "$env:PUBLIC", "$env:LOCALAPPDATA\Programs",
        "$env:LOCALAPPDATA\Temp", "$env:ProgramData\Microsoft"
    )
    foreach($b in $protected){
        if($b -and ($n -eq $b.Trim().TrimEnd('\').ToLower())){ return $false }
    }
    if($n -match '^[a-z]:\\windows(\\(system32|syswow64|winsxs|fonts|boot)(\\|$)|$)'){ return $false }
    if($n -match '^[a-z]:\\program files( \(x86\))?$'){ return $false }
    if($n -match '^[a-z]:\\(users|programdata|perflogs|recovery|\$recycle\.bin)$'){ return $false }
    if($n -match '^[a-z]:\\users\\[^\\]+$'){ return $false }
    if($n -match '\\program files( \(x86\))?\\(common files|windows ?(nt|defender|mail|photo viewer)?|internet explorer|microsoft|windowsapps|uninstall information)(\\|$)'){ return $false }
    if($n -match '\\appdata\\(local|roaming)(\\microsoft)?$'){ return $false }
    $true
}

function Remove-PathHard($path){
    if(-not (Test-Path -LiteralPath $path -EA SilentlyContinue)){ return $true }
    if(-not (Test-SafeToDelete $path)){ return $false }
    $isDir = $false
    try{ $isDir = (Get-Item -LiteralPath $path -Force -EA SilentlyContinue).PSIsContainer }catch{}
    try{ Remove-Item -LiteralPath $path -Force -Recurse -EA Stop; if(-not(Test-Path -LiteralPath $path)){ return $true } }catch{}
    Grant-OptiAdminAccess $path $isDir
    try{ Remove-Item -LiteralPath $path -Force -Recurse -EA Stop; if(-not(Test-Path -LiteralPath $path)){ return $true } }catch{}
    try{
        if($isDir){ cmd /c "rd /s /q `"$path`"" 2>&1 | Out-Null } else { cmd /c "del /f /q `"$path`"" 2>&1 | Out-Null }
        if(-not(Test-Path -LiteralPath $path)){ return $true }
    }catch{}
    if($isDir){
        try{
            $tmp = "$env:TEMP\optipc_empty_$(Get-Random)"
            [System.IO.Directory]::CreateDirectory($tmp) | Out-Null
            [void](Invoke-OptiCmd 'robocopy.exe' "`"$tmp`" `"$path`" /MIR /NFL /NDL /NJH /NJS /R:0 /W:0" 180000)
            Remove-Item $tmp -Force -Recurse -EA SilentlyContinue
            Remove-Item -LiteralPath $path -Force -Recurse -EA SilentlyContinue
            if(-not(Test-Path -LiteralPath $path)){ return $true }
        }catch{}
    }
    try{ Register-RebootDelete $path | Out-Null }catch{}
    $false
}

function Test-IsProtectedWindowsApp($name,$publisher){
    # Conserve pour compatibilite : vrai si l'element est indispensable a Windows
    (Get-OptiAppKind $name $publisher '') -eq 'essential'
}

# Classement des logiciels de la liste "Desinstaller" :
#   'essential' = indispensable au fonctionnement du PC -> MASQUE et protege
#                 (composants Windows, codecs, securite, Store, langue,
#                  pilotes et panneaux son / graphique / touchpad / touches Fn)
#   'oem'       = logiciel preinstalle par le fabricant, generalement inutile
#                 -> affiche avec un badge FABRICANT
#   ''          = logiciel normal
function Get-OptiAppKind($name,$publisher,$tech){
    $n = [string]$name; $p = [string]$publisher; $t = [string]$tech
    $all = "$n|$t"
    # Outils "miracle" de pilotes = logiciels ordinaires (jamais proteges)
    if($all -match '(?i)Driver ?(Booster|Easy|Genius|Talent|Updater|Support|Max|Reviver|Fix)|DriverPack|Snappy'){ return '' }

    # --- Composants Windows / Microsoft indispensables ---
    $ms = '(?i)(Assistant d.installation de Windows|Windows.*Installation Assistant|Contr[oô]le d.int[eé]grit[eé] du PC Windows|PC Health Check|Windows Malicious Software Removal Tool|Microsoft Update Health Tools|Outils de r[eé]paration de la mise [aà] jour|Visual C\+\+|Microsoft \.NET|\.NET Native|Windows SDK|WebView2|Windows Driver Package|App ?Runtime|AppRuntime|Microsoft\.VCLibs|Microsoft\.UI\.Xaml|Microsoft\.Services\.Store|VideoExtension|ImageExtension|Video Extension|Image Extension|WebMediaExtensions|Web Media Extensions|HEVC|HEIF|SecHealthUI|S[eé]curit[eé] Windows|Windows Security|Microsoft Defender|Windows Defender|Microsoft Store|WindowsStore|StorePurchaseApp|DesktopAppInstaller|App Installer|Programme d.installation d.application|Windows Package Manager|winget|LanguageExperiencePack|Local Experience Pack|Module d.exp[eé]rience locale|Language Pack|Module linguistique|ApplicationCompatibility|Compatibility Fix Database|Widgets Platform Runtime|WebExperience|StartExperiencesApp|CrossDevice|Microsoft Edge|MicrosoftEdge|Edge\.Stable|GameInput|DirectX|Microsoft Visual Studio Installer|Windows Subsystem|Microsoft Windows Desktop Runtime|Microsoft ASP\.NET Core)'
    if($all -match $ms){ return 'essential' }

    # --- Pilotes et panneaux materiels (son, graphique, touchpad, touches Fn, Wi-Fi, Bluetooth) ---
    $hw = '(?i)(Realtek|RealtekSemiconductor|Intel\(R\)|Intel.*(Graphics|Management Engine|Rapid Storage|Serial IO|Chipset|Wireless|PROSet|Bluetooth|Dynamic|Innovation Platform|Optane|Thunderbolt|Arc )|IntelGraphicsExperience|AppUp\.Intel|AMD (Software|Radeon|Chipset|Ryzen)|Radeon Software|AMDRadeonSoftware|AdvancedMicroDevices|NVIDIA (Graphics|Control Panel|PhysX|HD Audio|FrameView|Display|USBC)|NVIDIACorp|Dolby|DTS (Audio|Sound|:X)|Waves (MaxxAudio|Audio)|MaxxAudio|B[&＆]O|Bang ?[&＆] ?Olufsen|BOAudioControl|Audio Control|Audio Console|Audio Switch|Smart Sound|SmartAudio|Synaptics|\bELAN\b|Precision Touch ?Pad|TouchPad|Bluetooth|Qualcomm|Killer (Performance|Network|Wireless)|MediaTek|Broadcom|Thunderbolt|Fingerprint|Goodix|Validity Sensors|HP System Event|HPSystemEventUtility|HP Hotkey|Lenovo (Hotkeys|Utility|System Interface Foundation|Pen Settings)|LenovoUtility|E0469640|ASUS (System Control Interface|ATK|Precision)|ATK Package|Dell (Power Manager Service|Optimizer Service|Peripheral)|Microsoft Surface|Pilote|Graphics Driver|Audio Driver|Chipset|Firmware|BIOS|Driver Package| Drivers?$)'
    if($all -match $hw){ return 'essential' }

    # --- Logiciels preinstalles par le fabricant (supprimables) ---
    if($all -match '(?i)(^|\b)(HP |HP$|Hewlett|Lenovo|Dell|ASUS|Acer|MSI |Samsung|Toshiba|Dynabook|Huawei|Medion|McAfee|Norton|WildTangent|Booking\.com|ExpressVPN|Dropbox (promotion|offre)|AD2F1837|E046963F|DellInc|B9ECED6F|AcerIncorporated|SAMSUNGELECTRONICS)'){ return 'oem' }
    if($p -match '(?i)^(HP Inc|Hewlett|Lenovo|Dell|ASUSTeK|Acer|Samsung|Toshiba|Huawei|McAfee|NortonLifeLock|Gen Digital)'){ return 'oem' }
    ''
}

function Get-AppsFull {
    $c = Get-OptiCache 'apps' 45
    if($c){ return @($c) }
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $apps = [System.Collections.ArrayList]::new()
    $seen = @{}
    foreach($rp in $roots){
        if(-not(Test-Path $rp -EA SilentlyContinue)){ continue }
        try{
            foreach($k in (Get-ChildItem $rp -EA SilentlyContinue)){
                try{
                    $pr = Get-ItemProperty $k.PSPath -EA SilentlyContinue
                    if(-not $pr -or -not $pr.DisplayName){ continue }
                    if($pr.SystemComponent -eq 1){ continue }
                    if($pr.NoRemove -eq 1){ continue }
                    if($pr.ParentKeyName){ continue }
                    if($pr.ReleaseType -match 'Update|Hotfix|Security'){ continue }
                    $n = ([string]$pr.DisplayName).Trim()
                    if(-not $n){ continue }
                    if($n -match '^(KB\d+|Update for |Security Update|Hotfix|Mise a jour)'){ continue }
                    $kind = Get-OptiAppKind $n ([string]$pr.Publisher) ([string]$k.PSChildName)
                    if($kind -eq 'essential'){ continue }
                    $dedup = $n.ToLower() + '|' + [string]$pr.DisplayVersion
                    if($seen[$dedup]){ continue }
                    $seen[$dedup] = $true
                    $loc = [string]$pr.InstallLocation
                    if($loc){ $loc = $loc.Trim().Trim('"').TrimEnd('\') }
                    $szB = if($pr.EstimatedSize){ [long]$pr.EstimatedSize * 1024 } else { [long]0 }
                    if($szB -le 0 -and $loc -and (Test-Path -LiteralPath $loc -EA SilentlyContinue)){ $szB = Get-FolderSize $loc }
                    $unst = [string]$pr.UninstallString
                    $quiet = [string]$pr.QuietUninstallString
                    $date = [string]$pr.InstallDate
                    if($date -match '^(\d{4})(\d{2})(\d{2})$'){ $date = "$($matches[3])/$($matches[2])/$($matches[1])" }
                    [void]$apps.Add(@{
                        name            = $n
                        version         = [string]$pr.DisplayVersion
                        publisher       = [string]$pr.Publisher
                        sizeBytes       = $szB
                        size            = if($szB -gt 0){ Format-Size $szB } else { '?' }
                        uninstallString = $unst
                        quietUninstall  = $quiet
                        installLocation = $loc
                        installDate     = $date
                        regKey          = [string]$k.PSPath
                        type            = 'win32'
                        kind            = $kind
                        id              = [string]$k.PSChildName
                        removable       = [bool]($unst -or $quiet)
                    })
                }catch{}
            }
        }catch{}
    }
    $mfWatch = [System.Diagnostics.Stopwatch]::StartNew()
    try{
        foreach($p in @(Get-AppxPackage -EA SilentlyContinue)){
            try{
                if($p.IsFramework){ continue }
                if($p.SignatureKind -eq 'System'){ continue }
                if($p.NonRemovable){ continue }
                $dn = [string]$p.Name
                $pubDn = ''
                # Lire chaque manifeste coute cher : au-dela de 20 s on garde le nom technique
                if($mfWatch.Elapsed.TotalSeconds -lt 20){ try{
                    $mf = Get-AppxPackageManifest $p -EA SilentlyContinue
                    if($mf -and $mf.Package.Properties.DisplayName -and $mf.Package.Properties.DisplayName -notmatch '^ms-resource'){
                        $dn = [string]$mf.Package.Properties.DisplayName
                    }
                    if($mf -and $mf.Package.Properties.PublisherDisplayName -and $mf.Package.Properties.PublisherDisplayName -notmatch '^ms-resource'){
                        $pubDn = [string]$mf.Package.Properties.PublisherDisplayName
                    }
                }catch{} }
                $pubShown = if($pubDn){ $pubDn } else { ([string]$p.Publisher -replace '^CN=([^,]+).*$','$1') }
                $kind = Get-OptiAppKind $dn $pubShown ([string]$p.Name)
                if($kind -eq 'essential'){ continue }
                $instLoc = [string]$p.InstallLocation
                $sz = if($instLoc -and (Test-Path -LiteralPath $instLoc -EA SilentlyContinue)){ Get-FolderSize $instLoc } else { [long]0 }
                [void]$apps.Add(@{
                    name            = $dn + ' (Store)'
                    version         = [string]$p.Version
                    publisher       = $pubShown
                    sizeBytes       = $sz
                    size            = if($sz -gt 0){ Format-Size $sz } else { '?' }
                    uninstallString = ''
                    quietUninstall  = ''
                    installLocation = $instLoc
                    installDate     = ''
                    regKey          = ''
                    type            = 'uwp'
                    kind            = $kind
                    id              = [string]$p.PackageFullName
                    removable       = $true
                })
            }catch{}
        }
    }catch{}
    $res = @($apps | Sort-Object { [string]$_.name })
    Set-OptiCache 'apps' $res
    $res
}

function Clear-AppsCache { try{ Remove-Item (Get-OptiCacheFile 'apps') -Force -EA SilentlyContinue }catch{} }

function Get-AppLeftovers($app){
    $dirs = New-Object System.Collections.ArrayList
    $keys = New-Object System.Collections.ArrayList
    $runs = New-Object System.Collections.ArrayList
    $name = ([string]$app.name) -replace '\s*\(Store\)$',''
    $pub  = [string]$app.publisher
    $loc  = [string]$app.installLocation
    $safe = ($name -replace '[\\/:*?"<>|]','').Trim()
    $short = ($safe -split '\s+')[0]

    $cand = New-Object System.Collections.ArrayList
    if($loc){ [void]$cand.Add($loc) }
    foreach($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramData, "$env:LOCALAPPDATA\Programs")){
        if(-not $root){ continue }
        $subs = @($safe)
        if($pub){ $subs += (Join-Path $pub $safe) }
        foreach($sub in $subs){
            if(-not $sub){ continue }
            [void]$cand.Add((Join-Path $root $sub))
        }
    }
    foreach($p in ($cand | Select-Object -Unique)){
        try{
            if((Test-Path -LiteralPath $p -EA SilentlyContinue) -and (Test-SafeToDelete $p)){
                $sz = Get-FolderSize $p
                [void]$dirs.Add(@{path=$p;size=$sz;sizeStr=(Format-Size $sz)})
            }
        }catch{}
    }

    if($app.regKey){ [void]$keys.Add([string]$app.regKey) }
    if($pub -and $safe){
        foreach($hive in @('HKCU:\SOFTWARE','HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node')){
            foreach($sub in @("$pub\$safe", "$safe")){
                $rk = Join-Path $hive $sub
                try{ if(Test-Path $rk -EA SilentlyContinue){ [void]$keys.Add($rk) } }catch{}
            }
        }
    }

    foreach($rk in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')){
        if(-not(Test-Path $rk -EA SilentlyContinue)){ continue }
        try{
            $pr = Get-ItemProperty $rk -EA SilentlyContinue
            if(-not $pr){ continue }
            $pr.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notmatch '^PS' } | ForEach-Object {
                $v = [string]$_.Value
                $hit = $false
                if($loc -and $v -like "*$loc*"){ $hit = $true }
                elseif($short.Length -ge 4 -and $v -match [regex]::Escape($short)){ $hit = $true }
                if($hit){ [void]$runs.Add(@{key=$rk;name=$_.Name;value=$v}) }
            }
        }catch{}
    }

    $tot = ($dirs | Measure-Object -Property size -Sum).Sum
    @{dirs=@($dirs);keys=@($keys|Select-Object -Unique);runs=@($runs);count=($dirs.Count+$keys.Count+$runs.Count);totalSize=(Format-Size ([long]$tot))}
}

function Get-OptiInstallerKind($exe){
    try{
        if(-not $exe -or -not (Test-Path -LiteralPath $exe)){ return 'unknown' }
        if([IO.Path]::GetFileName($exe) -match '(?i)^unins\d{3}\.exe$'){ return 'inno' }
        $fs = [IO.File]::Open($exe,'Open','Read','ReadWrite')
        try{
            $len = [int][Math]::Min($fs.Length, 4MB)
            $buf = New-Object byte[] $len
            [void]$fs.Read($buf,0,$len)
        } finally { $fs.Close() }
        $txt = [Text.Encoding]::ASCII.GetString($buf)
        if($txt -match 'Nullsoft'){ return 'nsis' }
        if($txt -match 'Inno Setup'){ return 'inno' }
    }catch{}
    'unknown'
}
function Remove-OptiStoreApp($pkg){
    # Remove-AppxPackage est lance dans un PowerShell separe et invisible :
    # sa barre de progression ne peut plus geler OptiPC, et on impose un delai.
    if($pkg -notmatch '^[A-Za-z0-9._~\-]+$'){ return @{ok=$false;msg="Identifiant de paquet invalide"} }
    $cmd = "`$ProgressPreference='SilentlyContinue'; try{ Remove-AppxPackage -Package '$pkg' -ErrorAction Stop; exit 0 }catch{ [Console]::Error.WriteLine(`$_.Exception.Message); exit 1 }"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -Command `"$cmd`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardError = $true
    $pr = [System.Diagnostics.Process]::Start($psi)
    $errTask = $pr.StandardError.ReadToEndAsync()
    if(-not $pr.WaitForExit(180000)){
        try{ $pr.Kill() }catch{}
        return @{ok=$false;msg="Delai depasse (3 min) : le service de deploiement Windows ne repond pas"}
    }
    $err = ''
    try{ $err = ([string]$errTask.Result).Trim() }catch{}
    $still = $null
    try{ $still = Get-AppxPackage -Name ($pkg.Split('_')[0]) -EA SilentlyContinue | Where-Object { $_.PackageFullName -eq $pkg } }catch{}
    if(-not $still){ return @{ok=$true;msg=''} }
    if(-not $err){ $err = "le paquet est toujours present (code $($pr.ExitCode))" }
    @{ok=$false;msg=$err}
}
function Test-OptiAppStillInstalled($app){
    # Vrai si le logiciel figure encore dans "Programmes et fonctionnalites",
    # c.-a-d. si sa cle de desinstallation existe toujours dans le registre.
    if([string]$app.type -eq 'uwp'){
        try{
            $base = ([string]$app.id).Split('_')[0]
            return [bool](Get-AppxPackage -Name $base -EA SilentlyContinue | Where-Object { $_.PackageFullName -eq [string]$app.id })
        }catch{ return $false }
    }
    $rk = [string]$app.regKey
    if($rk -and (Test-Path -LiteralPath $rk -EA SilentlyContinue)){
        $pr = Get-ItemProperty -LiteralPath $rk -EA SilentlyContinue
        if($pr -and $pr.DisplayName){ return $true }
    }
    # Repli : rechercher par nom dans les trois racines Uninstall
    $nm = ([string]$app.name -replace '\s*\(Store\)$','').Trim().ToLower()
    if(-not $nm){ return $false }
    foreach($rp in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')){
        if(-not(Test-Path $rp -EA SilentlyContinue)){ continue }
        foreach($k in @(Get-ChildItem $rp -EA SilentlyContinue)){
            try{
                $pr = Get-ItemProperty -LiteralPath $k.PSPath -EA SilentlyContinue
                if($pr -and ([string]$pr.DisplayName).Trim().ToLower() -eq $nm){ return $true }
            }catch{}
        }
    }
    $false
}
function Wait-OptiUninstallEnd($app, [datetime]$since, [int]$maxMs, $liveLog){
    # POURQUOI : beaucoup de desinstalleurs (Zoom, Teams, Discord...) lancent
    # une copie d'eux-memes puis quittent tout de suite avec le code 0. La
    # vraie desinstallation (et sa fenetre de confirmation) continue apres.
    # OptiPC verifiait le registre 0,4 s plus tard et annoncait un echec alors
    # que le client venait d'accepter a l'ecran. On attend donc que l'entree
    # disparaisse, tant qu'un processus de desinstallation lance depuis le
    # debut de l'operation tourne encore.
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $idle = [Diagnostics.Stopwatch]::StartNew()
    $nextBeat = 15
    $selfPid = $PID
    while($sw.ElapsedMilliseconds -lt $maxMs){
        if(-not (Test-OptiAppStillInstalled $app)){ return $true }
        $busy = $false
        try{
            foreach($pr in (Get-CimInstance Win32_Process -EA SilentlyContinue)){
                if($pr.ProcessId -eq $selfPid){ continue }
                $st = $null; try{ $st = $pr.CreationDate }catch{}
                if(-not $st -or $st -lt $since.AddSeconds(-2)){ continue }
                $n = ([string]$pr.Name).ToLower()
                $ep = ([string]$pr.ExecutablePath).ToLower()
                if($n -match 'unins|uninst|setup|install|au_\.exe|msiexec|update' -or $ep -match '\\temp\\|\\uninstall'){
                    $busy = $true; break
                }
            }
        }catch{}
        if($busy){ $idle.Restart() }
        elseif($idle.ElapsedMilliseconds -gt 12000){ break }
        $sec = [int]($sw.ElapsedMilliseconds/1000)
        if($liveLog -and $sec -ge $nextBeat){
            & $liveLog "Desinstallation en cours... ($sec s) - repondez a la fenetre du logiciel si elle s'affiche"
            $nextBeat += 15
        }
        Start-Sleep -Milliseconds 1500
    }
    -not (Test-OptiAppStillInstalled $app)
}

function Invoke-AppUninstallV2($app,$mode,$liveLog){
    $log = New-Object System.Collections.ArrayList
    # Chaque ligne ajoutee au journal part aussi en direct vers l'interface
    # (suppression forcee), au lieu d'arriver seulement a la fin.
    $L = { param($m) [void]$log.Add($m); if($liveLog){ try{ & $liveLog $m }catch{} } }
    $name = ([string]$app.name) -replace '\s*\(Store\)$',''
    if((Get-OptiAppKind $name ([string]$app.publisher) ([string]$app.id)) -eq 'essential'){
        return @{success=$false;log=@("Element indispensable au fonctionnement du PC : desinstallation bloquee par OptiPC");message="$name est necessaire au PC : OptiPC ne le supprime pas"}
    }
    $loc  = [string]$app.installLocation
    $isForce = ($mode -eq 'force')

    if([string]$app.type -eq 'uwp'){
        $rr = $null
        try{ $rr = Remove-OptiStoreApp ([string]$app.id) }catch{ $rr = @{ok=$false;msg=$_.Exception.Message} }
        Clear-AppsCache
        if($rr.ok){
            & $L ("Application Microsoft Store desinstallee")
            return @{success=$true;log=@($log);message="$name desinstalle"}
        }
        return @{success=$false;log=@("Echec : $($rr.msg)");message="Impossible de desinstaller $name"}
    }

    if($isForce){
        $killed = 0
        try{
            foreach($p in (Get-Process -EA SilentlyContinue)){
                try{
                    $pp = $null
                    try{ $pp = [string]$p.Path }catch{}
                    $match = $false
                    if($loc -and $pp -and $pp.ToLower().StartsWith($loc.ToLower())){ $match = $true }
                    if($match){ cmd /c "taskkill /F /T /PID $($p.Id) 2>nul" | Out-Null; $killed++; & $L "Processus arrete : $($p.ProcessName)" }
                }catch{}
            }
        }catch{}
        if($killed -gt 0){ & $L ("$killed processus arrete(s)") }

        $svcN = 0
        try{
            foreach($s in (Get-WmiObject Win32_Service -EA SilentlyContinue)){
                $sp = [string]$s.PathName
                if($loc -and $sp -and ($sp -replace '"','').ToLower().StartsWith($loc.ToLower())){
                    try{ Stop-Service $s.Name -Force -EA SilentlyContinue }catch{}
                    try{ sc.exe delete $s.Name 2>&1 | Out-Null; $svcN++; & $L "Service supprime : $($s.Name)" }catch{}
                }
            }
        }catch{}
        if($svcN -gt 0){ & $L ("$svcN service(s) supprime(s)") }

        $tskN = 0
        try{
            foreach($t in (Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.TaskPath -notmatch '^\\Microsoft\\' })){
                $hit = $false
                foreach($a in $t.Actions){
                    $ex = [string]$a.Execute
                    if($loc -and $ex -and ($ex -replace '"','').ToLower().StartsWith($loc.ToLower())){ $hit = $true }
                }
                if($hit){ try{ Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -EA SilentlyContinue; $tskN++ }catch{} }
            }
        }catch{}
        if($tskN -gt 0){ & $L ("$tskN tache(s) planifiee(s) supprimee(s)") }
    }

    $uns = [string]$app.quietUninstall
    $silent = [bool]$uns
    if(-not $uns){ $uns = [string]$app.uninstallString }
    $exitOk = $true
    if($uns){
        try{
            $uns = [Environment]::ExpandEnvironmentVariables($uns)
            $exe = $null; $argStr = ''
            if($uns -match '(?i)msiexec'){
                $g = ''
                if($uns -match '(\{[0-9A-Fa-f-]{36}\})'){ $g = $matches[1] }
                $exe = 'msiexec.exe'
                $argStr = if($g){ "/x $g /qn /norestart" } else { ($uns -replace '(?i).*msiexec(\.exe)?\s*','') + ' /qn /norestart' }
                $silent = $true
            } else {
                if($uns -match '^\s*"([^"]+)"\s*(.*)$'){ $exe = $matches[1]; $argStr = $matches[2] }
                elseif($uns -match '^\s*(.+?\.exe)(\s+(.*))?$'){ $exe = $matches[1]; $argStr = [string]$matches[3] }
                else { $exe = $uns; $argStr = '' }
                if($exe -and -not (Test-Path -LiteralPath $exe)){
                    & $L ("Desinstalleur introuvable sur le disque : $exe")
                    $exe = $null; $exitOk = $false
                }
                if($exe -and -not $silent){
                    # Mode silencieux uniquement si le type d'installeur est reconnu.
                    # Avant : fenetre cachee + arguments au hasard => assistant invisible
                    # qui attendait un clic pendant 2 min (gel en selection multiple).
                    switch(Get-OptiInstallerKind $exe){
                        'inno' { $argStr = ($argStr + ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART').Trim(); $silent = $true }
                        'nsis' {
                            if($argStr -notmatch '(^|\s)/S(\s|$)'){ $argStr = ($argStr + ' /S').Trim() }
                            if($argStr -notmatch '_\?='){ $argStr = "$argStr _?=" + (Split-Path $exe -Parent) }
                            $silent = $true
                        }
                    }
                }
            }
            if($exe){
                $ws    = if($silent){ 'Hidden' } else { 'Normal' }
                $limit = if($silent){ 180000 } else { 600000 }
                if(-not $silent){ & $L ("Desinstalleur interactif : suivez les instructions a l'ecran") }
                else { & $L ("Desinstallation silencieuse en cours...") }
                $launchedAt = Get-Date
                $proc = if($argStr){ Start-Process $exe -ArgumentList $argStr -PassThru -WindowStyle $ws -EA Stop }
                        else       { Start-Process $exe -PassThru -WindowStyle $ws -EA Stop }
                if($proc){
                    if(-not $proc.WaitForExit($limit)){
                        try{ $proc.Kill() }catch{}
                        $exitOk = $false
                        & $L ("Desinstalleur interrompu (delai de $([int]($limit/60000)) min depasse)")
                    } else {
                        $code = $proc.ExitCode
                        if(@(0,1605,1614,3010,1641) -notcontains $code){ $exitOk = $false }
                        & $L ("Desinstalleur officiel termine (code $code)")
                        if(Test-OptiAppStillInstalled $app){
                            & $L ("Attente de la fin de la desinstallation...")
                            $wait = if($silent){ 60000 } else { 300000 }
                            [void](Wait-OptiUninstallEnd $app $launchedAt $wait $liveLog)
                        }
                    }
                }
            }
        }catch{ $exitOk = $false; & $L ("Desinstalleur indisponible : $($_.Exception.Message)") }
    } else {
        & $L ("Aucun desinstalleur declare dans le registre")
    }

    if(-not $isForce){
        Clear-AppsCache
        $lo = Get-AppLeftovers $app
        Start-Sleep -Milliseconds 400
        $stillThere = Test-OptiAppStillInstalled $app
        if($stillThere){
            & $L ("ATTENTION : $name figure toujours dans Programmes et fonctionnalites")
            if(-not $silent){ & $L ("Le desinstalleur demande peut-etre une action a l'ecran, ou un redemarrage") }
            return @{success=$false;log=@($log);leftovers=$lo;message="$name : desinstallation incomplete";stillInstalled=$true;pendingLeftovers=($lo.count -gt 0)}
        }
        return @{success=$true;log=@($log);leftovers=$lo;message="$name desinstalle";pendingLeftovers=($lo.count -gt 0)}
    }

    $lo = Get-AppLeftovers $app
    $dirOk = 0
    foreach($d in $lo.dirs){
        if(Remove-PathHard ([string]$d.path)){ $dirOk++; & $L ("Dossier supprime : $($d.path) ($($d.sizeStr))") }
        else { & $L ("Dossier verrouille (supprime au redemarrage) : $($d.path)") }
    }
    $keyOk = 0
    foreach($k in $lo.keys){
        try{ Remove-Item -LiteralPath $k -Recurse -Force -EA SilentlyContinue; $keyOk++ }catch{}
    }
    if($keyOk -gt 0){ & $L ("$keyOk cle(s) de registre supprimee(s)") }
    foreach($r in $lo.runs){
        try{ Remove-ItemProperty -Path ([string]$r.key) -Name ([string]$r.name) -Force -EA SilentlyContinue; & $L ("Entree de demarrage supprimee : $($r.name)") }catch{}
    }
    $lnk = 0
    foreach($sd in @("$env:USERPROFILE\Desktop","$env:PUBLIC\Desktop","$env:APPDATA\Microsoft\Windows\Start Menu\Programs","$env:ProgramData\Microsoft\Windows\Start Menu\Programs")){
        if(-not(Test-Path $sd)){ continue }
        try{
            Get-ChildItem $sd -Recurse -Filter '*.lnk' -EA SilentlyContinue | Where-Object { $_.BaseName -match [regex]::Escape(($name -split '\s+')[0]) } | ForEach-Object {
                Remove-Item $_.FullName -Force -EA SilentlyContinue; $lnk++
            }
        }catch{}
    }
    if($lnk -gt 0){ & $L ("$lnk raccourci(s) supprime(s)") }

    Clear-AppsCache
    @{success=$true;log=@($log);message="$name supprime ($dirOk dossier(s), $keyOk cle(s))";removed=$dirOk}
}

function Get-OptiAppTraces($app){
    # Recherche approfondie facon Geek Uninstaller : dossiers, cles de
    # registre, entrees de demarrage, services, taches planifiees et
    # raccourcis lies au logiciel. Tout est filtre par Test-SafeToDelete.
    $name = (([string]$app.name) -replace '\s*\(Store\)$','').Trim()
    $pub  = ([string]$app.publisher).Trim()
    $loc  = ([string]$app.installLocation).Trim().Trim('"').TrimEnd('\')
    $safe = ($name -replace '[\\/:*?"<>|]','').Trim()
    $short= ($safe -split '\s+')[0]
    $dirs=[System.Collections.ArrayList]::new(); $keys=[System.Collections.ArrayList]::new()
    $runs=[System.Collections.ArrayList]::new(); $svcs=[System.Collections.ArrayList]::new()
    $tasks=[System.Collections.ArrayList]::new(); $lnks=[System.Collections.ArrayList]::new()
    $seenD=@{}

    function _addDir($pp){
        if(-not $pp){ return }
        $pp=([string]$pp).Trim().Trim('"').TrimEnd('\'); if(-not $pp){ return }
        $kl=$pp.ToLower(); if($seenD[$kl]){ return }
        if((Test-Path -LiteralPath $pp -EA SilentlyContinue) -and (Test-SafeToDelete $pp) -and -not (Test-UnderSelfDir $pp)){
            $seenD[$kl]=$true
            $sz=0; try{ $sz=Get-FolderSize $pp }catch{}
            [void]$dirs.Add(@{path=$pp;size=$sz;sizeStr=(Format-Size $sz)})
        }
    }
    _addDir $loc
    foreach($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs", $env:LOCALAPPDATA, $env:APPDATA, "$env:ProgramData")){
        if(-not $root){ continue }
        _addDir (Join-Path $root $safe)
        if($pub){ _addDir (Join-Path $root (Join-Path $pub $safe)) }
    }
    # Cle de desinstallation + cles Software au nom de l'editeur / du logiciel
    if($app.regKey){ [void]$keys.Add([string]$app.regKey) }
    if($safe){
        foreach($hive in @('HKCU:\SOFTWARE','HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node')){
            foreach($sub in @($safe, ($(if($pub){"$pub\$safe"}else{$null})), $pub)){
                if(-not $sub){ continue }
                $rk=Join-Path $hive $sub
                try{ if(Test-Path $rk -EA SilentlyContinue){ [void]$keys.Add($rk) } }catch{}
            }
        }
    }
    # Entrees de demarrage (Run)
    foreach($rk in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')){
        if(-not(Test-Path $rk -EA SilentlyContinue)){ continue }
        try{
            $pr=Get-ItemProperty $rk -EA SilentlyContinue; if(-not $pr){ continue }
            $pr.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notmatch '^PS' } | ForEach-Object {
                $v=[string]$_.Value
                if(($loc -and $v.ToLower().Contains($loc.ToLower())) -or ($short.Length -ge 4 -and $v -match [regex]::Escape($short))){
                    [void]$runs.Add(@{key=$rk;name=$_.Name})
                }
            }
        }catch{}
    }
    # Services dont l'executable est dans le dossier du logiciel
    if($loc){
        try{
            foreach($sv in (Get-CimInstance Win32_Service -EA SilentlyContinue)){
                $sp=(([string]$sv.PathName) -replace '"','').ToLower()
                if($sp -and $sp.StartsWith($loc.ToLower())){ [void]$svcs.Add([string]$sv.Name) }
            }
        }catch{}
    }
    # Taches planifiees (hors Microsoft) pointant vers le dossier
    if($loc){
        try{
            foreach($t in (Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.TaskPath -notmatch '^\\Microsoft\\' })){
                foreach($a in $t.Actions){
                    $ex=(([string]$a.Execute) -replace '"','').ToLower()
                    if($ex -and $ex.StartsWith($loc.ToLower())){ [void]$tasks.Add(@{name=$t.TaskName;path=$t.TaskPath}); break }
                }
            }
        }catch{}
    }
    # Raccourcis Bureau + Menu Demarrer
    if($short.Length -ge 3){
        foreach($sd in @("$env:USERPROFILE\Desktop","$env:PUBLIC\Desktop","$env:APPDATA\Microsoft\Windows\Start Menu\Programs","$env:ProgramData\Microsoft\Windows\Start Menu\Programs")){
            if(-not(Test-Path $sd)){ continue }
            try{
                Get-ChildItem $sd -Recurse -Filter '*.lnk' -EA SilentlyContinue | Where-Object { $_.BaseName -match [regex]::Escape($short) } | ForEach-Object { [void]$lnks.Add($_.FullName) }
            }catch{}
        }
    }
    $keysU=@($keys|Select-Object -Unique)
    @{dirs=@($dirs);keys=$keysU;runs=@($runs);services=@($svcs);tasks=@($tasks);shortcuts=@($lnks);
      count=($dirs.Count+$keysU.Count+$runs.Count+$svcs.Count+$tasks.Count+$lnks.Count)}
}

function Get-AppForceLogFile { "$env:TEMP\optipc_appforce_log.txt" }

function Invoke-AppForceUninstall($app){
    # Journal live : chaque ligne est relue par l'interface pendant l'operation.
    $lf = Get-AppForceLogFile
    try{[IO.File]::WriteAllText($lf,"",[Text.Encoding]::UTF8)}catch{}
    $WL={param($m)try{[IO.File]::AppendAllText($lf,(Get-Date -F 'HH:mm:ss')+" $m`n",[Text.Encoding]::UTF8)}catch{}}
    $name=(([string]$app.name) -replace '\s*\(Store\)$','').Trim()
    if((Get-OptiAppKind $name ([string]$app.publisher) ([string]$app.id)) -eq 'essential'){
        & $WL "BLOQUE : $name est indispensable au fonctionnement du PC"
        return @{success=$false;stillInstalled=$true;message="$name est necessaire au PC : OptiPC ne le supprime pas"}
    }
    $removed=0

    & $WL "Analyse de $name..."
    if($app.installLocation){ & $WL "Dossier d'installation : $($app.installLocation)" }

    # 1) Desinstalleur officiel (silencieux si connu) ou paquet Store
    if([string]$app.type -eq 'uwp'){
        & $WL "Suppression du paquet Microsoft Store..."
        $rr=$null; try{ $rr=Remove-OptiStoreApp ([string]$app.id) }catch{ $rr=@{ok=$false;msg=$_.Exception.Message} }
        if($rr.ok){ & $WL "Paquet Store supprime" } else { & $WL "Store : $($rr.msg)" }
    } else {
        & $WL "Lancement du desinstalleur officiel..."
        try{ [void](Invoke-AppUninstallV2 $app 'force' $WL) }
        catch{ & $WL "Desinstalleur : $($_.Exception.Message)" }
    }

    # 2) Recherche approfondie des traces restantes
    & $WL "Recherche des traces restantes (dossiers, registre, services, taches, raccourcis)..."
    $tr = Get-OptiAppTraces $app
    & $WL "$($tr.count) trace(s) trouvee(s) : $($tr.dirs.Count) dossier(s), $($tr.keys.Count) cle(s), $($tr.services.Count) service(s), $($tr.tasks.Count) tache(s), $($tr.shortcuts.Count) raccourci(s)"

    foreach($sv in $tr.services){
        try{ sc.exe stop "$sv" 2>&1 | Out-Null; sc.exe delete "$sv" 2>&1 | Out-Null; & $WL "Service supprime : $sv"; $removed++ }catch{}
    }
    foreach($t in $tr.tasks){
        try{ Unregister-ScheduledTask -TaskName $t.name -TaskPath $t.path -Confirm:$false -EA SilentlyContinue; & $WL "Tache planifiee supprimee : $($t.name)"; $removed++ }catch{}
    }
    foreach($d in $tr.dirs){
        $ok=$false; try{ $ok=Remove-PathHard ([string]$d.path) }catch{}
        if($ok){ & $WL "Dossier supprime : $($d.path) ($($d.sizeStr))"; $removed++ }
        else   { & $WL "Dossier verrouille (au redemarrage) : $($d.path)" }
    }
    foreach($k in $tr.keys){
        $kd = ([string]$k) -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\'
        try{ if(Test-Path -LiteralPath $k -EA SilentlyContinue){ Remove-Item -LiteralPath $k -Recurse -Force -EA Stop; & $WL "Cle de registre supprimee : $kd"; $removed++ } }
        catch{ & $WL "Cle de registre non supprimee : $kd" }
    }
    foreach($r in $tr.runs){
        try{ Remove-ItemProperty -Path ([string]$r.key) -Name ([string]$r.name) -Force -EA SilentlyContinue; & $WL "Entree de demarrage supprimee : $($r.name)"; $removed++ }catch{}
    }
    foreach($ln in $tr.shortcuts){
        try{ Remove-Item -LiteralPath $ln -Force -EA SilentlyContinue; & $WL "Raccourci supprime : $([IO.Path]::GetFileName($ln))"; $removed++ }catch{}
    }

    Clear-AppsCache
    $still = Test-OptiAppStillInstalled $app
    if($still){ & $WL "ATTENTION : le logiciel figure encore dans la liste (redemarrage peut-etre requis)" }
    $msg = if($still){ "$name : traces supprimees, mais l'entree subsiste (redemarrez)" } else { "$name entierement supprime ($removed element(s) nettoye(s))" }
    & $WL "TERMINE - $msg"
    @{success=(-not $still);removed=$removed;message=$msg;stillInstalled=$still}
}
function Invoke-RemoveLeftovers($app){
    $lo = Get-AppLeftovers $app
    $log = New-Object System.Collections.ArrayList
    $n = 0
    foreach($d in $lo.dirs){ if(Remove-PathHard ([string]$d.path)){ $n++; [void]$log.Add("Supprime : $($d.path)") } }
    foreach($k in $lo.keys){ try{ Remove-Item -LiteralPath $k -Recurse -Force -EA SilentlyContinue; $n++ }catch{} }
    foreach($r in $lo.runs){ try{ Remove-ItemProperty -Path ([string]$r.key) -Name ([string]$r.name) -Force -EA SilentlyContinue; $n++ }catch{} }
    Clear-AppsCache
    @{success=$true;removed=$n;log=@($log);message="$n residu(s) supprime(s)"}
}

function Get-QuarDir {
    $d = "$env:LOCALAPPDATA\OptiPC\Quarantine"
    if(-not(Test-Path $d)){ [System.IO.Directory]::CreateDirectory($d) | Out-Null }
    $d
}
function Get-QuarManifest {
    $f = (Get-QuarDir) + "\manifest.json"
    if(-not(Test-Path $f)){ return @() }
    try{ @([IO.File]::ReadAllText($f,[Text.Encoding]::UTF8) | ConvertFrom-Json) }catch{ @() }
}
function Save-QuarManifest($items){
    $f = (Get-QuarDir) + "\manifest.json"
    try{ (@($items) | ConvertTo-Json -Depth 6) | Out-File $f -Encoding UTF8 -Force }catch{}
}
function Invoke-Quarantine($path,$reason){
    if(-not(Test-Path -LiteralPath $path -EA SilentlyContinue)){ return @{ok=$false;msg='Fichier introuvable'} }
    try{
        $isDir = (Get-Item -LiteralPath $path -Force).PSIsContainer
        if($isDir){ return @{ok=$false;msg='Les dossiers ne peuvent pas etre mis en quarantaine'} }
        $qd = Get-QuarDir
        $id = [guid]::NewGuid().ToString('N').Substring(0,12)
        $dest = Join-Path $qd ("$id.quar")
        try{ takeown /f "$path" 2>&1 | Out-Null; icacls "$path" /grant "*S-1-5-32-544:F" /c /q 2>&1 | Out-Null }catch{}
        Move-Item -LiteralPath $path -Destination $dest -Force -EA Stop
        $m = @(Get-QuarManifest)
        $m += @{id=$id;original=[string]$path;date=(Get-Date -Format 'dd/MM/yyyy HH:mm:ss');reason=[string]$reason;file="$id.quar"}
        Save-QuarManifest $m
        @{ok=$true;msg='Mis en quarantaine';id=$id}
    }catch{ @{ok=$false;msg=$_.Exception.Message} }
}
function Restore-QuarItem($id){
    $m = @(Get-QuarManifest)
    $it = $m | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if(-not $it){ return @{ok=$false;msg='Introuvable'} }
    try{
        $src = Join-Path (Get-QuarDir) ([string]$it.file)
        $dstDir = Split-Path ([string]$it.original) -Parent
        if(-not(Test-Path $dstDir)){ [System.IO.Directory]::CreateDirectory($dstDir) | Out-Null }
        Move-Item -LiteralPath $src -Destination ([string]$it.original) -Force -EA Stop
        Save-QuarManifest @($m | Where-Object { $_.id -ne $id })
        @{ok=$true;msg='Fichier restaure'}
    }catch{ @{ok=$false;msg=$_.Exception.Message} }
}
function Remove-QuarItem($id){
    $m = @(Get-QuarManifest)
    $it = $m | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if(-not $it){ return @{ok=$false;msg='Introuvable'} }
    try{
        Remove-Item -LiteralPath (Join-Path (Get-QuarDir) ([string]$it.file)) -Force -EA SilentlyContinue
        Save-QuarManifest @($m | Where-Object { $_.id -ne $id })
        @{ok=$true;msg='Supprime definitivement'}
    }catch{ @{ok=$false;msg=$_.Exception.Message} }
}
function Get-WhiteList {
    $f = "$env:LOCALAPPDATA\OptiPC\whitelist.json"
    if(-not(Test-Path $f)){ return @() }
    try{ @([IO.File]::ReadAllText($f,[Text.Encoding]::UTF8) | ConvertFrom-Json) }catch{ @() }
}
# Une menace ignoree est memorisee par son identite exacte (nom + chemin) :
# elle ne reapparait plus, mais une NOUVELLE menace au meme endroit sera signalee.
function Get-OptiThreatKey($name,$path){ 'ID::' + ([string]$name).Trim().ToLower() + '||' + ([string]$path).Trim().ToLower() }
function Test-OptiIgnored($t,$wl){
    if(-not $t){ return $false }
    $k = Get-OptiThreatKey $t.name $t.path
    $p = ([string]$t.path).Trim().ToLower()
    foreach($w in @($wl)){
        $ws = ([string]$w).Trim().ToLower()
        if(-not $ws){ continue }
        if($ws -eq $k){ return $true }
        if(-not $ws.StartsWith('id::') -and $p -and $ws -eq $p){ return $true }   # anciennes exceptions (chemin seul)
    }
    $false
}
function Get-OptiThreatScore($list){
    $score = 100
    foreach($t in @($list)){ $score -= switch([string]$t.sev){ 'critical'{18} 'high'{9} 'medium'{4} 'low'{1} default{3} } }
    [Math]::Max(0,[Math]::Min(100,$score))
}
function Add-WhiteList($path,$name){
    $f = "$env:LOCALAPPDATA\OptiPC\whitelist.json"
    $d = Split-Path $f -Parent
    if(-not(Test-Path $d)){ [System.IO.Directory]::CreateDirectory($d) | Out-Null }
    $l = @(Get-WhiteList)
    $entry = if($name){ Get-OptiThreatKey $name $path } else { [string]$path }
    if($l -notcontains $entry){ $l += $entry }
    try{ (@($l) | ConvertTo-Json) | Out-File $f -Encoding UTF8 -Force; @{ok=$true;msg='Ajoute aux exceptions'} }catch{ @{ok=$false;msg=$_.Exception.Message} }
}
function Clear-WhiteList { try{ Remove-Item "$env:LOCALAPPDATA\OptiPC\whitelist.json" -Force -EA SilentlyContinue; @{ok=$true} }catch{ @{ok=$false} } }

function Get-SigInfo($p){
    try{
        $s = Get-AuthenticodeSignature -LiteralPath $p -EA SilentlyContinue
        if(-not $s){ return @{status='Unknown';signer='';valid=$false} }
        $cn = ''
        if($s.SignerCertificate){
            $sub = [string]$s.SignerCertificate.Subject
            if($sub -match 'CN=("([^"]+)"|([^,]+))'){ $cn = ($matches[2] + $matches[3]).Trim() }
        }
        @{status=[string]$s.Status;signer=$cn;valid=($s.Status -eq 'Valid')}
    }catch{ @{status='Error';signer='';valid=$false} }
}

function Test-TrustedVendor($txt){
    if(-not $txt){ return $false }
    $txt -match 'Microsoft|Windows|Google|Mozilla|Adobe|Intel|NVIDIA|Realtek|AMD|Apple|Oracle|Java|Kaspersky|ESET|Avast|AVG|Bitdefender|Norton|Symantec|McAfee|Malwarebytes|Avira|Valve|Steam|Discord|Spotify|OneDrive|Dropbox|WinRAR|VideoLAN|VLC|7-Zip|Igor Pavlov|Logitech|Corsair|Dell|HP Inc|Hewlett|Lenovo|ASUS|Acer|Canon|Epson|Brother|Cisco|Citrix|VMware|Zoom|Slack|Notion|JetBrains|Python Software|Node\.js|Git for Windows|Qt |Electron|TeamViewer|AnyDesk|Wondershare|CCleaner|Piriform|Samsung|Western Digital|Seagate|Crucial|Micron|Qualcomm|Broadcom|Synaptics|Elan|MediaTek|Razer|SteelSeries|Opera|Brave|Vivaldi|Firefox|Thunderbird|Chrome|Edge|WhatsApp|Telegram|Signal|Skype|Teams|Ringover|Deezer|Netflix|NordVPN|ExpressVPN|Proton|LibreOffice|Foxit|Notepad\+\+|PDF24|Epic Games|Ubisoft|Battle\.net|Riot Games|Webex|GoTo|SecureeTech|OptiPC'
}

function Test-IsOptiPCInstaller($name){
    [string]$name -match '(?i)^OptiPC(-Setup)?(-\d+(\.\d+){0,3})?\.exe$'
}

function Get-FileEntropy($p){
    try{
        $fs = [IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
        $len = [int][Math]::Min($fs.Length, 65536)
        if($len -le 0){ $fs.Close(); return 0 }
        $buf = New-Object byte[] $len
        [void]$fs.Read($buf,0,$len)
        $fs.Close()
        $c = New-Object int[] 256
        for($i=0;$i -lt $len;$i++){ $c[$buf[$i]]++ }
        $e = 0.0
        foreach($n in $c){ if($n -gt 0){ $pr = $n/$len; $e -= $pr * [Math]::Log($pr,2) } }
        [Math]::Round($e,2)
    }catch{ 0 }
}

function Test-Whitelisted($p,$wl){
    if([string]$p -match '(?i)\\SecureeTech\\|\\OptiPC\\|OptiPC\.(exe|ps1)|Vigilance\.(exe|ps1)'){ return $true }   # nos propres logiciels
    if(-not $p -or -not $wl){ return $false }
    foreach($w in $wl){ if([string]$w -and ([string]$p).ToLower() -eq ([string]$w).ToLower()){ return $true } }
    $false
}

function Invoke-DeepFolderScan($roots,$maxFiles,$depth,$maxSig,$label){
    $thr  = New-Object System.Collections.ArrayList
    $n    = 0
    $sigN = 0
    $wl   = @(Get-WhiteList)
    $selfDir = Get-OptiSelfDir
    $dangerExt = @('.scr','.pif','.vbs','.vbe','.jse','.hta','.wsf','.wsh','.cmd','.bat','.com','.cpl','.msc','.lnk','.reg')
    $exeExt    = @('.exe','.dll','.sys','.ocx','.scr','.cpl','.drv')
    $docExt    = 'pdf|doc|docx|xls|xlsx|ppt|pptx|jpg|jpeg|png|gif|txt|mp3|mp4|zip|rar|csv|htm|html'
    $sigQueue  = New-Object System.Collections.ArrayList

    foreach($root in $roots){
        if(-not $root -or -not (Test-Path -LiteralPath $root -EA SilentlyContinue)){ continue }
        try{
            $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -Depth $depth -EA SilentlyContinue | Select-Object -First $maxFiles)
        }catch{ $files = @() }
        foreach($f in $files){
            $n++
            $fp = $f.FullName
            if($selfDir -and $fp.ToLower().StartsWith($selfDir.ToLower())){ continue }
            if(Test-Whitelisted $fp $wl){ continue }
            $ext = $f.Extension.ToLower()
            $nm  = $f.Name

            if($nm -match "\.($docExt)\.(exe|scr|bat|cmd|com|pif|vbs|js|jar|msi)$"){
                [void]$thr.Add(@{cat='Fichier';sev='critical';name="Double extension : $nm";path=$fp;detail='Technique classique de camouflage de virus : le fichier se fait passer pour un document';canDel=$true})
                continue
            }
            if($nm -match '(?i)(facture|invoice|commande|colis|remboursement|impot|paiement|scan|document|cv)[-_ ]?\d*\.(exe|scr|js|vbs|jar|hta|cmd|bat)$'){
                [void]$thr.Add(@{cat='Fichier';sev='critical';name="Piece jointe piegee : $nm";path=$fp;detail='Nom typique des campagnes de phishing par e-mail';canDel=$true})
                continue
            }
            if($dangerExt -contains $ext){
                $sev = if($root -match 'Downloads|Telechargements|Temp'){'high'}else{'medium'}
                [void]$thr.Add(@{cat='Fichier';sev=$sev;name="Fichier executable $ext : $nm";path=$fp;detail="Les fichiers $ext peuvent lancer du code sans prevenir";canDel=$true})
                continue
            }
            if(($f.Attributes -band [IO.FileAttributes]::Hidden) -and ($f.Attributes -band [IO.FileAttributes]::System) -and ($exeExt -contains $ext)){
                [void]$thr.Add(@{cat='Fichier';sev='high';name="Executable cache : $nm";path=$fp;detail='Fichier marque cache + systeme dans un dossier utilisateur';canDel=$true})
                continue
            }
            if(($exeExt -contains $ext) -and $sigQueue.Count -lt ($maxSig*3)){ [void]$sigQueue.Add($f) }
        }
    }

    foreach($f in ($sigQueue | Sort-Object LastWriteTime -Descending | Select-Object -First $maxSig)){
        $sigN++
        $fp = $f.FullName
        $si = Get-SigInfo $fp
        if($si.status -eq 'HashMismatch'){
            [void]$thr.Add(@{cat='Integrite';sev='critical';name="Fichier modifie apres signature : $($f.Name)";path=$fp;detail='La signature numerique ne correspond plus au contenu : fichier probablement infecte';canDel=$true})
            continue
        }
        if($si.valid){
            if(-not (Test-TrustedVendor $si.signer)){
                # signe mais editeur inconnu : information seulement
            }
            continue
        }
        if(Test-TrustedVendor $fp){ continue }
        if(Test-IsOptiPCInstaller $f.Name){ continue }
        $ent = Get-FileEntropy $fp
        $inRisk = $fp -match '\\AppData\\|\\Temp\\|\\Downloads\\|\\Users\\Public\\|\\ProgramData\\'
        if($ent -ge 7.2 -and $inRisk){
            [void]$thr.Add(@{cat='Malware';sev='high';name="Executable compresse non signe : $($f.Name)";path=$fp;detail="Sans signature numerique et fortement compresse/chiffre (entropie $ent/8) : comportement typique d un virus empaquete";canDel=$true})
        } elseif($inRisk -and $f.Extension.ToLower() -eq '.exe'){
            [void]$thr.Add(@{cat='Fichier';sev='medium';name="Executable non signe : $($f.Name)";path=$fp;detail='Programme sans signature numerique dans un dossier a risque';canDel=$true})
        } elseif($ent -ge 7.5){
            [void]$thr.Add(@{cat='Fichier';sev='low';name="Fichier non signe et compresse : $($f.Name)";path=$fp;detail="Entropie $ent/8 - a verifier si vous ne connaissez pas ce programme";canDel=$true})
        }
    }
    @{threats=@($thr);files=($n+$sigN)}
}

function Invoke-ScriptScan($roots,$maxFiles){
    $thr = New-Object System.Collections.ArrayList
    $n = 0
    $wl = @(Get-WhiteList)
    $selfDir = Get-OptiSelfDir
    $pats = @(
        @{rx='(?i)FromBase64String'          ;t='Code PowerShell encode en Base64'}
        @{rx='(?i)-enc(odedcommand)?\s+[A-Za-z0-9+/]{40,}' ;t='Commande PowerShell encodee'}
        @{rx='(?i)(IEX|Invoke-Expression)\s*\(' ;t='Execution de code telecharge'}
        @{rx='(?i)DownloadString|DownloadFile|Invoke-WebRequest.*-OutFile' ;t='Telechargement automatique de fichier'}
        @{rx='(?i)certutil\s+.*-decode'      ;t='Decodage de fichier via certutil (technique malware)'}
        @{rx='(?i)bitsadmin\s+/transfer'     ;t='Telechargement furtif via bitsadmin'}
        @{rx='(?i)powershell.*-w(indowstyle)?\s+hidden' ;t='PowerShell lance en fenetre cachee'}
        @{rx='(?i)vssadmin\s+delete\s+shadows' ;t='Suppression des sauvegardes (indicateur ransomware)'}
        @{rx='(?i)Add-MpPreference\s+-ExclusionPath' ;t='Ajout d une exclusion antivirus'}
        @{rx='(?i)reg\s+add.*DisableAntiSpyware' ;t='Desactivation de l antivirus'}
    )
    foreach($root in $roots){
        if(-not(Test-Path -LiteralPath $root -EA SilentlyContinue)){ continue }
        try{
            $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -Depth 4 -EA SilentlyContinue |
                Where-Object { $_.Extension -match '(?i)^\.(ps1|psm1|vbs|js|bat|cmd|hta|wsf|jse|vbe)$' -and $_.Length -lt 3MB } |
                Select-Object -First $maxFiles)
        }catch{ $files = @() }
        foreach($f in $files){
            $n++
            if($selfDir -and $f.FullName.ToLower().StartsWith($selfDir.ToLower())){ continue }
            if(Test-Whitelisted $f.FullName $wl){ continue }
            $txt = ''
            try{ $txt = [IO.File]::ReadAllText($f.FullName) }catch{ continue }
            if(-not $txt){ continue }
            $hits = @()
            foreach($p in $pats){ if($txt -match $p.rx){ $hits += $p.t } }
            if($hits.Count -ge 2){
                [void]$thr.Add(@{cat='Script';sev='critical';name="Script malveillant : $($f.Name)";path=$f.FullName;detail=($hits -join ' + ');canDel=$true})
            } elseif($hits.Count -eq 1){
                [void]$thr.Add(@{cat='Script';sev='medium';name="Script suspect : $($f.Name)";path=$f.FullName;detail=$hits[0];canDel=$true})
            }
        }
    }
    @{threats=@($thr);files=$n}
}

$SCAN_DEF = @(
    @{id=1 ;name='Protection Windows'              ;quick=$true }
    @{id=2 ;name='Historique Windows Defender'     ;quick=$true }
    @{id=3 ;name='Lancement analyse Defender'      ;quick=$false}
    @{id=4 ;name='Processus en memoire'            ;quick=$true }
    @{id=5 ;name='Modules DLL charges'             ;quick=$false}
    @{id=6 ;name='Connexions reseau actives'       ;quick=$true }
    @{id=7 ;name='Registre - programmes au demarrage' ;quick=$true }
    @{id=8 ;name='Registre - Winlogon et DLL systeme' ;quick=$false}
    @{id=9 ;name='Taches planifiees'               ;quick=$true }
    @{id=10;name='Services Windows'                ;quick=$true }
    @{id=11;name='Persistance WMI'                 ;quick=$false}
    @{id=12;name='Detournement IFEO'               ;quick=$false}
    @{id=13;name='Detournement COM'                ;quick=$false}
    @{id=14;name='Navigateurs et extensions'       ;quick=$true }
    @{id=15;name='Raccourcis detournes'            ;quick=$false}
    @{id=16;name='Reseau : hosts, DNS, proxy'      ;quick=$true }
    @{id=17;name='Certificats racine'              ;quick=$false}
    @{id=18;name='Analyse du dossier Telechargements' ;quick=$true }
    @{id=19;name='Analyse Bureau et Documents'     ;quick=$false}
    @{id=20;name='Analyse AppData (Roaming)'       ;quick=$false}
    @{id=21;name='Analyse AppData (Local)'         ;quick=$false}
    @{id=22;name='Analyse des dossiers temporaires';quick=$true }
    @{id=23;name='Analyse ProgramData et Public'   ;quick=$false}
    @{id=24;name='Scripts suspects'                ;quick=$false}
    @{id=25;name='Crypto-mineurs'                  ;quick=$true }
    @{id=26;name='Ransomware'                      ;quick=$true }
    @{id=27;name='Rootkits et pilotes'             ;quick=$false}
    @{id=28;name='Logiciels indesirables (PUP)'    ;quick=$true }
    @{id=29;name='Comptes et acces a distance'     ;quick=$false}
    @{id=30;name='Journaux d evenements Windows'   ;quick=$false}
    @{id=31;name='Resultats Windows Defender'      ;quick=$false}
    @{id=32;name='Calcul du score de securite'     ;quick=$true }
)
function Get-ScanPlan($mode){
    if($mode -eq 'quick'){ return @($SCAN_DEF | Where-Object { $_.quick }) }
    @($SCAN_DEF)
}

function Start-DefenderFullScan {
    try{
        $mpc = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
        if(-not(Test-Path $mpc)){
            $plat = Get-ChildItem "$env:ProgramData\Microsoft\Windows Defender\Platform" -Directory -EA SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
            if($plat){ $mpc = Join-Path $plat.FullName 'MpCmdRun.exe' }
        }
        if(-not($mpc -and (Test-Path $mpc))){ return @{ok=$false;msg='Windows Defender introuvable sur ce PC'} }
        [IO.File]::WriteAllText("$env:TEMP\optipc_deffullstart.txt",(Get-Date -Format 'o'),[Text.Encoding]::UTF8)
        $p = Start-Process $mpc -ArgumentList '-Scan','-ScanType','2' -WindowStyle Hidden -PassThru -EA SilentlyContinue
        if($p){ [IO.File]::WriteAllText("$env:TEMP\optipc_deffullpid.txt",[string]$p.Id,[Text.Encoding]::UTF8) }
        @{ok=$true;msg='Analyse complete Windows Defender lancee (20 a 60 minutes). Vous pouvez continuer a utiliser OptiPC.'}
    }catch{ @{ok=$false;msg=$_.Exception.Message} }
}
function Get-DefenderScanStatus {
    $r = @{running=$false;threats=@();elapsed=''}
    try{
        $pf = "$env:TEMP\optipc_deffullpid.txt"
        if(Test-Path $pf){
            $dp = [int]([IO.File]::ReadAllText($pf,[Text.Encoding]::UTF8))
            if(Get-Process -Id $dp -EA SilentlyContinue){ $r.running = $true }
            else { Remove-Item $pf -Force -EA SilentlyContinue }
        }
        $sf = "$env:TEMP\optipc_deffullstart.txt"
        if(Test-Path $sf){
            $st = [datetime]::Parse([IO.File]::ReadAllText($sf,[Text.Encoding]::UTF8))
            $r.elapsed = '{0:hh}h{0:mm}m' -f ((Get-Date)-$st)
            $list = New-Object System.Collections.ArrayList
            foreach($td in @(Get-MpThreatDetection -EA SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $st })){
                $tn = 'Menace'
                try{ $ti = Get-MpThreat -ThreatID $td.ThreatID -EA SilentlyContinue | Select-Object -First 1; if($ti){ $tn = [string]$ti.ThreatName } }catch{}
                [void]$list.Add(@{name=$tn;path=$(if($td.Resources){([string](@($td.Resources)[0])) -replace '^file:_',''}else{''})})
            }
            $r.threats = @($list)
        }
    }catch{}
    $r
}

function Get-OptiSelfDir {
    try{
        $cfg = "$env:LOCALAPPDATA\OptiPC\optipc.cfg"
        if(Test-Path $cfg){
            $p = (Get-Content $cfg -Raw -EA SilentlyContinue).Trim()
            if($p){ return (Split-Path $p -Parent) }
        }
    }catch{}
    $null
}
function Test-UnderSelfDir($path){
    $d = Get-OptiSelfDir
    if(-not $d -or -not $path){ return $false }
    ([string]$path).ToLower().StartsWith(([string]$d).ToLower())
}

function Get-SettingsFile { "$env:LOCALAPPDATA\OptiPC\settings.json" }
function Get-SettingsKeys { @('notifPro','notifClean','notifScan','notifStartup','notifThreat','sounds','openAtStartup') }
function Get-ConsentFile { "$env:LOCALAPPDATA\OptiPC\consent.json" }
function Get-ConsentStatus {
    $f = Get-ConsentFile
    if(-not(Test-Path $f)){ return @{accepted=$false} }
    try{
        $c = [IO.File]::ReadAllText($f,[Text.Encoding]::UTF8) | ConvertFrom-Json
        @{accepted=[bool]$c.accepted; version=[string]$c.version; date=[string]$c.date; user=[string]$c.user}
    }catch{ @{accepted=$false} }
}
function Set-Consent($version) {
    # Trace de l'acceptation : date, version des documents, session Windows.
    # C'est cette trace qui prouve que le client a bien accepte le CLUF.
    $d = Split-Path (Get-ConsentFile) -Parent
    if(-not(Test-Path $d)){ [System.IO.Directory]::CreateDirectory($d) | Out-Null }
    $rec = @{
        accepted = $true
        version  = [string]$version
        date     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        user     = $env:USERNAME
        machine  = $env:COMPUTERNAME
    }
    try{
        ($rec | ConvertTo-Json -Compress) | Out-File (Get-ConsentFile) -Encoding UTF8 -Force
        @{success=$true;consent=$rec}
    }catch{ @{success=$false;error=$_.Exception.Message} }
}
function Open-ExternalUrl($url) {
    # Liste blanche stricte : le logiciel n'ouvre que nos propres pages.
    if([string]$url -notmatch '^https://(www\.)?secureetech\.com(/|$)'){
        return @{success=$false;error='Adresse non autorisee'}
    }
    try{ Start-Process ([string]$url); @{success=$true} }
    catch{ @{success=$false;error=$_.Exception.Message} }
}

# ══════════════════════════════════════════════════════════════════════════
#  MISES A JOUR
#  Le poste interroge api.secureetech.com. Verification en trois temps :
#  numero de version, empreinte SHA-256 du fichier telecharge, puis
#  signature Authenticode. Sans les trois, rien n'est installe.
# ══════════════════════════════════════════════════════════════════════════
function Get-OptiPCVersion { '2.0.0' }

function Get-MachineFingerprint {
    # Empreinte stable de l'ordinateur. On combine trois sources car aucune
    # n'est fiable seule : l'UUID SMBIOS est a zero sur certains lots OEM
    # entiers, le MachineGuid change a la reinstallation de Windows, et le
    # numero de serie du volume change au formatage.
    # Le tout est hache : aucun identifiant materiel n'est conserve en clair.
    $parts = @()
    try {
        $u = (Get-CimInstance Win32_ComputerSystemProduct -EA SilentlyContinue).UUID
        if($u -and $u -notmatch '^[0\-]+$' -and $u -ne 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF'){ $parts += "U:$u" }
    } catch {}
    try {
        $g = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -EA SilentlyContinue).MachineGuid
        if($g){ $parts += "G:$g" }
    } catch {}
    try {
        $v = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA SilentlyContinue).VolumeSerialNumber
        if($v){ $parts += "V:$v" }
    } catch {}
    if($parts.Count -eq 0){ $parts += "N:$env:COMPUTERNAME-$env:USERNAME" }
    $raw = ($parts -join '|')
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))
        $sha.Dispose()
        ([BitConverter]::ToString($h) -replace '-','').ToLower()
    } catch {
        ([string]$raw.GetHashCode()).Replace('-','n').PadRight(32,'0')
    }
}
function Get-OptiPCApiBase { 'https://api.secureetech.com' }
function Get-OptiPCPublisher { 'H2OCONSULTING' }   # doit figurer dans le certificat de signature

function Get-UpdateStampFile { "$env:LOCALAPPDATA\OptiPC\update.stamp" }

# ═════════════════════════════════════════════════════════════════════════════
# RESILIENCE RESEAU/DNS
# Constate le 14/09/2026 : une box/FAI cliente resolvait google.com mais pas
# api.secureetech.com, alors que le service etait parfaitement joignable et
# fonctionnel. OptiPC tourne chez des centaines de PC avec des box tres
# variees (et parfois un DNS local capricieux, filtrant, ou en panne) : on ne
# peut pas compter sur le fait que chaque poste resout correctement le nom de
# domaine. Quand Invoke-RestMethod echoue SANS meme recevoir de reponse HTTP
# (donc probablement un probleme de connexion/DNS, pas un refus du serveur),
# on retente en resolvant le nom via DNS-over-HTTPS (Cloudflare puis Google :
# de simples appels HTTPS vers une IP fixe, qui eux n'ont donc pas besoin du
# DNS local) puis en s'y connectant directement avec curl.exe - present
# nativement depuis Windows 10 1803 - qui sait garder le bon Host/SNI pour
# que le certificat TLS reste valide.
# ═════════════════════════════════════════════════════════════════════════════
function Resolve-OptiPCViaDoH($hostname) {
    # Initialisation paresseuse et DANS la fonction (pas en instruction de
    # premier niveau) : le pool de runspaces de ce logiciel precharge les
    # fonctions individuellement (voir plus bas, "PERFORMANCE : precharger
    # les fonctions") et ignore toute instruction hors fonction - une
    # variable initialisee en dehors d'une fonction ne survivrait pas a ce
    # prechargement.
    if(-not $script:OptiPCDnsCache){ $script:OptiPCDnsCache = @{} }
    $now = Get-Date
    if($script:OptiPCDnsCache.ContainsKey($hostname)){
        $c = $script:OptiPCDnsCache[$hostname]
        if(($now - $c.at).TotalMinutes -lt 10){ return $c.ip }
    }
    $providers = @(
        @{ Uri = "https://1.1.1.1/dns-query?name=$hostname&type=A"; Headers = @{ Accept = 'application/dns-json' } }
        @{ Uri = "https://8.8.8.8/resolve?name=$hostname&type=A";   Headers = @{} }
    )
    foreach($p in $providers){
        try {
            $r = Invoke-RestMethod -Uri $p.Uri -Headers $p.Headers -TimeoutSec 5 -UseBasicParsing
            $ip = $r.Answer | Where-Object { $_.type -eq 1 } | Select-Object -First 1 -ExpandProperty data -EA SilentlyContinue
            if($ip -and $ip -match '^\d{1,3}(\.\d{1,3}){3}$'){
                $script:OptiPCDnsCache[$hostname] = @{ ip = $ip; at = $now }
                return $ip
            }
        } catch {}
    }
    $null
}

function Invoke-OptiPCCurlDirect($url, $method, $bodyObj, $timeoutSec, $ip) {
    $curlCmd = Get-Command curl.exe -EA SilentlyContinue
    if(-not $curlCmd){ return $null }
    $uri = [Uri]$url
    $port = if($uri.Port -gt 0){ $uri.Port } else { 443 }
    $resolveArg = '{0}:{1}:{2}' -f $uri.Host, $port, $ip
    $tmpOut  = [IO.Path]::GetTempFileName()
    $tmpBody = $null
    try {
        $curlArgs = @(
            '--resolve', $resolveArg,
            '-sS', '-X', $(if($method){$method}else{'GET'}),
            '--max-time', [string]$timeoutSec,
            '--tlsv1.2',
            '-o', $tmpOut,
            '-w', 'HTTPSTATUS:%{http_code}'
        )
        if($bodyObj){
            $tmpBody = [IO.Path]::GetTempFileName()
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($tmpBody, ($bodyObj | ConvertTo-Json -Compress), $utf8NoBom)
            $curlArgs += @('-H', 'Content-Type: application/json; charset=utf-8', '--data-binary', "@$tmpBody")
        }
        $curlArgs += $url
        $out = & $curlCmd.Source @curlArgs 2>&1
        $exitCode = $LASTEXITCODE
        $body = ''
        try { $body = [IO.File]::ReadAllText($tmpOut, [Text.Encoding]::UTF8) } catch {}
        $code = 0
        if(([string]$out) -match 'HTTPSTATUS:(\d+)'){ $code = [int]$matches[1] }
        if($exitCode -ne 0 -or $code -eq 0){ return $null }  # curl non plus n'a pas pu se connecter : on abandonne le repli
        if($code -ge 200 -and $code -lt 300){
            $data = $null
            try { $data = $body | ConvertFrom-Json } catch {}
            return @{ ok = $true; data = $data }
        }
        $human = ''
        try { $j = $body | ConvertFrom-Json; if($j.message){ $human = [string]$j.message } } catch {}
        return @{ ok = $false; status = $code; error = "HTTP $code"; server = $body; serverMessage = $human }
    } catch {
        $null
    } finally {
        # $tmpBody peut etre $null (requete GET sans corps) : Remove-Item leve
        # une erreur de LIAISON DE PARAMETRE (pas une erreur "normale") si on
        # lui passe $null dans le tableau de chemins, et -ErrorAction ne la
        # supprime pas. On filtre donc les valeurs non-nulles avant l'appel.
        @($tmpOut, $tmpBody) | Where-Object { $_ } | Remove-Item -Force -EA SilentlyContinue
    }
}

function Invoke-OptiPCWeb($url, $method, $bodyObj, $timeoutSec) {
    # TLS 1.2/1.3 : Windows 10/11 en PowerShell 5.1 negocie encore TLS 1.0 par
    # defaut sur certaines configurations, ce qui ferait echouer chaque appel.
    try {
        $sp = [Net.SecurityProtocolType]::Tls12
        try { $sp = $sp -bor [Net.SecurityProtocolType]::Tls13 } catch {}
        [Net.ServicePointManager]::SecurityProtocol = $sp
    } catch {}
    if(-not $timeoutSec){ $timeoutSec = 20 }
    try {
        $p = @{ Uri = $url; Method = $(if($method){$method}else{'GET'}); TimeoutSec = $timeoutSec; UseBasicParsing = $true }
        if($bodyObj){
            $p.Body = ($bodyObj | ConvertTo-Json -Compress)
            $p.ContentType = 'application/json; charset=utf-8'
        }
        # Proxy d'entreprise eventuel : on reprend celui de Windows.
        try {
            $px = [Net.WebRequest]::GetSystemWebProxy().GetProxy([Uri]$url)
            if($px -and $px.AbsoluteUri -ne ([Uri]$url).AbsoluteUri){
                $p.Proxy = $px.AbsoluteUri
                $p.ProxyUseDefaultCredentials = $true
            }
        } catch {}
        $r = Invoke-RestMethod @p
        @{ ok = $true; data = $r }
    } catch {
        $ex = $_.Exception

        # Aucune reponse HTTP recue du tout (par opposition a un code d'erreur
        # renvoye par le serveur) : c'est le signe d'un probleme de connexion
        # ou de DNS local. On tente le repli DNS-over-HTTPS + curl.exe avant
        # d'abandonner - exactement le cas rencontre le 14/09/2026.
        $hasResponse = $false
        try { if($ex.Response){ $hasResponse = $true } } catch {}
        if(-not $hasResponse){
            try {
                $hostName = ([Uri]$url).Host
                $ip = Resolve-OptiPCViaDoH $hostName
                if($ip){
                    $fallback = Invoke-OptiPCCurlDirect $url $method $bodyObj $timeoutSec $ip
                    if($fallback){ return $fallback }
                }
            } catch {}
        }

        # Lecture ROBUSTE du code HTTP et du message renvoye par le serveur.
        # Sans cela, une reponse "cle inconnue" ou "poste deja utilise" etait
        # confondue avec une panne de reseau.
        $code = 0
        $srvMsg = ''
        foreach($try in 1..3){
            try {
                if($try -eq 1 -and $ex.Response){ $code = [int]$ex.Response.StatusCode }
                elseif($try -eq 2 -and $_.PSObject.Properties.Name -contains 'ErrorDetails'){ }
                elseif($try -eq 3 -and $ex.InnerException -and $ex.InnerException.Response){ $code = [int]$ex.InnerException.Response.StatusCode }
            } catch {}
            if($code -gt 0){ break }
        }
        if($code -eq 0){
            # Dernier recours : extraire le code du texte de l'erreur (ex. "(409) Conflict")
            try { if("$($ex.Message)" -match '\((\d{3})\)'){ $code = [int]$matches[1] } } catch {}
        }
        # Corps de la reponse : PowerShell 5.1 le place dans ErrorDetails
        try { if($_.ErrorDetails -and $_.ErrorDetails.Message){ $srvMsg = [string]$_.ErrorDetails.Message } } catch {}
        if(-not $srvMsg){
            try {
                $st = $ex.Response.GetResponseStream()
                if($st){ $srvMsg = (New-Object IO.StreamReader($st)).ReadToEnd() }
            } catch {}
        }
        $human = ''
        try { if($srvMsg){ $j = $srvMsg | ConvertFrom-Json; if($j.message){ $human = [string]$j.message } } } catch {}
        @{ ok = $false; status = $code; error = $ex.Message; server = $srvMsg; serverMessage = $human }
    }
}
function Compare-OptiPCVersion($a, $b) {
    $pa = @(([string]$a).Split('.') | ForEach-Object { [int]($_ -replace '\D','0') })
    $pb = @(([string]$b).Split('.') | ForEach-Object { [int]($_ -replace '\D','0') })
    for($i = 0; $i -lt 3; $i++){
        $x = if($i -lt $pa.Count){ $pa[$i] } else { 0 }
        $y = if($i -lt $pb.Count){ $pb[$i] } else { 0 }
        if($x -ne $y){ return $(if($x -gt $y){1}else{-1}) }
    }
    0
}

function Get-UpdateLastCheck {
    $f = Get-UpdateStampFile
    if(-not(Test-Path $f)){ return $null }
    try { [datetime]::Parse(([IO.File]::ReadAllText($f)).Trim()) } catch { $null }
}

function Set-UpdateLastCheck {
    $f = Get-UpdateStampFile
    $d = Split-Path $f -Parent
    try {
        if(-not(Test-Path $d)){ [System.IO.Directory]::CreateDirectory($d) | Out-Null }
        [IO.File]::WriteAllText($f, (Get-Date -Format 'o'))
    } catch {}
}

function Test-UpdateDue($intervalDays) {
    # Regle : on verifie au demarrage, mais au plus une fois tous les
    # $intervalDays jours. Un client qui allume son PC tous les matins
    # n'interroge pas le serveur 30 fois par mois pour rien.
    if(-not $intervalDays){ $intervalDays = 30 }
    $last = Get-UpdateLastCheck
    if(-not $last){ return $true }
    ((Get-Date) - $last).TotalDays -ge $intervalDays
}

function Get-OptiPCUpdate($force) {
    $cur = Get-OptiPCVersion
    if(-not $force -and -not (Test-UpdateDue (1/24))){
        return @{ checked = $false; update_available = $false; current = $cur; reason = 'deja_verifie' }
    }
    $mid = ''
    try { $mid = Get-MachineFingerprint } catch {}
    $url = (Get-OptiPCApiBase) + "/v1/update?current=$cur&channel=stable&machine=$mid"
    $r = Invoke-OptiPCWeb $url 'GET' $null 15
    Set-UpdateLastCheck
    if(-not $r.ok){
        return @{ checked = $true; update_available = $false; current = $cur; offline = $true; error = $r.error }
    }
    $d = $r.data
    if(-not $d.update_available){
        return @{ checked = $true; update_available = $false; current = $cur; latest = [string]$d.latest }
    }
    if((Compare-OptiPCVersion $d.version $cur) -le 0){
        return @{ checked = $true; update_available = $false; current = $cur }
    }
    @{
        checked          = $true
        update_available = $true
        current          = $cur
        version          = [string]$d.version
        url              = [string]$d.url
        sha256           = [string]$d.sha256
        size             = [long]$d.size
        mandatory        = [bool]$d.mandatory
        notes            = [string]$d.notes
    }
}

function Get-FileSha256($path) {
    try { (Get-FileHash -Path $path -Algorithm SHA256 -EA Stop).Hash.ToUpper() } catch { '' }
}

function Install-OptiPCUpdate($url, $expectedSha) {
    if([string]::IsNullOrWhiteSpace($url)){ return @{ success = $false; error = "Adresse de telechargement absente." } }
    if($url -notmatch '^https://'){ return @{ success = $false; error = "Telechargement refuse : la liaison n'est pas securisee." } }

    $dir = "$env:LOCALAPPDATA\OptiPC\updates"
    try { if(-not(Test-Path $dir)){ [System.IO.Directory]::CreateDirectory($dir) | Out-Null } } catch {}
    $name = [IO.Path]::GetFileName(($url -split '\?')[0])
    if(-not $name){ $name = 'OptiPC-Setup.exe' }
    $dest = Join-Path $dir $name

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
    } catch {}
    try {
        Remove-Item $dest -Force -EA SilentlyContinue
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 900 -EA Stop
    } catch {
        # Meme repli que pour les appels API (cf. Invoke-OptiPCWeb) : si aucune
        # reponse HTTP n'a ete recue du tout, on tente une resolution DNS-over-
        # HTTPS puis un telechargement direct via curl.exe avant d'abandonner.
        $hasResponse = $false
        try { if($_.Exception.Response){ $hasResponse = $true } } catch {}
        $downloaded = $false
        if(-not $hasResponse){
            try {
                $hostName = ([Uri]$url).Host
                $ip = Resolve-OptiPCViaDoH $hostName
                $curlCmd = if($ip){ Get-Command curl.exe -EA SilentlyContinue } else { $null }
                if($ip -and $curlCmd){
                    $uri = [Uri]$url
                    $port = if($uri.Port -gt 0){ $uri.Port } else { 443 }
                    $resolveArg = '{0}:{1}:{2}' -f $uri.Host, $port, $ip
                    Remove-Item $dest -Force -EA SilentlyContinue
                    & $curlCmd.Source --resolve $resolveArg -sS --max-time 900 --tlsv1.2 -o $dest $url 2>&1 | Out-Null
                    if($LASTEXITCODE -eq 0 -and (Test-Path $dest)){ $downloaded = $true }
                }
            } catch {}
        }
        if(-not $downloaded){
            return @{ success = $false; error = "Telechargement impossible : $($_.Exception.Message)" }
        }
    }
    if(-not(Test-Path $dest)){ return @{ success = $false; error = "Le fichier n'a pas ete recu." } }

    # 1) Empreinte du fichier
    if($expectedSha){
        $got = Get-FileSha256 $dest
        if($got -ne ([string]$expectedSha).ToUpper()){
            Remove-Item $dest -Force -EA SilentlyContinue
            return @{ success = $false; error = "Le fichier telecharge est corrompu ou a ete modifie. Installation annulee." }
        }
    }

    # 2) Signature Authenticode : c'est la verification decisive. Elle protege
    #    meme si le serveur de mise a jour venait a etre compromis.
    try {
        $sig = Get-AuthenticodeSignature $dest -EA Stop
        if($sig.Status -ne 'Valid'){
            Remove-Item $dest -Force -EA SilentlyContinue
            return @{ success = $false; error = "Signature numerique absente ou invalide ($($sig.Status)). Installation annulee." }
        }
        $subject = ''
        try { $subject = [string]$sig.SignerCertificate.Subject } catch {}
        if($subject -notmatch [regex]::Escape((Get-OptiPCPublisher))){
            Remove-Item $dest -Force -EA SilentlyContinue
            return @{ success = $false; error = "Le fichier n'est pas signe par l'editeur d'OptiPC. Installation annulee." }
        }
    } catch {
        Remove-Item $dest -Force -EA SilentlyContinue
        return @{ success = $false; error = "Verification de la signature impossible. Installation annulee." }
    }

    try {
        Start-Process $dest -ArgumentList '/SILENT','/NORESTART' -EA Stop
        try { [IO.File]::WriteAllText("$env:TEMP\optipc_quit.flag","quit") } catch {}
        @{ success = $true; message = "Installation lancee. OptiPC va redemarrer." }
    } catch {
        @{ success = $false; error = "Lancement de l'installation impossible : $($_.Exception.Message)" }
    }
}

function Get-OptiSettings {
    $def = @{notifPro=$true;notifClean=$true;notifScan=$true;notifStartup=$true;notifThreat=$true;sounds=$true;openAtStartup=$true}
    $f = Get-SettingsFile
    if(-not(Test-Path $f)){ return $def }
    try{
        $s = [IO.File]::ReadAllText($f,[Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach($k in (Get-SettingsKeys)){
            if($null -ne $s.$k){ $def[$k] = [bool]$s.$k }
        }
    }catch{}
    $def
}
function Set-OptiSettings($body) {
    $d = Split-Path (Get-SettingsFile) -Parent
    if(-not(Test-Path $d)){ [System.IO.Directory]::CreateDirectory($d) | Out-Null }
    $cur = Get-OptiSettings
    foreach($k in (Get-SettingsKeys)){
        if($null -ne $body.$k){ $cur[$k] = [bool]$body.$k }
    }
    try{
        ($cur | ConvertTo-Json -Compress) | Out-File (Get-SettingsFile) -Encoding UTF8 -Force
        @{success=$true;settings=$cur}
    }catch{ @{success=$false;error=$_.Exception.Message} }
}

function Get-ScanWorkDir {
    # Le dossier temporaire de Windows est parfois inaccessible en ecriture :
    # antivirus tiers, nettoyage automatique, strategie d'entreprise. Quand
    # l'ecriture echouait, le fichier d'etat n'existait pas et l'analyse
    # restait bloquee a 0 % sans le moindre message. On choisit donc le
    # premier emplacement REELLEMENT inscriptible.
    foreach($d in @("$env:LOCALAPPDATA\OptiPC", "$env:TEMP", "$env:USERPROFILE\OptiPC")){
        if(-not $d){ continue }
        try {
            if(-not(Test-Path $d)){ [System.IO.Directory]::CreateDirectory($d) | Out-Null }
            $t = Join-Path $d ("w_" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".tmp")
            [IO.File]::WriteAllText($t, 'ok', [Text.Encoding]::UTF8)
            Remove-Item $t -Force -EA SilentlyContinue
            return $d
        } catch {}
    }
    return $env:TEMP
}
function Get-ScanStateFile  { Join-Path (Get-ScanWorkDir) 'OptiPC_ScanState.json' }
function Get-ScanResultFile { Join-Path (Get-ScanWorkDir) 'OptiPC_ScanResult.json' }
function Get-ScanStopFlag   { Join-Path (Get-ScanWorkDir) 'OptiPC_ScanStop.flag' }
function Request-ScanStop {
    try{ [IO.File]::WriteAllText((Get-ScanStopFlag),'1',[Text.Encoding]::UTF8); @{success=$true} }
    catch{ @{success=$false;error=$_.Exception.Message} }
}

# -- Limites de la version gratuite (27/10/2026) ------------------------------
# startup : 2 programmes retires du demarrage au total ; uninstall : 3 desinstallations par mois.
function Use-OptiFreeQuota([string]$kind, [int]$max){
  try{ if(Test-IsPro){ return @{ok=$true} } }catch{}
  $dir = "$env:LOCALAPPDATA\OptiPC"
  $f = "$dir\free_quota.json"
  $q = @{}
  try{
    if(Test-Path $f){
      $o = Get-Content $f -Raw | ConvertFrom-Json
      foreach($p in $o.PSObject.Properties){ $q[$p.Name] = [string]$p.Value }
    }
  }catch{}
  $cle = $kind
  if($kind -eq 'uninstall'){ $cle = 'uninstall_' + (Get-Date -Format 'yyyy-MM') }
  $n = 0; try{ $n = [int]$q[$cle] }catch{}
  if($n -ge $max){
    return @{ok=$false;success=$false;premium=$true;quota=$kind;max=$max;msg="Limite de la version gratuite atteinte"}
  }
  $q[$cle] = [string]($n + 1)
  try{
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    [IO.File]::WriteAllText($f, ($q | ConvertTo-Json), [Text.Encoding]::UTF8)
  }catch{}
  @{ok=$true;used=($n + 1);max=$max}
}
