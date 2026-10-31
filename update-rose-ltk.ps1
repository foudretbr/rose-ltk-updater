# ==============================================================================
# Rose LTK Patcher Auto-Updater
# Automatically updates ltk_patcher_dll.dll and ltk_patcher_host.exe in Rose
# ==============================================================================
[CmdletBinding()]
param (
    [string]$RosePath = "",
    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Rose LTK Patcher Updater"

# 1. Require Administrator Privileges (needed for Program Files modifications)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] Requesting Administrator privileges..." -ForegroundColor Yellow
    $scriptArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Force) { $scriptArgs += " -Force" }
    if ($RosePath) { $scriptArgs += " -RosePath `"$RosePath`"" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $scriptArgs
    exit
}

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "             Rose LTK Patcher Auto-Updater            " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# 2. Locate Rose Tools Directory
$roseToolsDir = $RosePath
if (-not $roseToolsDir) {
    $searchPaths = @(
        "C:\Program Files\Rose\_internal\injection\tools",
        "C:\Program Files (x86)\Rose\_internal\injection\tools",
        "$env:LOCALAPPDATA\Programs\Rose\_internal\injection\tools",
        "$env:LOCALAPPDATA\Rose\_internal\injection\tools"
    )
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $roseToolsDir = $path
            break
        }
    }
}

if (-not $roseToolsDir -or -not (Test-Path $roseToolsDir)) {
    Write-Host "[-] Could not locate Rose installation folder." -ForegroundColor Red
    Write-Host "    Expected path: C:\Program Files\Rose\_internal\injection\tools" -ForegroundColor Red
    Write-Host "    You can specify custom path using: .\update-rose-ltk.ps1 -RosePath `"C:\path\to\tools`"" -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit..."
    exit 1
}

Write-Host "[+] Found Rose tools directory:" -ForegroundColor Green
Write-Host "    $roseToolsDir" -ForegroundColor Gray
Write-Host ""

# 3. Locate 7-Zip
$7z = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
if (-not $7z) {
    $candidates = @(
        "$env:USERPROFILE\scoop\shims\7z.exe",
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) { $7z = $cand; break }
    }
}

if (-not $7z) {
    Write-Host "[-] 7-Zip executable was not found." -ForegroundColor Red
    Write-Host "    Please install 7-Zip (e.g. 'winget install 7zip.7zip' or 'scoop install 7zip')." -ForegroundColor Yellow
    Read-Host "`nPress Enter to exit..."
    exit 1
}

# 4. Fetch the latest release from GitHub (LeagueToolkit/ltk-manager)
Write-Host "[*] Checking latest LTK Manager release on GitHub..." -ForegroundColor Yellow
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/LeagueToolkit/ltk-manager/releases/latest" -Headers @{ "User-Agent" = "Rose-LTK-Updater" }
    $latestTag = $release.tag_name
    Write-Host "[+] Latest version available on GitHub: $latestTag" -ForegroundColor Green
} catch {
    Write-Host "[-] Failed to contact GitHub API: $_" -ForegroundColor Red
    Read-Host "`nPress Enter to exit..."
    exit 1
}

# Check currently installed version
$versionFile = Join-Path $roseToolsDir "ltk_version.txt"
$currentVersion = ""
if (Test-Path $versionFile) {
    $currentVersion = (Get-Content $versionFile -Raw).Trim()
    Write-Host "[*] Currently installed version: $currentVersion" -ForegroundColor Gray
}

if ($currentVersion -eq $latestTag -and -not $Force) {
    Write-Host ""
    Write-Host "[!] Rose already has the latest version ($latestTag) installed." -ForegroundColor Green
    $choice = Read-Host "Do you want to force reinstall anyway? (Y/N)"
    if ($choice -notmatch "^[yYoO]") {
        Write-Host "Update skipped." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        exit 0
    }
}

# Find setup asset
$asset = $release.assets | Where-Object { $_.name -match "setup\.exe$" -and $_.name -notmatch "\.sig$" } | Select-Object -First 1
if (-not $asset) {
    Write-Host "[-] No setup binary found in release $latestTag." -ForegroundColor Red
    Read-Host "`nPress Enter to exit..."
    exit 1
}

$downloadUrl = $asset.browser_download_url
$tempDir = Join-Path $env:TEMP "rose_ltk_update"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$setupPath = Join-Path $tempDir $asset.name

# 5. Download the installer
Write-Host "[*] Downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 2)) MB)..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $downloadUrl -OutFile $setupPath

# 6. Extract patcher binaries using 7-Zip
Write-Host "[*] Extracting ltk_patcher_dll.dll and ltk_patcher_host.exe..." -ForegroundColor Yellow
$extractedDir = Join-Path $tempDir "extracted"
& $7z e -y "-o$extractedDir" "$setupPath" "ltk_patcher_dll.dll" "ltk_patcher_host.exe" | Out-Null

$newDll = Join-Path $extractedDir "ltk_patcher_dll.dll"
$newHost = Join-Path $extractedDir "ltk_patcher_host.exe"

if (-not (Test-Path $newDll) -or -not (Test-Path $newHost)) {
    Write-Host "[-] Failed to extract required patcher files from the archive." -ForegroundColor Red
    Read-Host "`nPress Enter to exit..."
    exit 1
}

# 7. Backup and update files in Rose
Write-Host "[*] Installing updated binaries into Rose..." -ForegroundColor Yellow

$targetDll = Join-Path $roseToolsDir "ltk_patcher_dll.dll"
$targetHost = Join-Path $roseToolsDir "ltk_patcher_host.exe"

if (Test-Path $targetDll) {
    Copy-Item $targetDll (Join-Path $roseToolsDir "ltk_patcher_dll.dll.bak") -Force
}
if (Test-Path $targetHost) {
    Copy-Item $targetHost (Join-Path $roseToolsDir "ltk_patcher_host.exe.bak") -Force
}

Copy-Item $newDll $targetDll -Force
Copy-Item $newHost $targetHost -Force

# Save version file
Set-Content -Path $versionFile -Value $latestTag -Force

# 8. Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "      Successfully updated Rose LTK to $latestTag!    " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host "[+] Updated ltk_patcher_dll.dll" -ForegroundColor Green
Write-Host "[+] Updated ltk_patcher_host.exe" -ForegroundColor Green
Write-Host "[+] Created .bak backup files" -ForegroundColor Gray

if (Get-Process -Name "*rose*" -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "[!] Note: Rose is currently running. Please restart Rose for the changes to take effect." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to exit..."
