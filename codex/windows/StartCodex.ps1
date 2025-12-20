<#
.SYNOPSIS
    Launch Codex CLI with directory picker and configured permissions

.DESCRIPTION
    Shows a directory picker dialog, then launches Codex CLI with:
    - Full disk read access
    - Write access to the selected folder

.EXAMPLE
    .\StartCodex.ps1
#>

Add-Type -AssemblyName System.Windows.Forms

$explanation = @"
Select a working directory for Codex.

PERMISSIONS:
- Codex can WRITE to the selected folder and its subfolders
- Codex can READ files anywhere on your computer

This allows Codex to analyze files across your system while
restricting changes to your chosen project folder.

Click OK to select your working directory.
"@

$result = [System.Windows.Forms.MessageBox]::Show(
    $explanation,
    "Start Codex - Select Working Directory",
    [System.Windows.Forms.MessageBoxButtons]::OKCancel,
    [System.Windows.Forms.MessageBoxIcon]::Information
)

if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    exit 0
}

$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select the directory where Codex can write files"
$folderBrowser.ShowNewFolderButton = $true

if (Test-Path "$env:USERPROFILE\Projects") {
    $folderBrowser.SelectedPath = "$env:USERPROFILE\Projects"
} elseif (Test-Path "$env:USERPROFILE\Documents") {
    $folderBrowser.SelectedPath = "$env:USERPROFILE\Documents"
}

$folderResult = $folderBrowser.ShowDialog()

if ($folderResult -ne [System.Windows.Forms.DialogResult]::OK) {
    exit 0
}

$selectedDir = $folderBrowser.SelectedPath

# Change to selected directory and launch codex
Set-Location $selectedDir
Write-Host "Starting Codex in: $selectedDir" -ForegroundColor Cyan
Write-Host "Permissions: Full disk read, write to this folder" -ForegroundColor Gray
Write-Host ""

# Launch codex with full disk read and folder write access
& codex --full-auto --sandbox-permissions="disk-full-read-access"
