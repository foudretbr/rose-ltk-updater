# Rose LTK Patcher Auto-Updater

A lightweight, automated updater script for **Rose** skin manager that keeps `ltk_patcher_dll.dll` and `ltk_patcher_host.exe` up-to-date with the latest official [LeagueToolkit (LTK Manager)](https://github.com/LeagueToolkit/ltk-manager) releases.

---

## 💡 Why this tool?

Due to redistribution policies, third-party modding tools like **Rose** cannot always bundle the latest League Toolkit patcher binaries. When League of Legends updates, custom skin injections may break until the LTK patcher binaries are refreshed.

This tool completely automates the process:
1. Queries the GitHub API for the latest official LTK Manager release.
2. Checks whether your local Rose installation is already up-to-date.
3. Automatically downloads the setup file and extracts `ltk_patcher_dll.dll` and `ltk_patcher_host.exe` using 7-Zip without installing the full LTK application.
4. Backs up existing files (`.bak`) in case you need to revert.
5. Injects the updated binaries directly into your Rose directory (`C:\Program Files\Rose\_internal\injection\tools`).

---

## 📋 Requirements

- **Windows 10 / 11**
- **PowerShell 5.1+** (included with Windows)
- **[7-Zip](https://www.7-zip.org/)** (installed via installer, winget, or scoop)
  ```powershell
  winget install 7zip.7zip
  # or
  scoop install 7zip
  ```

---

## 🚀 Usage

### Option 1: Double-Click (Easiest)
Simply double-click:
```text
update-rose-ltk.cmd
```
Accept the standard Windows UAC prompt (Administrator permission is required because Rose is located in `C:\Program Files`).

### Option 2: PowerShell
Run the script from an elevated or standard PowerShell console:
```powershell
.\update-rose-ltk.ps1
```
*(The script will automatically self-elevate if not run as Administrator).*

#### Optional Parameters:
- `-Force`: Reinstall or overwrite even if already on the latest version.
- `-RosePath "C:\custom\path\to\injection\tools"`: Specify a custom Rose tools directory.

```powershell
.\update-rose-ltk.ps1 -Force
```

---

## 📁 Default Target Paths
The script checks the following standard paths for Rose:
- `C:\Program Files\Rose\_internal\injection\tools`
- `C:\Program Files (x86)\Rose\_internal\injection\tools`
- `%LOCALAPPDATA%\Programs\Rose\_internal\injection\tools`

---

## 🛠️ Created Backups
Before overwriting any files, the script preserves your previous version:
- `ltk_patcher_dll.dll.bak`
- `ltk_patcher_host.exe.bak`

---

## 📄 License
MIT License. See [LICENSE](LICENSE) for details.
