# ============================================================
#  OptiPC 2.0 - Nouvelles fonctions du moteur
#  (Espace disque, sante du PC, reseau, logiciels a mettre a jour,
#   points de restauration, historique du score, rappel technicien,
#   planification et rappels executes par le logiciel natif)
#  Compatible Windows PowerShell 5.1 uniquement : pas de ?:, pas de ??.
# ============================================================

function Get-OptiDataDir {
    $d = "$env:LOCALAPPDATA\OptiPC"
    if(-not (Test-Path $d)){ try{ [System.IO.Directory]::CreateDirectory($d) | Out-Null }catch{} }
    $d
}

function Read-OptiJsonFile($path){
    try{
        if(Test-Path -LiteralPath $path){
            $t = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
            if($t){ return ($t | ConvertFrom-Json) }
        }
    }catch{}
    $null
}

function Write-OptiJsonFile($path, $obj){
    try{ [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 8 -Compress), [Text.Encoding]::UTF8); return $true }catch{ return $false }
}

# ─── ESPACE DISQUE ─────────────────────────────────────────────────────────────

function Get-OptiUserRoots {
    $roots = New-Object System.Collections.Generic.List[object]
    $add = {
        param($label,$path)
        if($path -and (Test-Path -LiteralPath $path -EA SilentlyContinue)){
            foreach($r in $roots){ if($r.path -ieq $path){ return } }
            $roots.Add(@{label=$label;path=$path})
        }
    }
    $dl = $null
    try{ $dl = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -EA Stop).'{374DE290-123F-4565-9164-39C4925E467B}' }catch{}
    if($dl){ $dl = [Environment]::ExpandEnvironmentVariables([string]$dl) } else { $dl = Join-Path $env:USERPROFILE 'Downloads' }
    & $add 'Telechargements' $dl
    & $add 'Bureau'    ([Environment]::GetFolderPath('Desktop'))
    & $add 'Documents' ([Environment]::GetFolderPath('MyDocuments'))
    & $add 'Images'    ([Environment]::GetFolderPath('MyPictures'))
    & $add 'Videos'    ([Environment]::GetFolderPath('MyVideos'))
    & $add 'Musique'   ([Environment]::GetFolderPath('MyMusic'))
    $roots.ToArray()
}

function Get-OptiFileKind($ext){
    $e = ([string]$ext).ToLower()
    if($e -match '^\.(jpg|jpeg|png|gif|bmp|tif|tiff|webp|heic|heif|raw|cr2|nef|arw|dng|svg)$'){ return 'Images' }
    if($e -match '^\.(mp4|avi|mkv|mov|wmv|flv|m4v|webm|ts|vob|mpg|mpeg|3gp|mts|m2ts)$'){ return 'Videos' }
    if($e -match '^\.(mp3|flac|wav|aac|ogg|wma|m4a|opus|aiff)$'){ return 'Musique' }
    if($e -match '^\.(pdf|doc|docx|xls|xlsx|ppt|pptx|txt|csv|odt|ods|odp|rtf|pages|numbers|key|epub)$'){ return 'Documents' }
    if($e -match '^\.(zip|rar|7z|tar|gz|bz2|xz|iso|img|cab)$'){ return 'Archives' }
    if($e -match '^\.(exe|msi|msix|msixbundle|appx|dmg|apk)$'){ return 'Installateurs' }
    'Autres'
}

function Get-OptiSpaceScan($force){
    if(-not $force){
        $c = Get-OptiCache 'space' 600
        if($c){ return $c }
    }
    # Version rapide en C# (dans OptiPC.exe) ; la version PowerShell ci-dessous sert de secours.
    $fast = 'OptiPC.SpaceScanner' -as [type]
    if($fast){
        try{
            $rootsF = Get-OptiUserRoots
            $dlF = ($rootsF | Where-Object { $_.label -eq 'Telechargements' } | Select-Object -First 1)
            $res = $fast::Scan([string[]]@($rootsF | ForEach-Object { [string]$_.path }), $(if($dlF){ [string]$dlF.path } else { '' }), 60, 1500000, 30)
            Set-OptiCache 'space' $res
            return $res
        }catch{ try{ Write-OptiErrorLog ("SpaceScanner : " + $_.Exception.Message) }catch{} }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $maxSeconds = 75
    $maxFiles = 400000
    $roots = Get-OptiUserRoots
    $dlRoot = ($roots | Where-Object { $_.label -eq 'Telechargements' } | Select-Object -First 1)
    $dlPath = if($dlRoot){ [string]$dlRoot.path } else { '' }

    # Attributs a ne JAMAIS ouvrir : fichiers OneDrive "en ligne uniquement"
    # (les lire forcerait leur telechargement) et liens symboliques/jonctions.
    $skipAttr = [int]([IO.FileAttributes]::Offline) -bor 0x00040000 -bor 0x00400000
    $files = New-Object System.Collections.Generic.List[object]
    $dirs  = New-Object System.Collections.Generic.List[string]
    $dirsWithFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $catSizes = @{}
    foreach($k in @('Videos','Images','Telechargements','Musique','Documents','Archives','Installateurs','Autres')){ $catSizes[$k] = [long]0 }
    $partial = $false
    $scanned = 0

    foreach($root in $roots){
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push([string]$root.path)
        $isDl = ($dlPath -and ([string]$root.path) -ieq $dlPath)
        while($stack.Count -gt 0){
            if($sw.Elapsed.TotalSeconds -gt $maxSeconds -or $scanned -ge $maxFiles){ $partial = $true; break }
            $dir = $stack.Pop()
            $di = $null
            try{ $di = New-Object IO.DirectoryInfo($dir) }catch{ continue }
            $entries = $null
            try{ $entries = $di.GetFileSystemInfos() }catch{ continue }
            if($dir -ine [string]$root.path){ $dirs.Add($dir) }
            foreach($e in $entries){
                try{
                    $attr = [int]$e.Attributes
                    if($e -is [IO.DirectoryInfo]){
                        if(($attr -band [int][IO.FileAttributes]::ReparsePoint) -ne 0){ $dirsWithFiles.Add($e.FullName) | Out-Null; continue }
                        if(($attr -band [int][IO.FileAttributes]::System) -ne 0){ $dirsWithFiles.Add($e.FullName) | Out-Null; continue }
                        $n = $e.Name
                        if($n -match '^(\$RECYCLE\.BIN|System Volume Information|node_modules|\.git|AppData)$'){ $dirsWithFiles.Add($e.FullName) | Out-Null; continue }
                        $stack.Push($e.FullName)
                    } else {
                        $scanned++
                        # Tout fichier (meme ignore) rend son dossier "non vide"
                        $p = $e.DirectoryName
                        while($p -and $dirsWithFiles.Add($p)){ $p = [IO.Path]::GetDirectoryName($p) }
                        if(($attr -band $skipAttr) -ne 0){ continue }
                        if(($attr -band [int][IO.FileAttributes]::ReparsePoint) -ne 0){ continue }
                        $len = [long]$e.Length
                        $kind = Get-OptiFileKind $e.Extension
                        if($isDl){ $catSizes['Telechargements'] += $len } else { $catSizes[$kind] += $len }
                        $files.Add([pscustomobject]@{path=$e.FullName;name=$e.Name;dir=$e.DirectoryName;len=$len;mod=$e.LastWriteTime;kind=$kind;dl=$isDl;hid=(($attr -band 6) -ne 0)})
                    }
                }catch{}
            }
        }
        if($partial){ break }
    }

    $now = Get-Date
    $mk = {
        param($f,$level,$detail)
        @{id=[string]$f.path;path=[string]$f.path;name=[string]$f.name;dir=[string]$f.dir;size=[long]$f.len;sizeStr=(Format-Size $f.len);date=$f.mod.ToString('dd/MM/yyyy');level=$level;kind=[string]$f.kind;detail=[string]$detail}
    }
    $levelFor = {
        param($f)
        if($f.kind -eq 'Installateurs' -or $f.kind -eq 'Archives'){ if($f.dl){ return 'safe' } else { return 'check' } }
        if($f.kind -match 'Images|Videos|Documents|Musique'){ return 'perso' }
        'check'
    }

    # 1) Gros fichiers (100 Mo et plus)
    $big = @($files | Where-Object { $_.len -ge 100MB } | Sort-Object len -Descending | Select-Object -First 60 | ForEach-Object { & $mk $_ (& $levelFor $_) '' })

    # 2) Doublons : meme taille, puis meme empreinte
    $dups = New-Object System.Collections.Generic.List[object]
    $hashBudget = [System.Diagnostics.Stopwatch]::StartNew()
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $quickHash = {
        param($path,$len)
        $fs = $null
        try{
            $fs = [IO.File]::Open($path,'Open','Read','ReadWrite')
            $bufLen = [int][Math]::Min(65536, $len)
            $b1 = New-Object byte[] $bufLen
            [void]$fs.Read($b1,0,$bufLen)
            $b2 = New-Object byte[] $bufLen
            if($len -gt $bufLen){ [void]$fs.Seek(-$bufLen,'End'); [void]$fs.Read($b2,0,$bufLen) }
            $all = New-Object byte[] ($bufLen*2 + 8)
            [Array]::Copy($b1,0,$all,0,$bufLen); [Array]::Copy($b2,0,$all,$bufLen,$bufLen)
            [Array]::Copy([BitConverter]::GetBytes([long]$len),0,$all,$bufLen*2,8)
            return [BitConverter]::ToString($sha.ComputeHash($all))
        }catch{ return $null } finally { if($fs){ $fs.Close() } }
    }
    $fullHash = {
        param($path)
        $fs = $null
        try{ $fs = [IO.File]::Open($path,'Open','Read','ReadWrite'); return [BitConverter]::ToString($sha.ComputeHash($fs)) }catch{ return $null } finally { if($fs){ $fs.Close() } }
    }
    $bySize = $files | Where-Object { $_.len -ge 1MB } | Group-Object len | Where-Object { $_.Count -ge 2 } | Sort-Object { [long]$_.Name } -Descending
    $gid = 0
    foreach($g in $bySize){
        if($hashBudget.Elapsed.TotalSeconds -gt 45){ $partial = $true; break }
        $byQuick = @{}
        foreach($f in $g.Group){
            $h = & $quickHash $f.path $f.len
            if($h){ if(-not $byQuick.ContainsKey($h)){ $byQuick[$h] = New-Object System.Collections.Generic.List[object] }; $byQuick[$h].Add($f) }
        }
        foreach($qh in $byQuick.Keys){
            $cand = $byQuick[$qh]
            if($cand.Count -lt 2){ continue }
            $exact = $true
            $groups = @{}
            if($cand[0].len -le 512MB){
                foreach($f in $cand){
                    $fh = & $fullHash $f.path
                    if($fh){ if(-not $groups.ContainsKey($fh)){ $groups[$fh] = New-Object System.Collections.Generic.List[object] }; $groups[$fh].Add($f) }
                }
            } else {
                $exact = $false
                $groups['q'] = $cand
            }
            foreach($k in $groups.Keys){
                $set = $groups[$k].ToArray()
                if($set.Count -lt 2){ continue }
                $gid++
                # On garde la copie hors Telechargements la plus recente.
                $ordered = @($set | Sort-Object @{Expression={ [int]$_.dl }}, @{Expression={ $_.mod }; Descending=$true})
                $keep = $ordered[0]
                for($i=1; $i -lt $ordered.Count; $i++){
                    $f = $ordered[$i]
                    $lvl = if(-not $exact){ 'check' } elseif($f.kind -match 'Images|Videos|Documents|Musique'){ 'perso' } else { 'safe' }
                    $it = & $mk $f $lvl ("Copie identique de : " + [string]$keep.path)
                    $it.group = $gid
                    $it.exact = $exact
                    $dups.Add($it)
                }
            }
        }
    }

    # 3) Telechargements oublies (plus de 60 jours)
    $dlOld = @($files | Where-Object { $_.dl -and ($now - $_.mod).TotalDays -gt 60 -and $_.len -ge 1MB } | Sort-Object len -Descending | Select-Object -First 150 | ForEach-Object {
        $lvl = if($_.kind -eq 'Installateurs' -or $_.kind -eq 'Archives'){ 'safe' } elseif($_.kind -match 'Images|Videos|Documents|Musique'){ 'perso' } else { 'check' }
        & $mk $_ $lvl ("Telecharge il y a " + [int](($now - $_.mod).TotalDays) + " jours")
    })

    # 4) Fichiers anciens (pas modifies depuis 2 ans, 50 Mo et plus)
    $old = @($files | Where-Object { -not $_.dl -and ($now - $_.mod).TotalDays -gt 730 -and $_.len -ge 50MB } | Sort-Object len -Descending | Select-Object -First 100 | ForEach-Object {
        $lvl = if($_.kind -match 'Images|Videos|Documents|Musique'){ 'perso' } else { 'check' }
        & $mk $_ $lvl ("Pas modifie depuis " + [int](($now - $_.mod).TotalDays / 365) + " ans")
    })

    # 4 bis) Fichiers vides (0 octet), hors fichiers caches/systeme et marqueurs techniques
    $emptyFiles = @($files | Where-Object { $_.len -eq 0 -and -not $_.hid -and $_.name -notmatch '^(desktop\.ini|thumbs\.db|\.gitkeep|\.keep|\.nomedia|\.placeholder)$' -and $_.name -notmatch '\.(lock|lck|pid|tmp|log)$' -and $_.name -notmatch '^~\$' } | Select-Object -First 500 | ForEach-Object {
        $lvl = if($_.kind -match 'Images|Videos|Documents|Musique|Archives|Installateurs'){ 'safe' } else { 'check' }
        & $mk $_ $lvl 'Fichier vide (0 octet)'
    })

    # 5) Dossiers vides
    $empty = @($dirs | Where-Object { -not $dirsWithFiles.Contains($_) } | Select-Object -First 500 | ForEach-Object {
        @{id=[string]$_;path=[string]$_;name=[IO.Path]::GetFileName($_);dir=[IO.Path]::GetDirectoryName($_);size=[long]0;sizeStr='';date='';level='safe';kind='Dossier';detail=''}
    })

    $sumOf = { param($arr) [long](@($arr | ForEach-Object { [long]$_.size }) | Measure-Object -Sum).Sum }
    $cats = @()
    foreach($k in @('Videos','Images','Telechargements','Musique','Documents','Archives','Installateurs','Autres')){
        $cats += @{name=$k;size=[long]$catSizes[$k];sizeStr=(Format-Size $catSizes[$k])}
    }
    $tot = [long]0; foreach($k in $catSizes.Keys){ $tot += $catSizes[$k] }
    $res = @{
        scanned = $scanned
        elapsed = [int]$sw.Elapsed.TotalSeconds
        partial = $partial
        total   = (Format-Size $tot)
        totalBytes = $tot
        cats    = @($cats)
        groups  = @{
            dups      = @{items=$dups.ToArray();      size=(& $sumOf $dups)}
            big       = @{items=@($big);       size=(& $sumOf $big)}
            downloads = @{items=@($dlOld);     size=(& $sumOf $dlOld)}
            empty     = @{items=@($empty);     size=[long]0}
            emptyfiles= @{items=@($emptyFiles); size=[long]0}
            old       = @{items=@($old);       size=(& $sumOf $old)}
        }
        date = (Get-Date -Format 'dd/MM/yyyy HH:mm')
    }
    try{ $sha.Dispose() }catch{}
    Set-OptiCache 'space' $res
    $res
}

function Test-OptiSpacePathAllowed($path){
    $p = [string]$path
    if(-not $p){ return $false }
    try{ $p = [IO.Path]::GetFullPath($p) }catch{ return $false }
    $up = [string]$env:USERPROFILE
    if(-not $up){ return $false }
    if($p -match '(?i)\\AppData\\|\\NTUSER|\\\$RECYCLE\.BIN|\\Windows\\|\\Program Files'){ return $false }
    $roots = @(Get-OptiUserRoots)
    foreach($r in $roots){ if($p -ieq [string]$r.path){ return $false } }
    if($p.StartsWith($up + '\', [StringComparison]::OrdinalIgnoreCase)){ return $true }
    # Dossier personnel deplace sur un autre disque (ex. Telechargements sur D:)
    foreach($r in $roots){ if($p.StartsWith(([string]$r.path).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)){ return $true } }
    $false
}

function Initialize-OptiRecycle {
    if('OptiRecycle' -as [type]){ return $true }
    try{
        Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class OptiRecycle {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct SHFILEOPSTRUCT { public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo; public ushort fFlags; public bool fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle; }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHFileOperation(ref SHFILEOPSTRUCT op);
  public static int ToBin(string path){
    var op = new SHFILEOPSTRUCT();
    op.wFunc = 3; // FO_DELETE
    op.pFrom = path + "\0\0";
    // ALLOWUNDO | NOCONFIRMATION | NOERRORUI | SILENT | WANTNUKEWARNING
    op.fFlags = (ushort)(0x40 | 0x10 | 0x400 | 0x4 | 0x4000);
    return SHFileOperation(ref op);
  }
}
"@ -EA Stop
        return $true
    }catch{ return $false }
}

function Remove-OptiSpaceItems($paths){
    $list = @($paths | Where-Object { $_ })
    if(-not $list.Count){ return @{ok=$false;msg='Aucun element selectionne'} }
    $isPro = $false; try{ $isPro = [bool](Test-IsPro) }catch{}
    $limit = [long]500MB
    if(-not (Initialize-OptiRecycle)){ return @{ok=$false;msg="La Corbeille de Windows n'est pas accessible."} }
    $done = 0; $freed = [long]0; $skipped = 0; $failed = 0; $limited = 0
    $log = New-Object System.Collections.Generic.List[string]
    foreach($p in $list){
        $p = [string]$p
        if(-not (Test-OptiSpacePathAllowed $p)){ $skipped++; continue }
        if(-not (Test-Path -LiteralPath $p)){ $skipped++; continue }
        $isDir = (Test-Path -LiteralPath $p -PathType Container)
        $sz = [long]0
        if(-not $isDir){ try{ $sz = [long](Get-Item -LiteralPath $p -Force).Length }catch{} }
        else {
            # Un dossier n'est accepte que s'il est vraiment vide (aucun fichier dedans).
            $hasFile = $false
            try{ $hasFile = [bool]([IO.Directory]::EnumerateFiles($p,'*','AllDirectories') | Select-Object -First 1) }catch{ $hasFile = $true }
            if($hasFile){ $skipped++; continue }
        }
        if(-not $isPro -and ($freed + $sz) -gt $limit){ $limited++; continue }
        $r = [OptiRecycle]::ToBin($p)
        if($r -eq 0 -and -not (Test-Path -LiteralPath $p)){ $done++; $freed += $sz; $log.Add("OK - $p") }
        else { $failed++; $log.Add("ECHEC - $p") }
    }
    try{ Remove-Item (Get-OptiCacheFile 'space') -Force -EA SilentlyContinue }catch{}
    $msg = "$done element(s) envoye(s) dans la Corbeille ($(Format-Size $freed))"
    if($limited -gt 0){ $msg += " - $limited element(s) non traites : la version gratuite est limitee a 500 Mo par nettoyage" }
    @{ok=($done -gt 0);done=$done;freed=$freed;freedStr=(Format-Size $freed);skipped=$skipped;failed=$failed;limited=$limited;isPro=$isPro;msg=$msg;log=@($log)}
}

function Move-OptiSpaceItems($paths, $dest){
    $d = [string]$dest
    if(-not $d -or -not (Test-Path -LiteralPath $d -PathType Container)){ return @{ok=$false;msg='Dossier de destination introuvable'} }
    $done = 0; $moved = [long]0; $failed = 0
    $target = Join-Path $d ('OptiPC - fichiers deplaces ' + (Get-Date -Format 'yyyy-MM-dd'))
    try{ [IO.Directory]::CreateDirectory($target) | Out-Null }catch{ return @{ok=$false;msg="Impossible d'ecrire dans ce dossier"} }
    foreach($p in @($paths)){
        $p = [string]$p
        if(-not (Test-OptiSpacePathAllowed $p) -or -not (Test-Path -LiteralPath $p -PathType Leaf)){ $failed++; continue }
        try{
            $sz = [long](Get-Item -LiteralPath $p -Force).Length
            $name = [IO.Path]::GetFileName($p)
            $dst = Join-Path $target $name
            $i = 1
            while(Test-Path -LiteralPath $dst){ $dst = Join-Path $target ([IO.Path]::GetFileNameWithoutExtension($name) + " ($i)" + [IO.Path]::GetExtension($name)); $i++ }
            Move-Item -LiteralPath $p -Destination $dst -Force -EA Stop
            $done++; $moved += $sz
        }catch{ $failed++ }
    }
    try{ Remove-Item (Get-OptiCacheFile 'space') -Force -EA SilentlyContinue }catch{}
    @{ok=($done -gt 0);done=$done;failed=$failed;moved=(Format-Size $moved);dest=$target;msg="$done fichier(s) deplace(s) vers $target ($(Format-Size $moved))"}
}

# ─── SANTE DU PC (disques, batterie, demarrage) ────────────────────────────────

function Get-OptiDiskHealth {
    $out = New-Object System.Collections.Generic.List[object]
    $predict = @()
    try{ $predict = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -OperationTimeoutSec 8 -EA Stop | Where-Object { $_.PredictFailure }) }catch{}
    $pds = @()
    try{ $pds = @(Get-PhysicalDisk -EA Stop) }catch{}
    foreach($d in $pds){
        try{
            $rel = $null
            try{ $rel = $d | Get-StorageReliabilityCounter -EA Stop }catch{}
            $num = [string]$d.DeviceId
            $letters = @()
            try{ $letters = @(Get-Partition -DiskNumber ([int]$num) -EA Stop | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter + ':' }) }catch{}
            $media = [string]$d.MediaType
            $bus = [string]$d.BusType
            $type = if($bus -eq 'NVMe'){ 'SSD NVMe' } elseif($media -eq 'SSD'){ 'SSD' } elseif($media -eq 'HDD'){ 'Disque dur' } elseif($bus -eq 'USB'){ 'Disque USB' } else { 'Disque' }
            $temp = $null; $wear = $null; $hours = $null; $starts = $null; $rdErr = $null; $rdUnc = $null; $wrErr = $null; $tempMax = $null
            if($rel){
                if($rel.Temperature -gt 0){ $temp = [int]$rel.Temperature }
                if($rel.TemperatureMax -gt 0){ $tempMax = [int]$rel.TemperatureMax }
                if($null -ne $rel.Wear){ $wear = [int]$rel.Wear }
                if($rel.PowerOnHours -gt 0){ $hours = [long]$rel.PowerOnHours }
                if($rel.StartStopCycleCount -gt 0){ $starts = [long]$rel.StartStopCycleCount }
                if($null -ne $rel.ReadErrorsTotal){ $rdErr = [long]$rel.ReadErrorsTotal }
                if($null -ne $rel.ReadErrorsUncorrected){ $rdUnc = [long]$rel.ReadErrorsUncorrected }
                if($null -ne $rel.WriteErrorsTotal){ $wrErr = [long]$rel.WriteErrorsTotal }
            }
            $hs = [string]$d.HealthStatus
            $ops = (@($d.OperationalStatus) | ForEach-Object { [string]$_ }) -join ', '
            $reasons = New-Object System.Collections.Generic.List[string]
            $level = 'ok'
            if($hs -eq 'Unhealthy'){ $level = 'crit'; $reasons.Add('Windows signale ce disque comme defaillant') }
            if($predict.Count -gt 0 -and $pds.Count -eq 1){ $level = 'crit'; $reasons.Add('Le disque annonce lui-meme une panne prochaine (SMART)') }
            if($rdUnc -gt 0){ $level = 'crit'; $reasons.Add("$rdUnc erreur(s) de lecture non corrigee(s)") }
            if($level -ne 'crit'){
                if($hs -eq 'Warning'){ $level = 'warn'; $reasons.Add('Windows signale un probleme sur ce disque') }
                if($wear -ne $null -and $wear -ge 70){ $level = 'warn'; $reasons.Add("Usure elevee ($wear %)") }
                if($temp -ne $null -and $temp -ge 60){ $level = 'warn'; $reasons.Add("Temperature elevee ($temp °C)") }
                if($ops -and $ops -notmatch '^OK'){ $level = 'warn'; $reasons.Add("Etat : $ops") }
            }
            $pct = if($wear -ne $null){ [Math]::Max(0, 100 - $wear) } elseif($level -eq 'crit'){ 15 } elseif($level -eq 'warn'){ 60 } else { 100 }
            $label = if($level -eq 'crit'){ 'Critique' } elseif($level -eq 'warn'){ 'Attention' } else { 'Bonne' }
            $rows = New-Object System.Collections.Generic.List[object]
            $rows.Add(@{k='Type';v=$type})
            $rows.Add(@{k='Interface';v=$bus})
            $rows.Add(@{k='Capacite';v=(Format-Size ([long]$d.Size))})
            if($d.FirmwareVersion){ $rows.Add(@{k='Firmware';v=[string]$d.FirmwareVersion}) }
            if($temp -ne $null){ $rows.Add(@{k='Temperature';v="$temp °C"}) }
            if($tempMax -ne $null){ $rows.Add(@{k='Temperature maximale constatee';v="$tempMax °C"}) }
            if($hours -ne $null){ $rows.Add(@{k="Heures d'utilisation";v=("{0:N0} h" -f $hours) + " (" + [Math]::Round($hours/24/365,1) + " ans)"}) }
            if($starts -ne $null){ $rows.Add(@{k='Demarrages';v=("{0:N0}" -f $starts)}) }
            if($wear -ne $null){ $rows.Add(@{k='Usure (SSD)';v="$wear %"}) }
            if($rdErr -ne $null){ $rows.Add(@{k='Erreurs de lecture';v=[string]$rdErr}) }
            if($rdUnc -ne $null){ $rows.Add(@{k='Erreurs de lecture non corrigees';v=[string]$rdUnc}) }
            if($wrErr -ne $null){ $rows.Add(@{k="Erreurs d'ecriture";v=[string]$wrErr}) }
            $rows.Add(@{k='Etat Windows';v=$hs})
            $out.Add(@{
                name=[string]$d.FriendlyName; number=$num; type=$type; size=(Format-Size ([long]$d.Size)); letters=@($letters)
                level=$level; label=$label; pct=[int]$pct; temp=$temp; hours=$hours; wear=$wear; reasons=$reasons.ToArray(); rows=$rows.ToArray()
            })
        }catch{}
    }
    $worst = 'ok'
    foreach($o in $out){ if($o.level -eq 'crit'){ $worst = 'crit' } elseif($o.level -eq 'warn' -and $worst -ne 'crit'){ $worst = 'warn' } }
    @{disks=$out.ToArray();worst=$worst;available=($out.Count -gt 0);predictAny=($predict.Count -gt 0)}
}

function Get-OptiBattery {
    $r = @{present=$false}
    try{
        $b = @(Get-CimInstance Win32_Battery -OperationTimeoutSec 5 -EA Stop) | Select-Object -First 1
        if(-not $b){ return $r }
        $r.present = $true
        $r.charge = [int]$b.EstimatedChargeRemaining
        $r.plugged = ([int]$b.BatteryStatus -in 2,6,7,8,9)
        $design = $null; $full = $null; $cycles = $null
        try{ $design = [long](@(Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -EA Stop)[0].DesignedCapacity) }catch{}
        try{ $full = [long](@(Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -EA Stop)[0].FullChargedCapacity) }catch{}
        try{ $cycles = [long](@(Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -EA Stop)[0].CycleCount) }catch{}
        if($design -gt 0 -and $full -gt 0){
            $h = [int][Math]::Min(100, [Math]::Round($full * 100.0 / $design))
            $r.health = $h
            $r.level = if($h -lt 50){ 'crit' } elseif($h -lt 75){ 'warn' } else { 'ok' }
            $r.design = "{0:N0} mWh" -f $design
            $r.full = "{0:N0} mWh" -f $full
        }
        if($cycles -gt 0){ $r.cycles = $cycles }
    }catch{}
    $r
}

function Get-OptiBootTime {
    $f = Join-Path (Get-OptiDataDir) 'boot.json'
    $st = Read-OptiJsonFile $f
    $hist = New-Object System.Collections.Generic.List[object]
    $first = $null
    if($st){ $first = $st.first; foreach($h in @($st.list)){ if($h){ $hist.Add(@{d=[string]$h.d;ms=[long]$h.ms}) } } }
    $last = $null
    try{
        $evs = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Diagnostics-Performance/Operational';Id=100} -MaxEvents 10 -EA Stop)
        foreach($e in ($evs | Sort-Object TimeCreated)){
            $x = [xml]$e.ToXml()
            $bt = $x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' } | Select-Object -First 1
            if($bt -and [long]$bt.'#text' -gt 0){
                $ms = [long]$bt.'#text'
                $d = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm')
                if(-not ($hist | Where-Object { $_.d -eq $d })){ $hist.Add(@{d=$d;ms=$ms}) }
                $last = $ms
            }
        }
    }catch{}
    $list = @($hist | Sort-Object { $_.d } | Select-Object -Last 20)
    if(-not $first -and $list.Count -gt 0){ $first = [long]$list[0].ms }
    Write-OptiJsonFile $f @{first=$first;list=$list} | Out-Null
    if(-not $last -and $list.Count -gt 0){ $last = [long]$list[-1].ms }
    $lastBoot = $null
    try{ $lastBoot = (Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).LastBootUpTime.ToString('dd/MM/yyyy HH:mm') }catch{}
    @{available=($last -ne $null);lastSec=$(if($last){[Math]::Round($last/1000)}else{$null});firstSec=$(if($first){[Math]::Round($first/1000)}else{$null});lastBoot=$lastBoot;history=$list}
}

function Get-OptiHealthAll {
    $c = Get-OptiCache 'health' 120
    if($c){ return $c }
    $r = @{disks=(Get-OptiDiskHealth);battery=(Get-OptiBattery);boot=(Get-OptiBootTime)}
    Set-OptiCache 'health' $r
    $r
}

# ─── PERFORMANCES EN DIRECT : disque et carte graphique ────────────────────────

function Get-OptiGpuInfo {
    $c = Get-OptiCache 'gpuinfo' 3600
    if($c){ return $c }
    $r = @{present=$false;name='';vendor=''}
    try{
        $vcs = @(Get-CimInstance Win32_VideoController -OperationTimeoutSec 6 -EA Stop | Where-Object { $_.Name -notmatch '(?i)Basic Display|Remote|Virtual|Mirage|Parsec|DisplayLink|Citrix' })
        foreach($v in $vcs){
            $n = [string]$v.Name; $comp = [string]$v.AdapterCompatibility
            $ded = $false
            if($n -match '(?i)NVIDIA|GeForce|Quadro|RTX|GTX'){ $ded = $true }
            elseif($n -match '(?i)Radeon\s*(RX|Pro|R9|R7|HD\s*[5-9])' -and $n -notmatch '(?i)Vega \d+ Graphics|Radeon\(TM\) Graphics'){ $ded = $true }
            elseif($n -match '(?i)Intel.*Arc\s*A\d'){ $ded = $true }
            if($ded){ $r = @{present=$true;name=$n;vendor=$(if($n -match '(?i)NVIDIA|GeForce|Quadro|RTX|GTX'){'nvidia'}else{'other'})}; break }
        }
        if(-not $r.present -and $vcs.Count -gt 0){ $r.name = [string]$vcs[0].Name }
    }catch{}
    Set-OptiCache 'gpuinfo' $r
    $r
}

function Get-OptiPerf2 {
    $disk = $null
    try{
        $pd = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -OperationTimeoutSec 4 -EA Stop
        if($pd){ $disk = [int][Math]::Max(0, [Math]::Min(100, 100 - [int]$pd.PercentIdleTime)) }
    }catch{}
    $g = Get-OptiGpuInfo
    $gpu = @{present=[bool]$g.present;name=[string]$g.name}
    if($g.present){
        $util = $null; $temp = $null
        $smi = "$env:SystemRoot\System32\nvidia-smi.exe"
        if(-not (Test-Path $smi)){ $smi = "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe" }
        if($g.vendor -eq 'nvidia' -and (Test-Path $smi)){
            $cc = Get-OptiCache 'gpusmi' 8
            if($cc){ $util = $cc.u; $temp = $cc.t }
            else {
                try{
                    $o = & $smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
                    if($o -match '^\s*(\d+)\s*,\s*(\d+)'){ $util = [int]$matches[1]; $temp = [int]$matches[2]; Set-OptiCache 'gpusmi' @{u=$util;t=$temp} }
                }catch{}
            }
        }
        if($util -eq $null){
            try{
                $eng = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -OperationTimeoutSec 4 -EA Stop | Where-Object { $_.Name -match 'engtype_3D' })
                $s = [int](($eng | Measure-Object -Property UtilizationPercentage -Sum).Sum)
                $util = [Math]::Min(100, $s)
            }catch{}
        }
        $gpu.pct = $util
        $gpu.temp = $temp
    }
    $procs = 0
    try{ $procs = @([System.Diagnostics.Process]::GetProcesses()).Count }catch{}
    @{disk=$disk;gpu=$gpu;procs=$procs}
}

# ─── RESEAU ────────────────────────────────────────────────────────────────────

function Get-OptiOuiVendor($mac){
    $m = ([string]$mac).ToUpper() -replace '[^0-9A-F]',''
    if($m.Length -lt 6){ return '' }
    # Adresse "privee" (aleatoire) : bit administre localement
    $second = [Convert]::ToInt32($m.Substring(1,1),16)
    if(($second -band 2) -ne 0){ return 'prive' }
    $oui = $m.Substring(0,6)
    $t = @{
        'F0D1A9'='Apple';'3C0754'='Apple';'A4D1D2'='Apple';'F0B479'='Apple';'7C6DF8'='Apple';'DC2B2A'='Apple';'40B395'='Apple';'B8E856'='Apple';'ACBC32'='Apple';'F4F15A'='Apple';'88665A'='Apple';'C82A14'='Apple';'D0817A'='Apple';'BC9FEF'='Apple';'F8FFC2'='Apple'
        '5C0A5B'='Samsung';'8C7712'='Samsung';'F025B7'='Samsung';'B47443'='Samsung';'BC765E'='Samsung';'C0BDD1'='Samsung';'E4E0C5'='Samsung';'78BDBC'='Samsung';'000DAE'='Samsung';'8425DB'='Samsung';'A0B4A5'='Samsung'
        '001E10'='Huawei';'00E0FC'='Huawei';'2C9D1E'='Huawei';'48DB50'='Huawei';'E8CD2D'='Huawei';'58605F'='Huawei'
        '64CC2E'='Xiaomi';'7811DC'='Xiaomi';'34CE00'='Xiaomi';'F48B32'='Xiaomi';'9C99A0'='Xiaomi';'50EC50'='Xiaomi'
        '50C7BF'='TP-Link';'F4F26D'='TP-Link';'C006C3'='TP-Link';'98DAC4'='TP-Link';'B0BE76'='TP-Link';'1C3BF3'='TP-Link'
        '00072B'='Free (Freebox)';'F4CAE5'='Free (Freebox)';'0024D4'='Free (Freebox)';'14C913'='Free (Freebox)';'68A378'='Free (Freebox)'
        '3C81D8'='Sagemcom (Livebox / box)';'7C034C'='Sagemcom (Livebox / box)';'E8F1B0'='Sagemcom (Livebox / box)';'A0391F'='Sagemcom (Livebox / box)';'2C3996'='Sagemcom (Livebox / box)';'34E380'='Sagemcom (Livebox / box)'
        '00264D'='Arcadyan (box)';'849CA6'='Arcadyan (box)';'A8D3F7'='Arcadyan (box)';'88D274'='Technicolor (box)';'5C35FC'='Technicolor (box)';'C4EA1D'='Technicolor (box)'
        'F4F5D8'='Google';'3C5AB4'='Google';'D86C63'='Google';'F88FCA'='Google';'54609A'='Google'
        'FC65DE'='Amazon';'747548'='Amazon';'4CEFC0'='Amazon';'0C47C9'='Amazon';'F0272D'='Amazon'
        '000E58'='Sonos';'5CAAFD'='Sonos';'48A6B8'='Sonos'
        '3C2AF4'='Brother';'0080770'='Brother';'001BA9'='Brother'
        '64EB8C'='Epson';'38C986'='Epson';'0026AB'='Epson';'A4EE57'='Epson'
        '00BB3A'='Canon';'F48139'='Canon';'002507'='Canon';'848506'='Canon'
        '3024A9'='HP';'9CB654'='HP';'A0D3C1'='HP';'FC3FDB'='HP';'10604B'='HP';'B05ADA'='HP';'009C02'='HP'
        'B827EB'='Raspberry Pi';'DCA632'='Raspberry Pi';'E45F01'='Raspberry Pi'
        'A85E45'='LG';'C808E9'='LG';'64CBE9'='LG';'00E091'='LG'
        'FCF152'='Sony';'0024BE'='Sony';'78843C'='Sony'
        '001788'='Philips Hue';'ECB5FA'='Philips Hue'
        '3497F6'='ASUS';'049226'='ASUS';'AC220B'='ASUS';'2C56DC'='ASUS'
        '8086F2'='Intel';'A4C3F0'='Intel';'3C9C0F'='Intel';'7C7A91'='Intel';'F8E43B'='Intel';'D4D252'='Intel'
        '00E04C'='Realtek';'525400'='Machine virtuelle';'000C29'='Machine virtuelle (VMware)';'080027'='Machine virtuelle (VirtualBox)'
        '0050F2'='Microsoft';'7C1E52'='Microsoft';'C83DD4'='Microsoft'
        '001A11'='Google';'B0E4D5'='Google (Nest)';'18B430'='Google (Nest)'
        '38F73D'='Amazon (Echo)';'44650D'='Amazon (Echo)'
        'E0B9E5'='Technicolor (box)';'A4B1E9'='Technicolor (box)'
    }
    if($t.ContainsKey($oui)){ return $t[$oui] }
    ''
}

function Get-OptiDeviceGuess($vendor,$name,$isGw,$isSelf){
    if($isSelf){ return @{type='pc';label='Ce PC'} }
    if($isGw){ return @{type='box';label='Box internet'} }
    $all = "$vendor $name"
    if($all -match '(?i)iphone'){ return @{type='phone';label='iPhone'} }
    if($all -match '(?i)ipad'){ return @{type='phone';label='Tablette iPad'} }
    if($all -match '(?i)android|galaxy|redmi|pixel|huawei|xiaomi|oppo|oneplus|honor|motorola|SM-[A-Z]'){ return @{type='phone';label='Téléphone ou tablette'} }
    if($all -match '(?i)apple ?tv|homepod'){ return @{type='tv';label='Apple TV ou HomePod'} }
    if($all -match '(?i)macbook|imac|\bmac\b'){ return @{type='pc';label='Ordinateur Mac'} }
    if($all -match '(?i)Apple'){ return @{type='apple';label='Appareil Apple'} }
    if($all -match '(?i)Brother|Epson|Canon|HP|print|imprim'){ return @{type='printer';label='Imprimante ou appareil HP/Canon/Epson'} }
    if($all -match '(?i)LG|Sony|Philips|TV|tv|chromecast|Google|Amazon|Roku|Fire'){ return @{type='tv';label='TV, enceinte ou boîtier multimédia'} }
    if($all -match '(?i)Sonos|Echo|Nest|Hue'){ return @{type='iot';label='Objet connecté'} }
    if($all -match '(?i)Freebox|Livebox|Sagemcom|Arcadyan|Technicolor|TP-Link'){ return @{type='box';label='Équipement réseau (box, répéteur)'} }
    if($all -match '(?i)Samsung'){ return @{type='phone';label='Appareil Samsung (téléphone, TV…)'} }
    if($all -match '(?i)Intel|Realtek|ASUS|desktop|laptop|PC'){ return @{type='pc';label='Ordinateur'} }
    if($vendor -eq 'prive'){ return @{type='phone';label='Téléphone ou tablette (adresse privée)'} }
    @{type='unknown';label='Appareil inconnu'}
}

function Get-OptiWifiInfo {
    $r = @{connected=$false}
    try{
        $lines = @(& netsh.exe wlan show interfaces 2>$null)
        foreach($l in $lines){
            if($l -match '^\s*SSID\s*:\s*(.+)$' -and -not $r.ssid){ $r.ssid = $matches[1].Trim(); $r.connected = $true }
            elseif($l -match '^\s*(Authentification|Authentication)\s*:\s*(.+)$'){ $r.auth = $matches[2].Trim() }
            elseif($l -match '^\s*(Chiffrement|Cipher)\s*:\s*(.+)$'){ $r.cipher = $matches[2].Trim() }
            elseif($l -match '^\s*Signal\s*:\s*(\d+)'){ $r.signal = [int]$matches[1] }
        }
    }catch{}
    if($r.connected){
        $a = [string]$r.auth
        if($a -match '(?i)WPA3'){ $r.level='ok'; $r.verdict='Tres bonne protection (WPA3)' }
        elseif($a -match '(?i)WPA2'){ $r.level='ok'; $r.verdict='Bonne protection (WPA2)' }
        elseif($a -match '(?i)WPA'){ $r.level='warn'; $r.verdict='Protection ancienne (WPA) : passez en WPA2 ou WPA3 dans les reglages de la box' }
        elseif($a -match '(?i)WEP'){ $r.level='crit'; $r.verdict='Protection obsolete (WEP) : vos voisins peuvent se connecter' }
        elseif($a -match '(?i)Open|Ouvert'){ $r.level='crit'; $r.verdict='Reseau ouvert, sans mot de passe : evitez les achats et la banque en ligne' }
        else { $r.level='ok'; $r.verdict='Protection : ' + $a }
    }
    $r
}

# ── Identification des appareils du reseau (nom annonce par l'appareil) ──────
# Les telephones recents utilisent une adresse materielle « privee » (aleatoire) :
# le fabricant ne peut plus etre deduit de l'adresse. On interroge donc les
# appareils eux-memes : mDNS/Bonjour (iPhone, Mac, Android, TV, imprimantes),
# NetBIOS (PC Windows, NAS) et UPnP/SSDP (box, TV, enceintes). ~3 secondes.
function New-OptiDnsQuery([string]$name, [int]$qtype, [bool]$qu){
    $ms = New-Object IO.MemoryStream
    $id = Get-Random -Minimum 1 -Maximum 65000
    $hdr = [byte[]]@([byte](($id -shr 8) -band 0xFF), [byte]($id -band 0xFF), 0,0, 0,1, 0,0, 0,0, 0,0)
    $ms.Write($hdr, 0, 12)
    foreach($lab in $name.TrimEnd('.').Split('.')){
        $b = [Text.Encoding]::UTF8.GetBytes($lab)
        $ms.WriteByte([byte]$b.Length); $ms.Write($b, 0, $b.Length)
    }
    $ms.WriteByte(0)
    $ms.WriteByte([byte](($qtype -shr 8) -band 0xFF)); $ms.WriteByte([byte]($qtype -band 0xFF))
    $cls = if($qu){ 0x8001 } else { 1 }
    $ms.WriteByte([byte](($cls -shr 8) -band 0xFF)); $ms.WriteByte([byte]($cls -band 0xFF))
    ,$ms.ToArray()
}
function Read-OptiDnsName([byte[]]$b, [ref]$pos){
    $labels = New-Object System.Collections.Generic.List[string]
    $p = [int]$pos.Value; $jumped = $false; $guard = 0
    while($p -lt $b.Length -and $guard -lt 80){
        $guard++
        $len = [int]$b[$p]
        if($len -eq 0){ $p++; break }
        if(($len -band 0xC0) -eq 0xC0){
            if($p + 1 -ge $b.Length){ break }
            $ptr = (($len -band 0x3F) -shl 8) -bor [int]$b[$p + 1]
            if(-not $jumped){ $pos.Value = $p + 2 }
            $jumped = $true; $p = $ptr; continue
        }
        if($p + 1 + $len -gt $b.Length){ break }
        $labels.Add([Text.Encoding]::UTF8.GetString($b, $p + 1, $len)); $p += 1 + $len
    }
    if(-not $jumped){ $pos.Value = $p }
    ($labels.ToArray() -join '.')
}
function Read-OptiDnsPacket([byte[]]$b){
    $out = New-Object System.Collections.Generic.List[object]
    if($b.Length -lt 12){ return ,$out.ToArray() }
    $qd = ([int]$b[4] -shl 8) -bor $b[5]; $an = ([int]$b[6] -shl 8) -bor $b[7]
    $ns = ([int]$b[8] -shl 8) -bor $b[9]; $ar = ([int]$b[10] -shl 8) -bor $b[11]
    $pos = 12
    for($i = 0; $i -lt $qd; $i++){ $r = [ref]$pos; [void](Read-OptiDnsName $b $r); $pos = [int]$r.Value + 4 }
    $total = $an + $ns + $ar
    for($i = 0; $i -lt $total -and $pos -lt $b.Length; $i++){
        $r = [ref]$pos; $nm = Read-OptiDnsName $b $r; $pos = [int]$r.Value
        if($pos + 10 -gt $b.Length){ break }
        $type = ([int]$b[$pos] -shl 8) -bor $b[$pos + 1]
        $rdlen = ([int]$b[$pos + 8] -shl 8) -bor $b[$pos + 9]
        $rd = $pos + 10
        if($rd + $rdlen -gt $b.Length){ break }
        $data = $null
        if($type -eq 12 -or $type -eq 5){ $tmp = $rd; $r2 = [ref]$tmp; $data = Read-OptiDnsName $b $r2 }
        elseif($type -eq 16){
            $txt = New-Object System.Collections.Generic.List[string]; $q = $rd
            while($q -lt $rd + $rdlen){ $l = [int]$b[$q]; if($l -gt 0 -and $q + 1 + $l -le $rd + $rdlen){ $txt.Add([Text.Encoding]::UTF8.GetString($b, $q + 1, $l)) }; $q += 1 + $l }
            $data = $txt.ToArray()
        }
        elseif($type -eq 1 -and $rdlen -eq 4){ $data = "{0}.{1}.{2}.{3}" -f $b[$rd], $b[$rd + 1], $b[$rd + 2], $b[$rd + 3] }
        $out.Add(@{name = $nm; type = $type; data = $data})
        $pos = $rd + $rdlen
    }
    ,$out.ToArray()
}
function Get-OptiNetNames($ips){
    $info = @{}
    foreach($ip in @($ips)){ $info[[string]$ip] = @{mdns = ''; model = ''; nb = ''; fn = ''; maker = ''} }
    $ep = New-Object System.Net.IPEndPoint([Net.IPAddress]::Any, 0)
    $svcRx = '^(.+?)\._(googlecast|airplay|raop|ipp|ipps|printer|pdl-datastream|spotify-connect|companion-link|device-info|hap|homekit|smb|afpovertcp|rdlink)\._(tcp|udp)'
    # 1) mDNS / Bonjour
    $u = $null
    try{
        $u = New-Object System.Net.Sockets.UdpClient(0)
        $u.Client.ReceiveTimeout = 250
        foreach($ip in $info.Keys){
            $o = $ip.Split('.'); $rev = "$($o[3]).$($o[2]).$($o[1]).$($o[0]).in-addr.arpa"
            foreach($qq in @((New-OptiDnsQuery $rev 12 $false), (New-OptiDnsQuery '_device-info._tcp.local' 12 $false))){
                try{ [void]$u.Send($qq, $qq.Length, $ip, 5353) }catch{}
            }
        }
        foreach($svc in @('_device-info._tcp.local','_googlecast._tcp.local','_airplay._tcp.local','_raop._tcp.local','_ipp._tcp.local','_printer._tcp.local','_spotify-connect._tcp.local','_companion-link._tcp.local','_hap._tcp.local')){
            $qq = New-OptiDnsQuery $svc 12 $true
            try{ [void]$u.Send($qq, $qq.Length, '224.0.0.251', 5353) }catch{}
        }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while($sw.ElapsedMilliseconds -lt 2500){
            $data = $null
            try{ $data = $u.Receive([ref]$ep) }catch{ continue }
            $src = [string]$ep.Address
            if(-not $info.ContainsKey($src)){ continue }
            $it = $info[$src]
            foreach($rr in (Read-OptiDnsPacket $data)){
                $nm = [string]$rr.name
                if($rr.type -eq 12 -and $nm -like '*.in-addr.arpa' -and $rr.data){ $it.mdns = [string]$rr.data }
                elseif($rr.type -eq 1 -and $nm -like '*.local' -and -not $it.mdns){ $it.mdns = $nm }
                elseif($rr.type -eq 16){
                    foreach($kv in @($rr.data)){
                        $kv = [string]$kv
                        if($kv -match '^(model|md|am)=(.+)$' -and -not $it.model){ $it.model = $matches[2] }
                        elseif($kv -match '^fn=(.+)$'){ $it.fn = $matches[1] }
                        elseif($kv -match '^ty=(.+)$' -and -not $it.model){ $it.model = $matches[1] }
                        elseif($kv -match '^usb_MFG=(.+)$' -and -not $it.maker){ $it.maker = $matches[1] }
                    }
                }
                $svcName = ''
                if($nm -match $svcRx){ $svcName = $matches[1] } elseif($rr.type -eq 12 -and [string]$rr.data -match $svcRx){ $svcName = $matches[1] }
                if($svcName -and -not $it.fn){
                    if($svcName -match '^[0-9A-Fa-f]{12}@(.+)$'){ $svcName = $matches[1] }
                    if($svcName -notmatch '^[0-9a-fA-F-]{16,}$'){ $it.fn = $svcName }
                }
            }
        }
    }catch{} finally { if($u){ try{ $u.Close() }catch{} } }
    # 2) NetBIOS (PC Windows, NAS, certaines imprimantes)
    $nb = $null
    try{
        $nb = New-Object System.Net.Sockets.UdpClient(0)
        $nb.Client.ReceiveTimeout = 250
        $pkt = [byte[]](@(0x13,0x37,0,0,0,1,0,0,0,0,0,0,0x20) + [byte[]][Text.Encoding]::ASCII.GetBytes('CK' + ('A' * 30)) + @(0,0,0x21,0,1))
        foreach($ip in $info.Keys){ try{ [void]$nb.Send($pkt, $pkt.Length, $ip, 137) }catch{} }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while($sw.ElapsedMilliseconds -lt 1200){
            $d = $null
            try{ $d = $nb.Receive([ref]$ep) }catch{ continue }
            $src = [string]$ep.Address
            if(-not $info.ContainsKey($src) -or $d.Length -lt 58){ continue }
            $cnt = [int]$d[56]
            for($i = 0; $i -lt $cnt; $i++){
                $o = 57 + $i * 18
                if($o + 18 -gt $d.Length){ break }
                $nmn = [Text.Encoding]::ASCII.GetString($d, $o, 15).Trim()
                $grp = ($d[$o + 16] -band 0x80) -ne 0
                if($d[$o + 15] -eq 0 -and -not $grp -and $nmn){ $info[$src].nb = $nmn; break }
            }
        }
    }catch{} finally { if($nb){ try{ $nb.Close() }catch{} } }
    # 3) UPnP / SSDP (box, TV, enceintes, imprimantes)
    $ss = $null; $locs = @{}
    try{
        $ss = New-Object System.Net.Sockets.UdpClient(0)
        $ss.Client.ReceiveTimeout = 250
        $msg = [Text.Encoding]::ASCII.GetBytes("M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 1`r`nST: ssdp:all`r`n`r`n")
        [void]$ss.Send($msg, $msg.Length, '239.255.255.250', 1900)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while($sw.ElapsedMilliseconds -lt 1800){
            $d = $null
            try{ $d = $ss.Receive([ref]$ep) }catch{ continue }
            $src = [string]$ep.Address
            if(-not $info.ContainsKey($src) -or $locs.ContainsKey($src)){ continue }
            $t = [Text.Encoding]::ASCII.GetString($d)
            if($t -match '(?im)^LOCATION:\s*(http://\S+)'){ $locs[$src] = $matches[1] }
        }
    }catch{} finally { if($ss){ try{ $ss.Close() }catch{} } }
    if($locs.Count -gt 0){
        $hc = $null
        try{
            Add-Type -AssemblyName System.Net.Http -EA SilentlyContinue
            $hc = New-Object System.Net.Http.HttpClient
            $hc.Timeout = [TimeSpan]::FromSeconds(2)
            $tasks = @{}
            foreach($k in $locs.Keys){ try{ $tasks[$k] = $hc.GetStringAsync([string]$locs[$k]) }catch{} }
            try{ [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tasks.Values), 2300) }catch{}
            foreach($k in $tasks.Keys){
                try{
                    $tk = $tasks[$k]
                    if($tk.Status -ne 'RanToCompletion'){ continue }
                    $x = [string]$tk.Result
                    $it = $info[$k]
                    if($x -match '<friendlyName>([^<]+)</friendlyName>' -and -not $it.fn){ $it.fn = [Net.WebUtility]::HtmlDecode($matches[1]).Trim() }
                    if($x -match '<manufacturer>([^<]+)</manufacturer>' -and -not $it.maker){ $it.maker = [Net.WebUtility]::HtmlDecode($matches[1]).Trim() }
                    if($x -match '<modelName>([^<]+)</modelName>' -and -not $it.model){ $it.model = [Net.WebUtility]::HtmlDecode($matches[1]).Trim() }
                }catch{}
            }
        }catch{} finally { if($hc){ try{ $hc.Dispose() }catch{} } }
    }
    $info
}
function Format-OptiDevName([string]$n){
    if(-not $n){ return '' }
    $n = $n -replace '\.(local|home|lan|box|localdomain)\.?$', '' -replace '\.$', ''
    if($n -match '^[\d.]+$'){ return '' }
    if($n -match '^[0-9a-fA-F-]{16,}$'){ return '' }
    if($n -cmatch '[a-z]' -and $n -notmatch '\s'){ $n = ($n -replace '[-_]+', ' ').Trim() }
    # « Karims iPhone » -> « iPhone de Karim »
    if($n -match "^(.+?)['’]s (iPhone|iPad|MacBook|Mac|Galaxy|Pixel)(.*)$"){ $n = "$($matches[2])$($matches[3]) de $($matches[1])" }
    $n
}
function Get-OptiModelLabel([string]$m){
    if(-not $m){ return @{model='';vendor=''} }
    if($m -match '^iPhone'){ return @{model='iPhone';vendor='Apple'} }
    if($m -match '^iPad'){ return @{model='iPad';vendor='Apple'} }
    if($m -match '^(MacBook|iMac|Macmini|MacPro|Mac\d)'){ return @{model='Mac';vendor='Apple'} }
    if($m -match '^(AppleTV|J\d+[a-z]*AP)'){ return @{model='Apple TV';vendor='Apple'} }
    if($m -match '^(AudioAccessory|HomePod)'){ return @{model='HomePod';vendor='Apple'} }
    if($m -match '^Watch'){ return @{model='Apple Watch';vendor='Apple'} }
    if($m -match '(?i)SM-[A-Z]\d|Galaxy'){ return @{model=$m;vendor='Samsung'} }
    @{model=$m;vendor=''}
}

function Get-OptiNetwork($force){
    if(-not $force){ $c = Get-OptiCache 'network' 90; if($c){ return $c } }
    $res = @{ok=$false}
    $cfg = $null
    try{ $cfg = @(Get-NetIPConfiguration -EA Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' }) | Select-Object -First 1 }catch{}
    if(-not $cfg){ return @{ok=$false;msg="Aucune connexion reseau active n'a ete trouvee."} }
    $myIp = [string](@($cfg.IPv4Address)[0].IPAddress)
    $gw = [string](@($cfg.IPv4DefaultGateway)[0].NextHop)
    $ifIdx = [int]$cfg.InterfaceIndex
    $parts = $myIp.Split('.')
    $base = "$($parts[0]).$($parts[1]).$($parts[2])."
    # Balayage /24 en parallele (ping 400 ms), pour remplir la table ARP
    $pings = @{}
    for($i=1; $i -le 254; $i++){
        $ip = $base + $i
        try{ $p = New-Object System.Net.NetworkInformation.Ping; $pings[$ip] = @{p=$p;t=$p.SendPingAsync($ip, 400)} }catch{}
    }
    try{ [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($pings.Values | ForEach-Object { $_.t }), 4000) }catch{}
    $alive = @{}
    foreach($k in $pings.Keys){
        try{ if($pings[$k].t.IsCompleted -and $pings[$k].t.Result.Status -eq 'Success'){ $alive[$k] = $true } }catch{}
        try{ $pings[$k].p.Dispose() }catch{}
    }
    $neigh = @{}
    try{
        foreach($n in @(Get-NetNeighbor -AddressFamily IPv4 -InterfaceIndex $ifIdx -EA Stop)){
            $ip = [string]$n.IPAddress
            if(-not $ip.StartsWith($base)){ continue }
            $mac = [string]$n.LinkLayerAddress
            if(-not $mac -or $mac -match '^(00-00-00-00-00-00|FF-FF-FF-FF-FF-FF)$'){ continue }
            if([string]$n.State -match 'Unreachable|Incomplete'){ continue }
            $neigh[$ip] = $mac
        }
    }catch{}
    $ips = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach($k in $alive.Keys){ [void]$ips.Add($k) }
    foreach($k in $neigh.Keys){ [void]$ips.Add($k) }
    [void]$ips.Add($myIp)
    # Noms d'hote en parallele (400 ms max)
    $dns = @{}
    foreach($ip in $ips){ try{ $dns[$ip] = [System.Net.Dns]::GetHostEntryAsync($ip) }catch{} }
    try{ [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($dns.Values), 1500) }catch{}
    $nn = @{}
    try{ $nn = Get-OptiNetNames @($ips | Where-Object { $_ -ne $myIp }) }catch{}
    $myMac = ''
    try{ $myMac = [string]$cfg.NetAdapter.MacAddress }catch{}
    $knownFile = Join-Path (Get-OptiDataDir) 'network.json'
    $known = @{}
    $firstRun = -not (Test-Path $knownFile)
    $kj = Read-OptiJsonFile $knownFile
    if($kj){ foreach($p in $kj.PSObject.Properties){ $known[$p.Name] = [string]$p.Value } }
    $devices = New-Object System.Collections.Generic.List[object]
    foreach($ip in ($ips | Sort-Object { [int]($_.Split('.')[3]) })){
        $mac = if($ip -eq $myIp){ $myMac } else { [string]$neigh[$ip] }
        $name = ''
        try{ $t = $dns[$ip]; if($t -and $t.IsCompleted -and -not $t.IsFaulted){ $hn = [string]$t.Result.HostName; if($hn -and $hn -ne $ip){ $name = $hn } } }catch{}
        $vendor = Get-OptiOuiVendor $mac
        $ni = $nn[$ip]
        $display = ''; $model = ''
        if($ni){
            $display = Format-OptiDevName ([string]$ni.mdns)
            if(-not $display){ $display = Format-OptiDevName ([string]$ni.fn) }
            if(-not $display -and $ni.nb){ $display = [string]$ni.nb }
            $ml = Get-OptiModelLabel ([string]$ni.model)
            $model = [string]$ml.model
            if((-not $vendor -or $vendor -eq 'prive') -and $ml.vendor){ $vendor = $ml.vendor }
            if((-not $vendor -or $vendor -eq 'prive') -and $ni.maker){ $vendor = ([string]$ni.maker -split '[,(]')[0].Trim() }
            if((-not $vendor -or $vendor -eq 'prive') -and "$display $($ni.mdns)" -match '(?i)iphone|ipad|macbook|imac|apple'){ $vendor = 'Apple' }
            if((-not $vendor -or $vendor -eq 'prive') -and "$display $($ni.mdns)" -match '(?i)galaxy|samsung'){ $vendor = 'Samsung' }
        }
        if(-not $display){ $display = Format-OptiDevName $name }
        $g = Get-OptiDeviceGuess $vendor "$name $display $model" ($ip -eq $gw) ($ip -eq $myIp)
        $key = if($mac){ $mac.ToUpper() } else { $ip }
        $isNew = $false
        if(-not $known.ContainsKey($key)){ $known[$key] = (Get-Date -Format 'yyyy-MM-dd'); if(-not $firstRun -and $ip -ne $myIp){ $isNew = $true } }
        $devices.Add(@{ip=$ip;mac=$mac;name=$name;display=$display;model=$model;privateMac=($vendor -eq 'prive');vendor=$(if($vendor -eq 'prive'){''}else{$vendor});type=$g.type;label=$g.label;isNew=$isNew;isGateway=($ip -eq $gw);isSelf=($ip -eq $myIp);firstSeen=$known[$key]})
    }
    Write-OptiJsonFile $knownFile $known | Out-Null
    # DNS utilises
    $dnsSrv = @()
    try{ $dnsSrv = @((Get-DnsClientServerAddress -InterfaceIndex $ifIdx -AddressFamily IPv4 -EA Stop).ServerAddresses) }catch{}
    $okDns = @('8.8.8.8','8.8.4.4','1.1.1.1','1.0.0.1','9.9.9.9','149.112.112.112','208.67.222.222','208.67.220.220','212.27.40.240','212.27.40.241','80.10.246.2','80.10.246.129','81.253.149.1','81.253.149.2','109.0.66.10','109.0.66.20','194.158.122.10','194.158.122.15','195.238.2.21','195.238.2.22','212.217.0.1','212.217.0.12','94.140.14.14','94.140.15.15')
    $dnsLevel = 'ok'
    foreach($s in $dnsSrv){
        $s = [string]$s
        $private = ($s -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.)')
        if(-not $private -and $okDns -notcontains $s -and $s -ne $gw){ $dnsLevel = 'check' }
    }
    $res = @{
        ok=$true; myIp=$myIp; gateway=$gw; adapter=[string]$cfg.InterfaceAlias
        devices=$devices.ToArray(); count=$devices.Count; newCount=@($devices | Where-Object { $_.isNew }).Count
        wifi=(Get-OptiWifiInfo); dns=@($dnsSrv); dnsLevel=$dnsLevel
        date=(Get-Date -Format 'dd/MM/yyyy HH:mm')
    }
    Set-OptiCache 'network' $res
    $res
}

function Invoke-OptiSpeedTest {
    try{ [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 }catch{}
    $url = 'https://speed.cloudflare.com/__down?bytes=25000000'
    $wc = New-Object System.Net.WebClient
    try{
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $data = $wc.DownloadData($url)
        $sw.Stop()
        $sec = [Math]::Max(0.2, $sw.Elapsed.TotalSeconds)
        $mbps = [Math]::Round(($data.Length * 8 / 1MB) / $sec, 1)
        $lvl = if($mbps -ge 30){ 'ok' } elseif($mbps -ge 8){ 'warn' } else { 'crit' }
        $txt = if($mbps -ge 100){ 'Tres rapide : films en 4K et visio sans souci' } elseif($mbps -ge 30){ 'Rapide : films et visio sans souci' } elseif($mbps -ge 8){ 'Correct pour internet et la visio' } else { 'Lent : rapprochez-vous de la box ou contactez votre fournisseur' }
        @{ok=$true;mbps=$mbps;level=$lvl;text=$txt}
    }catch{
        @{ok=$false;msg="Test impossible : verifiez la connexion internet."}
    } finally { try{ $wc.Dispose() }catch{} }
}

# ─── LOGICIELS A METTRE A JOUR (winget) ────────────────────────────────────────

function Get-OptiWingetPath {
    $c = Get-Command winget.exe -EA SilentlyContinue
    if($c){ return $c.Source }
    $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if(Test-Path $p){ return $p }
    try{
        $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -EA Stop | Sort-Object Version -Descending | Select-Object -First 1
        if($pkg){ $q = Join-Path $pkg.InstallLocation 'winget.exe'; if(Test-Path $q){ return $q } }
    }catch{}
    $null
}

function Invoke-OptiWinget($wargs, $timeoutSec){
    $w = Get-OptiWingetPath
    if(-not $w){ return @{ok=$false;code=-1;out=''} }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $w
    $psi.Arguments = $wargs
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $pr = [System.Diagnostics.Process]::Start($psi)
    $t = $pr.StandardOutput.ReadToEndAsync()
    $t2 = $pr.StandardError.ReadToEndAsync()
    if(-not $pr.WaitForExit($timeoutSec * 1000)){ try{ $pr.Kill() }catch{}; return @{ok=$false;code=-2;out=''} }
    @{ok=$true;code=$pr.ExitCode;out=[string]$t.Result}
}

function Get-OptiSoftUpdates($force){
    if(-not $force){ $c = Get-OptiCache 'softupd' 1800; if($c){ return $c } }
    if(-not (Get-OptiWingetPath)){ return @{available=$false;items=@();count=0;msg="L'outil de mise a jour de Windows (winget) n'est pas installe sur ce PC."} }
    $r = Invoke-OptiWinget 'upgrade --include-unknown --accept-source-agreements --disable-interactivity' 120
    if(-not $r.ok){ return @{available=$false;items=@();count=0;msg='La recherche de mises a jour a echoue.'} }
    $lines = @(([string]$r.out) -split "`r?`n" | ForEach-Object { ($_ -replace '^.*\r','') })
    $items = New-Object System.Collections.Generic.List[object]
    $sep = -1
    for($i=0; $i -lt $lines.Count; $i++){ if($lines[$i] -match '^-{10,}'){ $sep = $i; break } }
    if($sep -gt 0){
        $hdr = $lines[$sep-1]
        $starts = New-Object System.Collections.Generic.List[int]
        $starts.Add(0)
        for($c=1; $c -lt $hdr.Length; $c++){ if($hdr[$c] -ne ' ' -and $hdr[$c-1] -eq ' '){ $starts.Add($c) } }
        for($i=$sep+1; $i -lt $lines.Count; $i++){
            $l = $lines[$i]
            if(-not $l.Trim()){ break }
            if($l -match '^\d+\s+\D'){ break }
            if($starts.Count -lt 4 -or $l.Length -lt $starts[3]){ continue }
            $col = { param($n) $s = $starts[$n]; $e = $(if($n+1 -lt $starts.Count){ $starts[$n+1] } else { $l.Length }); if($s -ge $l.Length){ '' } else { $l.Substring($s, [Math]::Min($e,$l.Length)-$s).Trim() } }
            $name = & $col 0; $id = & $col 1; $cur = & $col 2; $new = & $col 3
            if(-not $id -or $id -match '…|\.\.\.$' -or $id -match '\s'){ continue }
            if($new -match '^\d' -or $new){ $items.Add(@{name=$name;id=$id;current=$cur;available=$new}) }
        }
    }
    $res = @{available=$true;items=$items.ToArray();count=$items.Count}
    Set-OptiCache 'softupd' $res
    $res
}

function Invoke-OptiSoftUpdate($id){
    if(-not (Test-IsPro)){ return @{ok=$false;msg='La mise a jour des logiciels est reservee a la version Premium.'} }
    $i = [string]$id
    if($i -notmatch '^[A-Za-z0-9._+\-]+$'){ return @{ok=$false;msg='Identifiant invalide'} }
    $r = Invoke-OptiWinget ("upgrade --id `"$i`" --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity") 1200
    try{ Remove-Item (Get-OptiCacheFile 'softupd') -Force -EA SilentlyContinue }catch{}
    if(-not $r.ok){ return @{ok=$false;msg='La mise a jour a pris trop de temps ou n''a pas pu demarrer.'} }
    if($r.code -eq 0){ return @{ok=$true;msg='Mise a jour installee'} }
    @{ok=$false;msg="La mise a jour n'a pas abouti (code $($r.code)). Fermez le logiciel concerne et reessayez."}
}

# ─── POINTS DE RESTAURATION ────────────────────────────────────────────────────

function Get-OptiRestorePoints {
    $list = @()
    try{
        $list = @(Get-ComputerRestorePoint -EA Stop | Sort-Object SequenceNumber -Descending | Select-Object -First 15 | ForEach-Object {
            $d = ''
            try{ $d = ([Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime)).ToString('dd/MM/yyyy HH:mm') }catch{}
            @{id=[int]$_.SequenceNumber;desc=[string]$_.Description;date=$d}
        })
    }catch{}
    $enabled = $true
    try{ $rp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -EA Stop; if($rp.RPSessionInterval -eq 0 -and $list.Count -eq 0){ $enabled = $false } }catch{}
    @{items=@($list);count=$list.Count;enabled=$enabled}
}

function New-OptiRestorePoint($desc){
    if(-not $desc){ $desc = 'OptiPC - avant optimisation' }
    $before = 0
    try{ $before = @(Get-ComputerRestorePoint -EA Stop).Count }catch{}
    try{ Enable-ComputerRestore -Drive "$env:SystemDrive\" -EA SilentlyContinue }catch{}
    try{
        Checkpoint-Computer -Description $desc -RestorePointType 'MODIFY_SETTINGS' -EA Stop -WarningAction SilentlyContinue
    }catch{
        return @{ok=$false;msg="Le point de restauration n'a pas pu etre cree : $($_.Exception.Message)"}
    }
    $after = $before
    try{ $after = @(Get-ComputerRestorePoint -EA Stop).Count }catch{}
    if($after -gt $before){ return @{ok=$true;created=$true;msg='Point de restauration cree'} }
    @{ok=$true;created=$false;msg='Un point de restauration recent existe deja (Windows en cree un par jour maximum)'}
}

function Open-OptiRestoreUI {
    try{ Start-Process "$env:SystemRoot\System32\rstrui.exe" -EA Stop; @{ok=$true} }catch{ @{ok=$false;msg=$_.Exception.Message} }
}

# ─── HISTORIQUE DU SCORE ───────────────────────────────────────────────────────

function Add-OptiScoreHistory($score){
    $s = [int]$score
    if($s -le 0){ return }
    $f = Join-Path (Get-OptiDataDir) 'score.json'
    $list = New-Object System.Collections.Generic.List[object]
    $j = Read-OptiJsonFile $f
    if($j){ foreach($e in @($j)){ if($e -and $e.d){ $list.Add(@{d=[string]$e.d;s=[int]$e.s}) } } }
    $today = (Get-Date -Format 'yyyy-MM-dd')
    $found = $false
    foreach($e in $list){ if($e.d -eq $today){ $e.s = $s; $found = $true } }
    if(-not $found){ $list.Add(@{d=$today;s=$s}) }
    $keep = @($list | Sort-Object { $_.d } | Select-Object -Last 90)
    Write-OptiJsonFile $f $keep | Out-Null
}

function Get-OptiScoreHistory {
    $f = Join-Path (Get-OptiDataDir) 'score.json'
    $j = Read-OptiJsonFile $f
    $list = @()
    if($j){ $list = @($j | Where-Object { $_ -and $_.d } | ForEach-Object { @{d=[string]$_.d;s=[int]$_.s} }) }
    $cut = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd')
    @{items=@($list | Where-Object { $_.d -ge $cut })}
}

# ─── RAPPEL PAR UN TECHNICIEN ──────────────────────────────────────────────────

function Send-OptiCallbackRequest($prenom, $telephone, $sujet){
    $tel = ([string]$telephone) -replace '[^\d+]',''
    if($tel.Length -lt 9){ return @{ok=$false;msg='Numero de telephone invalide'} }
    $mid = ''; try{ $mid = Get-MachineFingerprint }catch{}
    $ver = ''; try{ $ver = [string](Get-OptiPCVersion) }catch{}
    $pro = $false; try{ $pro = [bool](Test-IsPro) }catch{}
    $body = @{prenom=[string]$prenom;telephone=[string]$telephone;sujet=[string]$sujet;source='logiciel';machine=$mid;version="OptiPC $ver";premium=$pro;pc=$env:COMPUTERNAME}
    try{
        $r = Invoke-OptiPCWeb ((Get-OptiPCCrmBase) + '/api/rappel-optipc') 'POST' $body 30
        if($r.ok){ return @{ok=$true;msg='Demande envoyee : un technicien SecureeTech vous rappelle rapidement.'} }
    }catch{}
    @{ok=$false;msg="La demande n'a pas pu etre envoyee. Appelez directement le 05 54 54 23 43 (du lundi au vendredi, de 10 h a 17 h)."}
}

# ─── PLANIFICATION ET RAPPELS (appeles par le logiciel natif) ─────────────────

function Write-OptiSchedLog($msg){
    $f = "$env:TEMP\optipc_sched_debug.log"
    try { $fi = New-Object IO.FileInfo($f); if($fi.Exists -and $fi.Length -gt 512KB){ [IO.File]::WriteAllText($f, '', [Text.Encoding]::UTF8) } } catch {}
    try { [IO.File]::AppendAllText($f, "[$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')] $msg`n", [Text.Encoding]::UTF8) } catch {}
}

function Invoke-OptiScheduleTick {
    $sf = "$env:LOCALAPPDATA\OptiPC\schedule.json"
    if(-not (Test-Path $sf)){ return @{ran=$false} }
    try{
        $sc = Get-Content $sf -Raw -EA Stop | ConvertFrom-Json
        $now = Get-Date
        $last = [datetime]::MinValue
        if($sc.lastRun -and "$($sc.lastRun)" -ne ''){ try{ $last = [datetime]::Parse($sc.lastRun) }catch{} }
        $run = $false; $raison = ''
        if(-not $sc.frequency -or $sc.frequency -eq 'remove'){ return @{ran=$false} }
        elseif($sc.frequency -eq 'startup'){ if($last.Date -lt $now.Date){ $run = $true; $raison = 'demarrage' } }
        elseif($sc.frequency -eq 'daily' -or $sc.frequency -eq 'weekly'){
            $t = [datetime]::ParseExact([string]$sc.time, 'HH:mm', $null)
            $tgt = Get-Date -Hour $t.Hour -Minute $t.Minute -Second 0
            $dayOk = ($sc.frequency -eq 'daily') -or ($now.DayOfWeek -eq [DayOfWeek]::Monday)
            if($dayOk -and $now -ge $tgt -and $last.Date -lt $now.Date){ $run = $true; $raison = "$($sc.frequency) $($sc.time)" }
        }
        if(-not $run){ return @{ran=$false} }
        # Le nettoyage planifie est une fonction Premium.
        if(-not (Test-IsPro)){ Write-OptiSchedLog 'SKIP : version gratuite'; return @{ran=$false;reason='free'} }
        $sc.lastRun = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
        try{ $sc | ConvertTo-Json -Depth 5 | Set-Content $sf -Encoding UTF8 }catch{}
        $logP = "$env:LOCALAPPDATA\OptiPC\clean.log"
        [IO.File]::AppendAllText($logP, "[$(Get-Date -F 'dd/MM/yyyy HH:mm:ss')] [DEBUT] Nettoyage planifie lance ($raison)`n", [Text.Encoding]::UTF8)
        $r = Invoke-Cleaning @(Get-OptiAutoCleanIds)
        $line = "[$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')] [OK] Nettoyage planifie termine : $($r.cleaned) liberes"
        [IO.File]::AppendAllText($logP, $line + "`n", [Text.Encoding]::UTF8)
        Write-OptiSchedLog $line
        return @{ran=$true;cleaned=[string]$r.cleaned}
    }catch{
        Write-OptiSchedLog "ERREUR planification : $($_.Exception.Message)"
        return @{ran=$false;error=$_.Exception.Message}
    }
}

function Invoke-OptiNudgeCheck {
    # Une fois par semaine : analyse discrete. En version gratuite, une notification
    # montre les VRAIS chiffres (Go a nettoyer, points de securite).
    $st = Join-Path (Get-OptiDataDir) 'nudge.json'
    $s = Get-OptiSettings
    if(-not $s.notifPro){ return @{show=$false} }
    $last = [datetime]::MinValue
    try{ $j = Read-OptiJsonFile $st; if($j -and $j.last){ $last = [datetime]::Parse([string]$j.last) } }catch{}
    if(((Get-Date) - $last).TotalDays -lt 7){ return @{show=$false} }
    Write-OptiJsonFile $st @{last=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')} | Out-Null
    $pro = $false; try{ $pro = [bool](Test-IsPro) }catch{}
    if($pro){ return @{show=$false} }
    $a = Get-DirtyAnalysis
    try{ Add-OptiScoreHistory $a.score }catch{}
    $sec = Get-SecurityStatus
    $issues = @()
    if(-not $sec.defEnabled -and -not $sec.otherAV){ $issues += 'antivirus desactive' }
    elseif($sec.defSigAge -gt 7 -and -not $sec.otherAV){ $issues += 'antivirus pas a jour' }
    if(-not $sec.fwOk){ $issues += 'pare-feu incomplet' }
    if(-not $sec.uacOk){ $issues += 'controle de compte desactive' }
    if(-not $sec.ssOk){ $issues += 'SmartScreen desactive' }
    $thr = 0
    try { $thr = @(Get-MpThreatDetection -EA SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-30) }).Count } catch {}
    $parts = @()
    if([long]$a.totalBytes -ge 200MB){ $parts += "$($a.total) de fichiers inutiles a nettoyer" }
    if($thr -gt 0){ $parts += "$thr menace(s) detectee(s) ce mois-ci" }
    if($issues.Count -gt 0){ $parts += "$($issues.Count) point(s) de securite a corriger ($($issues -join ', '))" }
    if(-not $parts.Count){ return @{show=$false} }
    $warn = ($thr -gt 0 -or $issues.Count -gt 0)
    $title = if($warn){ "OptiPC : votre PC a besoin d'attention" } else { 'OptiPC : de la place a liberer' }
    @{show=$true;warn=$warn;title=$title;text=(($parts -join ' · ') + '. Cliquez pour voir et corriger.')}
}

function Register-OptiStartup($exe){
    $e = [string]$exe
    if(-not $e -or -not (Test-Path -LiteralPath $e)){ return @{ok=$false} }
    try{
        $d = Get-OptiDataDir
        [IO.File]::WriteAllText((Join-Path $d 'optipc.cfg'), $e, [Text.Encoding]::UTF8)
    }catch{}
    # Uniquement pour la version installee (Program Files) : une copie de test
    # lancee depuis Telechargements ne doit pas s'inscrire au demarrage.
    $pf = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    $installed = $false
    foreach($p in $pf){ if($e.StartsWith($p + '\', [StringComparison]::OrdinalIgnoreCase)){ $installed = $true } }
    if(-not $installed){ return @{ok=$true;installed=$false} }
    # La V1 s'inscrivait aussi dans la cle Run : avec un logiciel qui demande les droits
    # administrateur, cela affichait une fenetre de confirmation a chaque ouverture de
    # session. La 2.0 utilise uniquement la tache planifiee (elevee, sans confirmation).
    try{ Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'OptiPC' -EA SilentlyContinue }catch{}
    try{
        $task = Get-ScheduledTask -TaskName 'OptiPC' -EA SilentlyContinue
        $need = $true
        if($task){
            $a = @($task.Actions)[0]
            $need = -not ($a -and ([string]$a.Execute) -ieq $e -and ([string]$a.Arguments) -match '-AuDemarrage')
        }
        if($need){
            # Meme definition que l'installateur (OptiPC.iss) : a l'ouverture de session de
            # tout membre du groupe Utilisateurs (SID S-1-5-32-545, independant de la langue).
            $act = New-ScheduledTaskAction -Execute $e -Argument '-AuDemarrage'
            $trg = New-ScheduledTaskTrigger -AtLogOn
            $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
            $pri = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Highest
            Register-ScheduledTask -TaskName 'OptiPC' -Action $act -Trigger $trg -Settings $set -Principal $pri -Force -EA Stop | Out-Null
        }
        if(-not (Get-ScheduledTask -TaskName 'OptiPC' -EA SilentlyContinue)){ return @{ok=$false;installed=$true;error='tache OptiPC absente apres inscription'} }
        # Entree visible dans Gestionnaire des taches > Applications de demarrage : le lanceur
        # sans droits (OptiPCDemarrage.exe) demarre la tache. On ne touche pas a StartupApproved :
        # si le client l'a desactivee, elle reste desactivee.
        $lanceur = Join-Path (Split-Path -Parent $e) 'OptiPCDemarrage.exe'
        if(Test-Path -LiteralPath $lanceur){
            $run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            $voulu = '"' + $lanceur + '"'
            if([string](Get-ItemProperty $run -Name 'OptiPC' -EA SilentlyContinue).OptiPC -ne $voulu){
                Set-ItemProperty $run -Name 'OptiPC' -Value $voulu -EA Stop
            }
        }
        return @{ok=$true;installed=$true}
    }catch{ return @{ok=$false;installed=$true;error=$_.Exception.Message} }
}

# ─── MEMOIRE VIRTUELLE (correctif 2.0 : la V1 appelait une action inexistante) ─

function Set-OptiPagefile([int]$sizeMB){
    try{
        $cs = Get-CimInstance Win32_ComputerSystem -EA Stop
        if($sizeMB -le 0){
            Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$true} -EA Stop
            return @{success=$true;output='Memoire virtuelle geree automatiquement par Windows. Redemarrez le PC pour appliquer.'}
        }
        if($cs.AutomaticManagedPagefile){ Set-CimInstance -InputObject $cs -Property @{AutomaticManagedPagefile=$false} -EA Stop }
        $sysDrive = "$env:SystemDrive"
        $pf = Get-CimInstance Win32_PageFileSetting -EA SilentlyContinue | Where-Object { ([string]$_.Name).StartsWith($sysDrive, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
        if(-not $pf){ $pf = New-CimInstance -ClassName Win32_PageFileSetting -Property @{Name="$sysDrive\pagefile.sys"} -EA Stop }
        Set-CimInstance -InputObject $pf -Property @{InitialSize=[uint32]$sizeMB;MaximumSize=[uint32]$sizeMB} -EA Stop
        @{success=$true;output=("Memoire virtuelle reglee sur {0} Go. Redemarrez le PC pour appliquer." -f [Math]::Round($sizeMB/1024,1))}
    }catch{
        @{success=$false;output="Reglage impossible : $($_.Exception.Message)"}
    }
}

# ══════════════════════════════════════════════════════════════════════════
#  NAVIGATEURS DETOURNES (Chrome, Edge, Brave, Firefox)
#  Les pirates imposent leur page de demarrage / moteur de recherche par des
#  « strategies » Windows (« Gere par votre organisation »), des raccourcis
#  modifies, des taches planifiees ou les reglages du profil.
#  Detection gratuite ; reparation reservee a Premium.
#  Jamais touches : favoris, mots de passe, historique, cookies.
# ══════════════════════════════════════════════════════════════════════════
function Get-OptiBrowserDefs {
    @(
        @{id='chrome'; name='Google Chrome';   exe='chrome.exe';  pol='Google\Chrome';        data="$env:LOCALAPPDATA\Google\Chrome\User Data"},
        @{id='edge';   name='Microsoft Edge';  exe='msedge.exe';  pol='Microsoft\Edge';       data="$env:LOCALAPPDATA\Microsoft\Edge\User Data"},
        @{id='brave';  name='Brave';           exe='brave.exe';   pol='BraveSoftware\Brave';  data="$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"},
        @{id='firefox';name='Mozilla Firefox'; exe='firefox.exe'; pol='Mozilla\Firefox';      data=''}
    )
}
function Get-OptiPolValues { @('HomepageLocation','HomepageIsNewTabPage','NewTabPageLocation','RestoreOnStartup','DefaultSearchProviderEnabled','DefaultSearchProviderSearchURL','DefaultSearchProviderName','DefaultSearchProviderKeyword','DefaultSearchProviderSuggestURL','DefaultSearchProviderNewTabURL','ShowHomeButton') }
function Get-OptiPolKeys { @('RestoreOnStartupURLs','URLsToRestoreOnStartup','Homepage','SearchEngines','NewTabPage') }
function Get-OptiUrlHost([string]$u){
    try{ if($u -notmatch '^[a-z]+://'){ $u = 'http://' + $u }; return ([Uri]$u).Host.ToLower() }catch{ return [string]$u }
}
function Test-OptiSafeHost([string]$h){
    $h = ([string]$h).ToLower()
    $h -match '(^|\.)(google\.[a-z.]+|bing\.com|msn\.com|microsoft\.com|yahoo\.com|duckduckgo\.com|qwant\.com|ecosia\.org|lilo\.org|startpage\.com|brave\.com|search\.brave\.com|mozilla\.org|firefox\.com|wikipedia\.org|orange\.fr|free\.fr|sfr\.fr|laposte\.net|bouyguestelecom\.fr|secureetech\.com)$'
}
function Read-OptiJsonDict([string]$path){
    Add-Type -AssemblyName System.Web.Extensions -EA SilentlyContinue
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue; $js.RecursionLimit = 1000
    $txt = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    ,$js.DeserializeObject($txt)
}
function Write-OptiJsonDict([string]$path, $obj){
    Add-Type -AssemblyName System.Web.Extensions -EA SilentlyContinue
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = [int]::MaxValue; $js.RecursionLimit = 1000
    [IO.File]::WriteAllText($path, $js.Serialize($obj), (New-Object System.Text.UTF8Encoding($false)))
}
function Get-OptiDictPath($d, [string]$dotted){
    $cur = $d
    foreach($k in $dotted.Split('.')){
        if($cur -is [System.Collections.IDictionary] -and ([System.Collections.IDictionary]$cur).Contains($k)){ $cur = $cur[$k] } else { return $null }
    }
    ,$cur
}
function Get-OptiBrowserHijack {
    $items = New-Object System.Collections.Generic.List[object]
    $add = { param($browser,$kind,$level,$title,$detail,$target) $items.Add(@{browser=$browser;kind=$kind;level=$level;title=$title;detail=[string]$detail;target=[string]$target}) }
    foreach($b in (Get-OptiBrowserDefs)){
        # 1) Strategies imposees
        foreach($root in @('HKLM:\SOFTWARE\Policies','HKCU:\SOFTWARE\Policies','HKLM:\SOFTWARE\WOW6432Node\Policies')){
            $k = Join-Path $root $b.pol
            if(-not (Test-Path $k)){ continue }
            try{
                $p = Get-ItemProperty $k -EA Stop
                foreach($v in (Get-OptiPolValues)){
                    $val = $p.$v
                    if($null -ne $val -and "$val" -ne ''){
                        $txt = [string]$val
                        if($v -match 'URL|Location'){ $txt = Get-OptiUrlHost $txt }
                        & $add $b.name 'policy' 'crit' "Réglage imposé : $v" $txt "$k|$v"
                    }
                }
                foreach($sk in (Get-OptiPolKeys)){
                    $kk = Join-Path $k $sk
                    if(Test-Path $kk){
                        $vals = @(); try{ $pp = Get-ItemProperty $kk; $vals = @($pp.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { Get-OptiUrlHost ([string]$_.Value) }) }catch{}
                        & $add $b.name 'policykey' 'crit' "Pages imposées au démarrage" ($vals -join ', ') "$kk|"
                    }
                }
                $fk = Join-Path $k 'ExtensionInstallForcelist'
                if(Test-Path $fk){
                    try{
                        $pp = Get-ItemProperty $fk
                        foreach($pr in @($pp.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' })){
                            $val = [string]$pr.Value
                            $offStore = ($val -match ';' -and $val -notmatch 'clients2\.google\.com|edge\.microsoft\.com|microsoftedge\.microsoft\.com')
                            if($offStore){ & $add $b.name 'extension' 'crit' "Extension imposée hors boutique officielle" ($val.Split(';')[0]) "$fk|$($pr.Name)" }
                            else { & $add $b.name 'extinfo' 'check' "Extension imposée (boutique officielle)" ($val.Split(';')[0]) '' }
                        }
                    }catch{}
                }
            }catch{}
        }
        # 2) Reglages du profil (pages de demarrage, page d'accueil, moteur de recherche)
        if($b.data -and (Test-Path $b.data)){
            foreach($pf in @(Get-ChildItem $b.data -Directory -EA SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })){
                $pref = Join-Path $pf.FullName 'Preferences'
                $sec  = Join-Path $pf.FullName 'Secure Preferences'
                foreach($file in @($pref,$sec)){
                    if(-not (Test-Path $file)){ continue }
                    $d = $null; try{ $d = Read-OptiJsonDict $file }catch{ continue }
                    $ros = Get-OptiDictPath $d 'session.restore_on_startup'
                    $urls = Get-OptiDictPath $d 'session.startup_urls'; if($null -eq $urls){ $urls = @() } else { $urls = @($urls) }
                    if([string]$ros -eq '4' -and $urls.Count){
                        $bad = @($urls | ForEach-Object { Get-OptiUrlHost ([string]$_) } | Where-Object { $_ -and -not (Test-OptiSafeHost $_) })
                        if($bad.Count){ & $add $b.name 'prefs' 'crit' "Page de démarrage détournée ($($pf.Name))" (($bad | Select-Object -Unique) -join ', ') $pf.FullName }
                    }
                    $hp = Get-OptiDictPath $d 'homepage'
                    if($hp -and -not (Test-OptiSafeHost (Get-OptiUrlHost ([string]$hp)))){ & $add $b.name 'prefs' 'crit' "Page d'accueil détournée ($($pf.Name))" (Get-OptiUrlHost ([string]$hp)) $pf.FullName }
                    $su = Get-OptiDictPath $d 'default_search_provider_data.template_url_data.url'
                    if($su -and -not (Test-OptiSafeHost (Get-OptiUrlHost ([string]$su)))){ & $add $b.name 'prefs' 'crit' "Moteur de recherche détourné ($($pf.Name))" (Get-OptiUrlHost ([string]$su)) $pf.FullName }
                }
            }
        }
    }
    # Firefox : fichier de strategies dans le dossier du programme
    foreach($ffDir in @("$env:ProgramFiles\Mozilla Firefox", "${env:ProgramFiles(x86)}\Mozilla Firefox")){
        $pj = Join-Path $ffDir 'distribution\policies.json'
        if(Test-Path $pj){ try{ $t = [IO.File]::ReadAllText($pj); if($t -match '"(Homepage|SearchEngines|NewTabPage|ExtensionSettings)"'){ & $add 'Mozilla Firefox' 'ffpolicy' 'crit' 'Réglages imposés (policies.json)' 'page d''accueil / recherche' $pj } }catch{} }
    }
    # 3) Raccourcis modifies (adresse ajoutee derriere le navigateur)
    $sh = $null; try{ $sh = New-Object -ComObject WScript.Shell }catch{}
    if($sh){
        $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('StartMenu'), [Environment]::GetFolderPath('CommonStartMenu'), "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar", "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch")
        foreach($dir in $dirs){
            if(-not $dir -or -not (Test-Path $dir)){ continue }
            foreach($lnk in @(Get-ChildItem $dir -Filter *.lnk -Recurse -Depth 2 -EA SilentlyContinue)){
                try{
                    $s = $sh.CreateShortcut($lnk.FullName)
                    if([string]$s.TargetPath -match '(?i)\\(chrome|msedge|brave|firefox)\.exe$' -and [string]$s.Arguments -match '(?i)(https?://|www\.|\.(com|net|org|info|xyz|top|online|site)\b)'){
                        $h = ([regex]::Match([string]$s.Arguments, '(?i)(https?://\S+|www\.\S+|\S+\.(com|net|org|info|xyz|top|online|site)\S*)')).Value
                        & $add ([IO.Path]::GetFileNameWithoutExtension($lnk.Name)) 'shortcut' 'crit' 'Raccourci modifié' (Get-OptiUrlHost $h) $lnk.FullName
                    }
                }catch{}
            }
        }
    }
    # 4) Taches planifiees qui ouvrent un site
    try{
        foreach($t in @(Get-ScheduledTask -EA Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })){
            foreach($a in @($t.Actions)){
                $exe = [string]$a.Execute; $arg = [string]$a.Arguments
                if(($exe -match '(?i)(chrome|msedge|brave|firefox|iexplore|explorer|cmd|powershell)(\.exe)?"?$' -or $exe -match '(?i)^https?://') -and ("$exe $arg") -match '(?i)https?://'){
                    $h = Get-OptiUrlHost (([regex]::Match("$exe $arg", '(?i)https?://[^\s"]+')).Value)
                    if(-not (Test-OptiSafeHost $h)){ & $add 'Windows' 'task' 'crit' "Tâche qui ouvre un site : $($t.TaskName)" $h ($t.TaskPath + '|' + $t.TaskName) }
                }
            }
        }
    }catch{}
    $seen = @{}; $uniq = New-Object System.Collections.Generic.List[object]
    foreach($x in $items){ $key = "$($x.browser)|$($x.title)|$($x.detail)"; if(-not $seen.ContainsKey($key)){ $seen[$key] = 1; $uniq.Add($x) } }
    $arr = $uniq.ToArray()
    @{ items = $arr; count = @($arr | Where-Object { $_.level -eq 'crit' }).Count; date = (Get-Date -Format 'dd/MM/yyyy HH:mm') }
}
function Repair-OptiBrowserHijack {
    if(-not (Test-IsPro)){ return @{ok=$false;premium=$true;msg='La réparation des navigateurs est réservée à la version Premium.'} }
    $scan = Get-OptiBrowserHijack
    $fixed = 0; $fail = 0
    # Fermer les navigateurs (les onglets sont proposes a la reouverture)
    foreach($p in @('chrome','msedge','brave','firefox')){ try{ Get-Process $p -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue }catch{} }
    Start-Sleep -Milliseconds 1500
    $profilesDone = @{}
    foreach($it in @($scan.items)){
        try{
            switch($it.kind){
                'policy' {
                    $k,$v = $it.target.Split('|',2)
                    Remove-ItemProperty -Path $k -Name $v -Force -EA Stop; $fixed++
                }
                'policykey' { $k = $it.target.Split('|')[0]; Remove-Item -Path $k -Recurse -Force -EA Stop; $fixed++ }
                'extension' { $k,$v = $it.target.Split('|',2); Remove-ItemProperty -Path $k -Name $v -Force -EA Stop; $fixed++ }
                'ffpolicy' { Move-Item -LiteralPath $it.target -Destination ($it.target + '.optipc-desactive') -Force -EA Stop; $fixed++ }
                'shortcut' {
                    $sh = New-Object -ComObject WScript.Shell
                    $s = $sh.CreateShortcut($it.target)
                    $clean = [regex]::Replace([string]$s.Arguments, '(?i)"?(https?://\S+|www\.\S+|\S+\.(com|net|org|info|xyz|top|online|site)\S*)"?', '').Trim()
                    $s.Arguments = $clean; $s.Save(); $fixed++
                }
                'task' { $tp,$tn = $it.target.Split('|',2); Unregister-ScheduledTask -TaskPath $tp -TaskName $tn -Confirm:$false -EA Stop; $fixed++ }
                'prefs' {
                    if($profilesDone.ContainsKey($it.target)){ $fixed++; break }
                    $profilesDone[$it.target] = $true
                    foreach($name in @('Preferences','Secure Preferences')){
                        $file = Join-Path $it.target $name
                        if(-not (Test-Path $file)){ continue }
                        Copy-Item -LiteralPath $file -Destination ($file + '.optipc.bak') -Force -EA SilentlyContinue
                        $d = Read-OptiJsonDict $file
                        $sess = Get-OptiDictPath $d 'session'
                        if($sess -is [System.Collections.IDictionary]){ $sess.Remove('restore_on_startup') | Out-Null; $sess.Remove('startup_urls') | Out-Null }
                        foreach($kk in @('homepage','homepage_is_newtabpage','default_search_provider_data','default_search_provider')){ if(([System.Collections.IDictionary]$d).Contains($kk)){ $d.Remove($kk) | Out-Null } }
                        $macs = Get-OptiDictPath $d 'protection.macs'
                        if($macs -is [System.Collections.IDictionary]){
                            foreach($kk in @('homepage','homepage_is_newtabpage','default_search_provider_data')){ $macs.Remove($kk) | Out-Null }
                            $ms = $macs['session']; if($ms -is [System.Collections.IDictionary]){ $ms.Remove('restore_on_startup') | Out-Null; $ms.Remove('startup_urls') | Out-Null }
                        }
                        Write-OptiJsonDict $file $d
                    }
                    $fixed++
                }
            }
        }catch{ $fail++ }
    }
    try{ gpupdate /target:computer /force 2>&1 | Out-Null }catch{}
    $after = Get-OptiBrowserHijack
    @{ ok = ($fixed -gt 0 -or $scan.count -eq 0); fixed = $fixed; failed = $fail; remaining = $after.count; msg = "$fixed problème(s) corrigé(s)" + $(if($after.count){ " · $($after.count) restant(s)" } else { '' }) }
}
