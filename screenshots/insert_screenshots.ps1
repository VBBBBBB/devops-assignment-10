$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSCommandPath
$docx = 'C:\Users\bhamr\anti\Devops\Assignment\Devops Ass 10.docx'
$work = Join-Path $env:TEMP 'ass10work'
$ex = Join-Path $work 'ex'

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item $docx (Join-Path $work 'backup.docx') -Force

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($docx, $ex)

$UTF8 = New-Object System.Text.UTF8Encoding($false)
$docXmlPath = Join-Path $ex 'word\document.xml'
$relsPath = Join-Path $ex 'word\_rels\document.xml.rels'
$ctPath = Join-Path $ex '[Content_Types].xml'

$xml = [System.IO.File]::ReadAllText($docXmlPath)
$rels = [System.IO.File]::ReadAllText($relsPath)
$ct = [System.IO.File]::ReadAllText($ctPath)

$maxId = 0
foreach ($rm in [regex]::Matches($rels, 'Id="rId(\d+)"')) {
    $n = [int]$rm.Groups[1].Value
    if ($n -gt $maxId) { $maxId = $n }
}

function New-Drawing([int]$imgN, [string]$rid) {
    $id = 910000 + $imgN
    return '<w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">' +
        '<wp:extent cx="5842000" cy="3128754"/><wp:effectExtent l="0" t="0" r="6350" b="0"/>' +
        "<wp:docPr id=`"$id`" name=`"Picture $imgN`"/>" +
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>' +
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">' +
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">' +
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">' +
        "<pic:nvPicPr><pic:cNvPr id=`"$id`" name=`"Picture $imgN`"/><pic:cNvPicPr/></pic:nvPicPr>" +
        "<pic:blipFill><a:blip r:embed=`"$rid`"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>" +
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="5842000" cy="3128754"/></a:xfrm>' +
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>'
}

$actions = @()
$ms = [regex]::Matches($xml, '<w:p\b[^>]*>.*?</w:p>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
foreach ($m in $ms) {
    $t = [regex]::Replace($m.Value, '<[^>]+>', '')
    $t = $t -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"'
    $t = $t.Trim()
    if ($t -match 'INSERT SCREENSHOT (\d) HERE') {
        $actions += [pscustomobject]@{ Index = $m.Index; Length = $m.Length; Type = 'image'; N = [int]$Matches[1] }
    }
    elseif ($t -match '^\(paste image:') {
        $actions += [pscustomobject]@{ Index = $m.Index; Length = $m.Length; Type = 'delete'; N = 0 }
    }
}

$imageActions = @($actions | Where-Object { $_.Type -eq 'image' } | Sort-Object N)
if ($imageActions.Count -ne 4) { throw "Expected 4 placeholders, found $($imageActions.Count)." }
$deleteActions = @($actions | Where-Object { $_.Type -eq 'delete' })
if ($deleteActions.Count -ne 4) { throw "Expected 4 paste-image lines, found $($deleteActions.Count)." }

$ridByN = @{}
for ($i = 0; $i -lt $imageActions.Count; $i++) {
    $ridByN[$imageActions[$i].N] = 'rId' + ($maxId + 1 + $i)
}

foreach ($a in ($actions | Sort-Object Index -Descending)) {
    if ($a.Type -eq 'delete') {
        $xml = $xml.Remove($a.Index, $a.Length)
    }
    else {
        $drawing = New-Drawing $a.N $ridByN[$a.N]
        $para = '<w:p><w:pPr><w:spacing w:before="60" w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="center"/></w:pPr><w:r>' + $drawing + '</w:r></w:p>'
        $xml = $xml.Substring(0, $a.Index) + $para + $xml.Substring($a.Index + $a.Length)
    }
}

[System.IO.File]::WriteAllText($docXmlPath, $xml, $UTF8)

foreach ($n in 1..4) {
    $rel = '<Relationship Id="' + $ridByN[$n] + '" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image' + $n + '.png"/>'
    $rels = $rels.Replace('</Relationships>', $rel + '</Relationships>')
}
[System.IO.File]::WriteAllText($relsPath, $rels, $UTF8)

if ($ct -notmatch 'Extension="png"') {
    $ct = $ct.Replace('</Types>', '<Default Extension="png" ContentType="image/png"/></Types>')
    [System.IO.File]::WriteAllText($ctPath, $ct, $UTF8)
}

$mediaDir = Join-Path $ex 'word\media'
New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null
for ($n = 1; $n -le 4; $n++) {
    $src = Join-Path $base ('0' + $n + '-*.png')
    $file = Get-ChildItem $src | Select-Object -First 1
    if (-not $file) { throw "Missing screenshot file for image $n" }
    Copy-Item $file.FullName (Join-Path $mediaDir ('image' + $n + '.png')) -Force
    Write-Output ("image{0}.png <- {1}" -f $n, $file.Name)
}

$out = Join-Path $work 'out.docx'
if (Test-Path $out) { Remove-Item $out -Force }
$zip = [System.IO.Compression.ZipFile]::Open($out, 'Create')
$files = Get-ChildItem $ex -Recurse -File
$ctFile = $files | Where-Object { $_.Name -eq '[Content_Types].xml' }
$others = $files | Where-Object { $_.Name -ne '[Content_Types].xml' }
foreach ($f in @($ctFile) + @($others)) {
    $name = $f.FullName.Substring($ex.Length + 1).Replace('\', '/')
    $entry = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
    $es = $entry.Open()
    $fs = [System.IO.File]::OpenRead($f.FullName)
    $fs.CopyTo($es)
    $fs.Close(); $es.Close()
}
$zip.Dispose()

Copy-Item $out $docx -Force
Write-Output "Inserted 4 screenshots ($($ridByN[1])..$($ridByN[4])) and saved $docx"
