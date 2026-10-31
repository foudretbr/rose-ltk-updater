# ==============================================================================
# Rose LTK Patcher Auto-Updater
# Automatically updates ltk_patcher_dll.dll and ltk_patcher_host.exe in Rose
# Repository: https://github.com/foudretbr/rose-ltk-updater
# ==============================================================================
[CmdletBinding()]
param (
    [string]$RosePath = "",
    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Rose LTK Patcher Auto-Updater"

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

# 2. Automatically locate Rose Installation Directory
$roseToolsDir = $RosePath

if (-not $roseToolsDir) {
    # Method A: Check Windows Registry (finds custom installation drives/paths)
    try {
        $regEntries = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                      "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName -match "^Rose(\s|$)" }

        foreach ($entry in $regEntries) {
            $base = ""
            if ($entry.InstallLocation -and (Test-Path $entry.InstallLocation)) {
                $base = $entry.InstallLocation
            } elseif ($entry.UninstallString) {
                $cleanUninst = $entry.UninstallString.Trim().Trim('"')
                $dirCandidate = Split-Path $cleanUninst
                if (Test-Path $dirCandidate) { $base = $dirCandidate }
            }

            if ($base) {
                $candidate = Join-Path $base "_internal\injection\tools"
                if (Test-Path $candidate) {
                    $roseToolsDir = $candidate
                    break
                }
            }
        }
    } catch {}

    # Method B: Standard drive and environment paths fallback
    if (-not $roseToolsDir) {
        $commonPaths = @(
            (Join-Path $env:ProgramFiles "Rose\_internal\injection\tools"),
            (Join-Path ${env:ProgramFiles(x86)} "Rose\_internal\injection\tools"),
            (Join-Path $env:LOCALAPPDATA "Programs\Rose\_internal\injection\tools"),
            (Join-Path $env:LOCALAPPDATA "Rose\_internal\injection\tools"),
            "C:\Program Files\Rose\_internal\injection\tools",
            "D:\Program Files\Rose\_internal\injection\tools",
            "D:\Rose\_internal\injection\tools"
        )
        foreach ($path in $commonPaths) {
            if ($path -and (Test-Path $path)) {
                $roseToolsDir = $path
                break
            }
        }
    }
}

if (-not $roseToolsDir -or -not (Test-Path $roseToolsDir)) {
    Write-Host "[-] Could not automatically find your Rose installation directory." -ForegroundColor Red
    Write-Host "    Expected subfolder: _internal\injection\tools" -ForegroundColor Red
    Write-Host ""
    Write-Host "    You can run the script specifying your custom path:" -ForegroundColor Yellow
    Write-Host "    .\update-rose-ltk.ps1 -RosePath `"D:\Games\Rose\_internal\injection\tools`"" -ForegroundColor Gray
    Read-Host "`nPress Enter to exit..."
    exit 1
}

Write-Host "[+] Found Rose tools directory:" -ForegroundColor Green
Write-Host "    $roseToolsDir" -ForegroundColor Gray
Write-Host ""

# 3. Locate 7-Zip (or offer automatic installation via winget)
$7z = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
if (-not $7z) {
    $search7z = @(
        (Join-Path $env:ProgramFiles "7-Zip\7z.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "7-Zip\7z.exe"),
        (Join-Path $env:USERPROFILE "scoop\shims\7z.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\7-Zip\7z.exe")
    )
    foreach ($cand in $search7z) {
        if ($cand -and (Test-Path $cand)) { $7z = $cand; break }
    }
}

if (-not $7z) {
    Write-Host "[!] 7-Zip was not found on this computer." -ForegroundColor Yellow
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        $install7z = Read-Host "Would you like to automatically install 7-Zip via winget? (Y/N)"
        if ($install7z -match "^[yYoO]") {
            Write-Host "[*] Installing 7-Zip..." -ForegroundColor Yellow
            Start-Process -FilePath "winget" -ArgumentList "install --id 7zip.7zip -e --source winget --accept-source-agreements --accept-package-agreements --silent" -Wait -NoNewWindow
            $candidate = Join-Path $env:ProgramFiles "7-Zip\7z.exe"
            if (Test-Path $candidate) { $7z = $candidate }
        }
    }

    if (-not $7z) {
        Write-Host "[-] 7-Zip is required to unpack the patcher binaries." -ForegroundColor Red
        Write-Host "    Download and install it from https://www.7-zip.org/ and rerun this updater." -ForegroundColor Yellow
        Read-Host "`nPress Enter to exit..."
        exit 1
    }
}

# 4. Fetch the latest release from GitHub
Write-Host "[*] Checking latest LTK Manager release on GitHub..." -ForegroundColor Yellow
$latestTag = ""
$downloadUrl = ""
$assetName = "LTK.Manager_x64-setup.exe"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/LeagueToolkit/ltk-manager/releases/latest" -Headers @{ "User-Agent" = "Rose-LTK-Updater" }
    $latestTag = $release.tag_name

    $asset = $release.assets | Where-Object { $_.name -match "setup\.exe$" -and $_.name -notmatch "\.sig$" } | Select-Object -First 1
    if ($asset) {
        $downloadUrl = $asset.browser_download_url
        $assetName = $asset.name
    }
    Write-Host "[+] Latest version available on GitHub: $latestTag" -ForegroundColor Green
} catch {
    Write-Host "[!] Could not fetch release details from GitHub API (might be rate-limited)." -ForegroundColor Gray
    Write-Host "[*] Using direct fallback download link..." -ForegroundColor Yellow
    $downloadUrl = "https://github.com/LeagueToolkit/ltk-manager/releases/latest/download/LTK.Manager_x64-setup.exe"
    $latestTag = "latest"
}

# Check currently installed version
$versionFile = Join-Path $roseToolsDir "ltk_version.txt"
$currentVersion = ""
if (Test-Path $versionFile) {
    $currentVersion = (Get-Content $versionFile -Raw).Trim()
    Write-Host "[*] Currently installed version: $currentVersion" -ForegroundColor Gray
}

if ($latestTag -ne "latest" -and $currentVersion -eq $latestTag -and -not $Force) {
    Write-Host ""
    Write-Host "[!] Rose already has the latest version ($latestTag) installed." -ForegroundColor Green
    $choice = Read-Host "Do you want to force reinstall anyway? (Y/N)"
    if ($choice -notmatch "^[yYoO]") {
        Write-Host "Update skipped." -ForegroundColor Gray
        Start-Sleep -Seconds 2
        exit 0
    }
}

$tempDir = Join-Path $env:TEMP "rose_ltk_update"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$setupPath = Join-Path $tempDir $assetName

# 5. Download the installer
Write-Host "[*] Downloading installer..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $setupPath
} catch {
    Write-Host "[-] Failed to download installer from: $downloadUrl" -ForegroundColor Red
    Write-Host "    Error: $_" -ForegroundColor Red
    Read-Host "`nPress Enter to exit..."
    exit 1
}

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
Write-Host "            Rose LTK Successfully Updated!            " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host "[+] Updated: ltk_patcher_dll.dll" -ForegroundColor Green
Write-Host "[+] Updated: ltk_patcher_host.exe" -ForegroundColor Green
Write-Host "[+] Created: .bak backup files" -ForegroundColor Gray

if (Get-Process -Name "*rose*" -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "[!] Note: Rose is currently running. Please restart Rose for the changes to take effect." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to exit..."
