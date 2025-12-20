<#
.SYNOPSIS
    AIclilistener Menu - Launch scripts with a GUI

.DESCRIPTION
    Windows Forms menu to launch all AIclilistener PowerShell scripts.
    CodexService.ps1 spawns in a new window so the menu stays available.

.EXAMPLE
    .\Menu.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Define scripts with descriptions
$scripts = @(
    @{
        Name = "CodexService.ps1"
        Description = "Start a Codex AI agent that accepts JSON requests via Named Pipe"
        NewWindow = $true
        SelectDirectory = $true
        Color = [System.Drawing.Color]::FromArgb(46, 125, 50)  # Green
    },
    @{
        Name = "demo.ps1"
        Description = "Interactive demo - test the service with a sample request"
        NewWindow = $false
        Color = [System.Drawing.Color]::FromArgb(25, 118, 210)  # Blue
    },
    @{
        Name = "CodexClient.ps1"
        Description = "Send a ping command to verify the service is running"
        NewWindow = $false
        Args = "-Command ping"
        Color = [System.Drawing.Color]::FromArgb(25, 118, 210)  # Blue
    },
    @{
        Name = "Summarize-Files.ps1"
        Description = "Batch summarize files listed in a CSV using AI"
        NewWindow = $false
        Color = [System.Drawing.Color]::FromArgb(156, 39, 176)  # Purple
    },
    @{
        Name = "Install-Skill.ps1"
        Description = "Install the AIclilistener skill so Codex can use this service automatically"
        NewWindow = $false
        Color = [System.Drawing.Color]::FromArgb(255, 152, 0)  # Orange
    },
    @{
        Name = "Install-PdfToText.ps1"
        Description = "Install pdftotext (Poppler) to enable PDF text extraction"
        NewWindow = $false
        Color = [System.Drawing.Color]::FromArgb(255, 152, 0)  # Orange
    },
    @{
        Name = "Test-PdfExtract.ps1"
        Description = "Test PDF text extraction on a specific file"
        NewWindow = $false
        Color = [System.Drawing.Color]::FromArgb(121, 85, 72)  # Brown
    },
    @{
        Name = "Test-Pipe.ps1"
        Description = "Low-level Named Pipe connectivity test"
        NewWindow = $false
        Color = [System.Drawing.Color]::FromArgb(121, 85, 72)  # Brown
    }
)

# Create form (25% wider: 500 -> 625)
$form = New-Object System.Windows.Forms.Form
$form.Text = "AIclilistener Menu"
$form.Size = New-Object System.Drawing.Size(625, 540)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)

# Title label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "AIclilistener - Codex CLI Service"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(33, 33, 33)
$titleLabel.Size = New-Object System.Drawing.Size(580, 35)
$titleLabel.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($titleLabel)

# Subtitle
$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "Select a script to run:"
$subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$subtitleLabel.Size = New-Object System.Drawing.Size(580, 20)
$subtitleLabel.Location = New-Object System.Drawing.Point(20, 50)
$form.Controls.Add($subtitleLabel)

# Create buttons for each script (25% wider: 450 -> 565)
$yPos = 85
$buttonHeight = 45
$buttonSpacing = 8
$buttonWidth = 565

foreach ($script in $scripts) {
    $scriptPath = Join-Path $scriptDir $script.Name

    # Skip if script doesn't exist
    if (-not (Test-Path $scriptPath)) {
        continue
    }

    # Create button
    $button = New-Object System.Windows.Forms.Button
    $button.Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
    $button.Location = New-Object System.Drawing.Point(20, $yPos)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $script.Color
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $button.TextAlign = "MiddleLeft"
    $button.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand

    # Button text with name and description
    $button.Text = "  $($script.Name)`n  $($script.Description)"

    # Store script info in Tag
    $button.Tag = $script

    # Click handler
    $button.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $path = Join-Path $scriptDir $info.Name

        if ($info.SelectDirectory) {
            # Special handling for CodexService - show explanation and folder picker
            $explanation = @"
Select a working directory for the Codex agent.

PERMISSIONS:
- The agent can WRITE to the selected folder and its subfolders
- The agent can READ files anywhere on your computer

This allows the agent to analyze files across your system while
restricting changes to your chosen project folder.

Click OK to select your working directory.
"@

            $result = [System.Windows.Forms.MessageBox]::Show(
                $explanation,
                "Codex Agent - Select Working Directory",
                [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
                return
            }

            # Show folder browser
            $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderBrowser.Description = "Select the directory where the Codex agent can write files"
            $folderBrowser.ShowNewFolderButton = $true

            # Try to set initial directory to common locations
            if (Test-Path "$env:USERPROFILE\Projects") {
                $folderBrowser.SelectedPath = "$env:USERPROFILE\Projects"
            } elseif (Test-Path "$env:USERPROFILE\Documents") {
                $folderBrowser.SelectedPath = "$env:USERPROFILE\Documents"
            }

            $folderResult = $folderBrowser.ShowDialog()

            if ($folderResult -ne [System.Windows.Forms.DialogResult]::OK) {
                return
            }

            $selectedDir = $folderBrowser.SelectedPath

            # Spawn CodexService in new window at selected directory
            Start-Process cmd.exe -ArgumentList "/k", "cd /d `"$selectedDir`" && powershell -ExecutionPolicy Bypass -File `"$path`""

        } elseif ($info.NewWindow) {
            # Spawn in new command prompt window
            Start-Process cmd.exe -ArgumentList "/k", "powershell", "-ExecutionPolicy", "Bypass", "-File", "`"$path`""
        } else {
            # Run in current context but hide menu temporarily
            $form.WindowState = "Minimized"

            try {
                if ($info.Args) {
                    & powershell -ExecutionPolicy Bypass -File $path $info.Args
                } else {
                    & powershell -ExecutionPolicy Bypass -File $path
                }
            } finally {
                $form.WindowState = "Normal"
                $form.Activate()
            }

            # Pause so user can see output
            Write-Host ""
            Write-Host "Press Enter to return to menu..." -ForegroundColor Cyan
            Read-Host
        }
    })

    # Hover effects - lighten color manually
    $button.Add_MouseEnter({
        param($sender, $e)
        $c = $sender.BackColor
        $sender.BackColor = [System.Drawing.Color]::FromArgb(
            [Math]::Min(255, $c.R + 30),
            [Math]::Min(255, $c.G + 30),
            [Math]::Min(255, $c.B + 30)
        )
    })

    $button.Add_MouseLeave({
        param($sender, $e)
        $sender.BackColor = $sender.Tag.Color
    })

    $form.Controls.Add($button)
    $yPos += $buttonHeight + $buttonSpacing
}

# Exit button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Size = New-Object System.Drawing.Size($buttonWidth, 35)
$exitButton.Location = New-Object System.Drawing.Point(20, ($yPos + 10))
$exitButton.FlatStyle = "Flat"
$exitButton.FlatAppearance.BorderSize = 1
$exitButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$exitButton.BackColor = [System.Drawing.Color]::White
$exitButton.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$exitButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$exitButton.Text = "Exit"
$exitButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$exitButton.Add_Click({ $form.Close() })
$form.Controls.Add($exitButton)

# Show form
[void]$form.ShowDialog()
