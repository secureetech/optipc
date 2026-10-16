$root = Split-Path $PSScriptRoot -Parent
$src = (Get-Content "$root/src/engine/functions.ps1" -Raw) + "`n" + (Get-Content "$root/src/engine/extra.ps1" -Raw)
. ([scriptblock]::Create($src))
# Reponse mDNS fabriquee : PTR 24.1.168.192.in-addr.arpa -> iPhone-de-Karim.local + TXT model=iPhone14,2
$ms = New-Object IO.MemoryStream
$ms.Write([byte[]](0,0,0x84,0,0,0,0,2,0,0,0,0),0,12)
function W($n){ foreach($l in $n.Split('.')){ $b=[Text.Encoding]::UTF8.GetBytes($l); $ms.WriteByte($b.Length); $ms.Write($b,0,$b.Length) }; $ms.WriteByte(0) }
W '24.1.168.192.in-addr.arpa'; $ms.Write([byte[]](0,12,0,1,0,0,0,120),0,8)
$tgt = New-Object IO.MemoryStream; foreach($l in 'iPhone-de-Karim.local'.Split('.')){ $b=[Text.Encoding]::UTF8.GetBytes($l); $tgt.WriteByte($b.Length); $tgt.Write($b,0,$b.Length) }; $tgt.WriteByte(0); $tb=$tgt.ToArray()
$ms.WriteByte(0); $ms.WriteByte($tb.Length); $ms.Write($tb,0,$tb.Length)
W 'iPhone-de-Karim._device-info._tcp.local'; $ms.Write([byte[]](0,16,0,1,0,0,0,120),0,8)
$t=[Text.Encoding]::UTF8.GetBytes('model=iPhone14,2'); $ms.WriteByte(0); $ms.WriteByte($t.Length+1); $ms.WriteByte($t.Length); $ms.Write($t,0,$t.Length)
$pk = Read-OptiDnsPacket $ms.ToArray()
$pk | % { "$($_.type) $($_.name) => $($_.data -join ',')" }
Format-OptiDevName 'iPhone-de-Karim.local'
Format-OptiDevName "Karim's iPhone"
Format-OptiDevName 'DESKTOP-AB12'
(Get-OptiModelLabel 'iPhone14,2').vendor
(Get-OptiDeviceGuess 'Apple' ' iPhone de Karim iPhone' $false $false).label
$q = New-OptiDnsQuery '_device-info._tcp.local' 12 $true; "qlen=" + $q.Length
$info = Get-OptiNetNames @('127.0.0.1'); "names ok " + $info.Count
