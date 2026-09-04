#Requires -Version 5.1
<#
    Local dev server for Kitty Hub -- the no-Python twin of localhost.py.

    Serves the built .lua files to your executor, and rebuilds them from src/ on
    demand so the edit -> re-execute loop is just "save, run again in Roblox".
    Windows already ships PowerShell, so this needs nothing installed.

        powershell -ExecutionPolicy Bypass -File localhost.ps1            # http://127.0.0.1:8000
        powershell -ExecutionPolicy Bypass -File localhost.ps1 8080       # different port
        powershell -ExecutionPolicy Bypass -File localhost.ps1 -Lan       # also reachable from your phone
        powershell -ExecutionPolicy Bypass -File localhost.ps1 -NoBuild   # serve files as-is, never rebuild
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateRange(1, 65535)]
    [int]$Port = 8000,

    [switch]$Lan,
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$SrcDir = Join-Path $Root 'src'
$SharedDir = Join-Path $SrcDir '_shared'
$AutoBuild = -not $NoBuild

$Titles = @{
    'mm2'       = 'Murder Mystery 2 Script'
    'jailbreak' = 'Jailbreak Script'
    'generic'   = 'Universal fallback module'
}

# Kept identical to build.py's BANNER so either builder produces the same file.
$Banner = (@'
-- ============================================================================
--
--   ██╗  ██╗██╗████████╗████████╗██╗   ██╗    ██╗  ██╗██╗   ██╗██████╗
--   ██║ ██╔╝██║╚══██╔══╝╚══██╔══╝╚██╗ ██╔╝    ██║  ██║██║   ██║██╔══██╗
--   █████╔╝ ██║   ██║      ██║    ╚████╔╝     ███████║██║   ██║██████╔╝
--   ██╔═██╗ ██║   ██║      ██║     ╚██╔╝      ██╔══██║██║   ██║██╔══██╗
--   ██║  ██╗██║   ██║      ██║      ██║       ██║  ██║╚██████╔╝██████╔╝
--   ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝      ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚═════╝
--
--   {title}
--   build {build}  ·  {stamp}
--
--   GENERATED FILE — do not edit directly.
--   Sources live in src/{module}/ ; rebuild with `python build.py`.
--
-- ============================================================================


'@) -replace "`r`n", "`n"


function Write-Note {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] " -ForegroundColor DarkGray -NoNewline
    Write-Host $Message -ForegroundColor $Color
}

function Read-LuaText([string]$Path) {
    # Universal newlines, the way Python's read_text sees them.
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return ($text -replace "`r`n", "`n") -replace "`r", "`n"
}


# --- build (a port of build.py, so this half needs no Python either) ---------

function Get-ModuleVersion($Files) {
    # Read the Version field out of the prelude so the banner cannot drift.
    foreach ($file in $Files) {
        foreach ($line in (Read-LuaText $file.FullName) -split "`n") {
            $stripped = $line.Trim()
            if ($stripped.StartsWith('Version') -and $stripped.Contains('=')) {
                return $stripped.Substring($stripped.IndexOf('=') + 1).Trim().Trim([char[]]@('"', ','))
            }
        }
    }
    return '0.0.0'
}

function Get-ModuleSources([string]$Name) {
    # Shared sources plus the module's own, ordered by their numeric prefix.
    $moduleDir = Join-Path $SrcDir $Name
    if (-not (Test-Path -LiteralPath $moduleDir -PathType Container)) { return @() }
    $own = @(Get-ChildItem -LiteralPath $moduleDir -Filter '*.lua' -File)
    $shared = @()
    if (Test-Path -LiteralPath $SharedDir -PathType Container) {
        $shared = @(Get-ChildItem -LiteralPath $SharedDir -Filter '*.lua' -File)
    }
    return @(($own + $shared) | Sort-Object Name)
}

function Build-Module([string]$Name) {
    $files = @(Get-ModuleSources $Name)
    if ($files.Count -eq 0) { throw "no .lua sources for module $Name" }

    $dash = [string][char]0x2500
    $parts = foreach ($file in $files) {
        $text = (Read-LuaText $file.FullName).TrimEnd()
        $label = "$($file.Directory.Name)/$($file.Name)"
        "-- $dash$dash$dash src/$label " +
        ($dash * [Math]::Max(0, 58 - $label.Length)) + "`n`n$text`n"
    }
    $body = $parts -join "`n"

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = [System.BitConverter]::ToString(
            $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($body))
        ).Replace('-', '').ToLowerInvariant().Substring(0, 8)
    } finally { $sha.Dispose() }

    $title = if ($Titles.ContainsKey($Name)) { $Titles[$Name] } else { $Name }
    $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    $header = $Banner.
        Replace('{title}', $title).
        Replace('{build}', "$(Get-ModuleVersion $files)+$digest").
        Replace('{stamp}', "$stamp UTC").
        Replace('{module}', $Name)

    # Python writes in text mode, so on Windows the shipped files come out CRLF.
    $content = $header + $body
    $out = Join-Path $Root "$Name.lua"
    [System.IO.File]::WriteAllText($out, ($content -replace "`n", "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

    $lines = $content.Split([char]10).Length
    $size = (Get-Item -LiteralPath $out).Length
    return ('  {0,-14} {1} sources -> {2} lines, {3:N0} bytes  [{4}]' -f "$Name.lua", $files.Count, $lines, $size, $digest)
}

function Test-StaleModule([string]$Name) {
    # True when src/<name>/ or src/_shared/ changed since <name>.lua was built.
    $moduleDir = Join-Path $SrcDir $Name
    $built = Join-Path $Root "$Name.lua"
    if (-not (Test-Path -LiteralPath $moduleDir -PathType Container)) { return $false }
    if (-not (Test-Path -LiteralPath $built -PathType Leaf)) { return $true }

    $newest = Get-ModuleSources $Name |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $newest) { return $false }
    return $newest.LastWriteTimeUtc -gt (Get-Item -LiteralPath $built).LastWriteTimeUtc
}


# --- serve -------------------------------------------------------------------

function Get-ContentType([string]$Path) {
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.lua'  { 'text/plain; charset=utf-8' }
        '.txt'  { 'text/plain; charset=utf-8' }
        '.md'   { 'text/plain; charset=utf-8' }
        '.html' { 'text/html; charset=utf-8' }
        '.js'   { 'text/javascript; charset=utf-8' }
        '.json' { 'application/json' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        default { 'application/octet-stream' }
    }
}

function Get-LanIP {
    # Best-effort local address, for pointing a phone at this server.
    try {
        $probe = New-Object System.Net.Sockets.Socket(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp)
        try {
            $probe.Connect('8.8.8.8', 80)
            return $probe.LocalEndPoint.Address.ToString()
        } finally { $probe.Dispose() }
    } catch { return '127.0.0.1' }
}

function Invoke-Client($Client) {
    $Client.ReceiveTimeout = 5000
    $Client.SendTimeout = 15000
    $stream = $Client.GetStream()
    $peer = $Client.Client.RemoteEndPoint.Address.ToString()

    $buffer = New-Object byte[] 4096
    $request = ''
    while (-not $request.Contains("`r`n`r`n") -and $request.Length -lt 16384) {
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { return }
        $request += [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
    }

    $requestLine = ($request -split "`r`n")[0]
    $fields = $requestLine -split ' '
    $method = $fields[0]
    $rawTarget = if ($fields.Count -gt 1) { $fields[1] } else { '/' }

    # Executors cache aggressively, and so do some proxies. The loader adds
    # a cache-buster too; between the two, a stale script is very unlikely.
    $respond = {
        param([int]$Status, [string]$Reason, [string]$Type, [byte[]]$Data)
        $head = "HTTP/1.1 $Status $Reason`r`n" +
                "Content-Type: $Type`r`n" +
                "Content-Length: $($Data.Length)`r`n" +
                "Cache-Control: no-store, no-cache, must-revalidate, max-age=0`r`n" +
                "Pragma: no-cache`r`n" +
                "Expires: 0`r`n" +
                "Access-Control-Allow-Origin: *`r`n" +
                "Connection: close`r`n`r`n"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($head)
        $stream.Write($bytes, 0, $bytes.Length)
        if ($method -ne 'HEAD' -and $Data.Length -gt 0) { $stream.Write($Data, 0, $Data.Length) }
        $stream.Flush()

        $color = if ($Status -ge 400) { 'Red' } elseif ($Status -eq 200) { 'Green' } else { 'Yellow' }
        Write-Note "$peer  ""$requestLine"" $Status" $color
    }
    $utf8 = { param([string]$Message) [System.Text.Encoding]::UTF8.GetBytes($Message) }

    if ($method -ne 'GET' -and $method -ne 'HEAD') {
        & $respond 501 'Not Implemented' 'text/plain; charset=utf-8' (& $utf8 "501 unsupported method`n")
        return
    }

    $requested = [System.Uri]::UnescapeDataString((($rawTarget -split '\?')[0]).TrimStart('/'))

    if ($AutoBuild -and $requested.EndsWith('.lua')) {
        $name = $requested.Substring(0, $requested.Length - 4)
        if (Test-StaleModule $name) {
            Write-Note "${name}: sources changed, rebuilding" 'Yellow'
            try {
                Write-Note (Build-Module $name) 'Green'
            } catch {
                Write-Note "  $($_.Exception.Message)" 'Red'
                & $respond 500 'Internal Server Error' 'text/plain; charset=utf-8' (& $utf8 "build failed`n")
                return
            }
        }
    }

    $rootFull = ([System.IO.Path]::GetFullPath($Root)).TrimEnd('\', '/')
    $path = if ($requested) { Join-Path $Root $requested } else { $Root }
    try { $path = [System.IO.Path]::GetFullPath($path) } catch { $path = '' }
    $inside = $path -and ($path.TrimEnd('\', '/') -eq $rootFull -or $path.StartsWith(
        $rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))

    if ($inside -and (Test-Path -LiteralPath $path -PathType Container)) {
        $index = Join-Path $path 'index.html'
        if (Test-Path -LiteralPath $index -PathType Leaf) {
            $path = $index
        } else {
            $base = if ($requested) { '/' + $requested.TrimEnd('/') + '/' } else { '/' }
            $rows = Get-ChildItem -LiteralPath $path | Sort-Object PSIsContainer, Name | ForEach-Object {
                $entry = $_.Name + $(if ($_.PSIsContainer) { '/' } else { '' })
                "<li><a href=""$base$entry"">$entry</a></li>"
            }
            $listing = "<!doctype html><meta charset=""utf-8""><title>$base</title><h1>$base</h1><ul>$($rows -join '')</ul>"
            & $respond 200 'OK' 'text/html; charset=utf-8' (& $utf8 $listing)
            return
        }
    }

    if (-not $inside -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        & $respond 404 'Not Found' 'text/plain; charset=utf-8' (& $utf8 "404 not found`n")
        return
    }

    & $respond 200 'OK' (Get-ContentType $path) ([System.IO.File]::ReadAllBytes($path))
}


# --- main --------------------------------------------------------------------

$bind = if ($Lan) { [System.Net.IPAddress]::Any } else { [System.Net.IPAddress]::Loopback }
$listener = New-Object System.Net.Sockets.TcpListener($bind, $Port)
try {
    $listener.Start()
} catch {
    Write-Host "Error: could not bind ${bind}:$Port - $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Another server may already be running on this port.' -ForegroundColor DarkGray
    exit 1
}

$urls = @("http://localhost:$Port")
if ($Lan) { $urls += "http://$(Get-LanIP):$Port" }

Write-Host ''
Write-Host '  Kitty Hub dev server' -ForegroundColor Cyan
Write-Host "  serving $Root" -ForegroundColor DarkGray
Write-Host "  auto-rebuild: $(if ($AutoBuild) { 'on' } else { 'off' })" -ForegroundColor DarkGray
Write-Host ''
foreach ($url in $urls) { Write-Host "  loadstring(game:HttpGet(""$url/kittyhub.lua""))()" }
Write-Host ''
Write-Host '  Ctrl+C to stop' -ForegroundColor DarkGray
Write-Host ''

try {
    while ($true) {
        if (-not $listener.Pending()) { Start-Sleep -Milliseconds 50; continue }
        $client = $listener.AcceptTcpClient()
        try { Invoke-Client $client }
        catch { Write-Note "  $($_.Exception.Message)" 'Red' }
        finally { $client.Close() }
    }
} finally {
    $listener.Stop()
    Write-Host ''
    Write-Host '  stopped' -ForegroundColor DarkGray
}
