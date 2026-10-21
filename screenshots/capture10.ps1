$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSCommandPath

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Cap10 {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[Win32Cap10]::SetProcessDPIAware() | Out-Null

$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

function Capture-Page {
    param([string]$Url, [string]$OutFile, [int]$WaitMs = 7000)

    $profile = Join-Path $env:TEMP ('ass10-edge-' + [guid]::NewGuid().ToString('N'))
    $before = @(Get-Process msedge -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
        ForEach-Object { $_.Id })

    $proc = Start-Process -FilePath $edge -ArgumentList `
        '--new-window', '--no-first-run', '--no-default-browser-check', '--disable-sync',
        '--disable-features=msEdgeIdentitySyncPromo,msEdgeSidebarV2',
        "--user-data-dir=$profile", $Url -PassThru

    $winProc = $null
    for ($i = 0; $i -lt 150; $i++) {
        Start-Sleep -Milliseconds 300
        $cand = @(Get-Process msedge -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -ne [IntPtr]::Zero -and ($before -notcontains $_.Id)
        })
        if ($cand) { $winProc = $cand | Sort-Object StartTime | Select-Object -Last 1; break }
    }
    if (-not $winProc) { throw "Could not find browser window for $Url" }

    $handle = $winProc.MainWindowHandle
    [Win32Cap10]::ShowWindow($handle, 3) | Out-Null
    [Win32Cap10]::SetForegroundWindow($handle) | Out-Null
    Start-Sleep -Milliseconds $WaitMs
    try { [System.Windows.Forms.SendKeys]::SendWait('{ESC}') } catch { }
    Start-Sleep -Milliseconds 600

    $rect = New-Object Win32Cap10+RECT
    [Win32Cap10]::GetWindowRect($handle, [ref]$rect) | Out-Null
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Output "Captured: $OutFile ($width x $height)"

    Stop-Process -Id $winProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*$profile*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item $profile -Recurse -Force -ErrorAction SilentlyContinue
}

$targets = 'http://localhost:9090/targets'
$alerts  = 'http://localhost:9090/alerts'
$dashboard = 'http://localhost:3000/d/devops-monitoring/devops-system-monitoring?orgId=1&from=now-15m&to=now'
$promql = '100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
$graph = 'http://localhost:9090/graph?g0.expr=' + [uri]::EscapeDataString($promql) + '&g0.tab=1'

Capture-Page -Url $targets   -OutFile (Join-Path $base '01-targets.png')   -WaitMs 8000
Capture-Page -Url $graph     -OutFile (Join-Path $base '03-promql.png')     -WaitMs 8000
Capture-Page -Url $alerts    -OutFile (Join-Path $base '04-alerts.png')     -WaitMs 8000
Capture-Page -Url $dashboard -OutFile (Join-Path $base '02-dashboard.png')  -WaitMs 14000

Write-Output 'All captures finished.'
