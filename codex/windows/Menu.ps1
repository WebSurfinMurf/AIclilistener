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

# Function to show the Codex Client prompt dialog
function Show-CodexClientDialog {
    param([System.Windows.Forms.Form]$ParentForm)

    $clientPath = Join-Path $scriptDir "CodexClient.ps1"

    # Create child form
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Codex Client - Test Interface"
    $dialog.Size = New-Object System.Drawing.Size(700, 650)
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)

    # Info note at top
    $noteLabel = New-Object System.Windows.Forms.Label
    $noteLabel.Text = "This is a test interface for CodexClient.ps1. For interactive use, run 'codex' directly in your terminal for a better experience with full features."
    $noteLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $noteLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $noteLabel.Location = New-Object System.Drawing.Point(20, 12)
    $noteLabel.Size = New-Object System.Drawing.Size(645, 35)
    $dialog.Controls.Add($noteLabel)

    # Prompt label
    $promptLabel = New-Object System.Windows.Forms.Label
    $promptLabel.Text = "Enter your prompt:"
    $promptLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $promptLabel.Location = New-Object System.Drawing.Point(20, 55)
    $promptLabel.Size = New-Object System.Drawing.Size(200, 25)
    $dialog.Controls.Add($promptLabel)

    # Prompt text box (multiline)
    $promptBox = New-Object System.Windows.Forms.TextBox
    $promptBox.Multiline = $true
    $promptBox.ScrollBars = "Vertical"
    $promptBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $promptBox.Location = New-Object System.Drawing.Point(20, 85)
    $promptBox.Size = New-Object System.Drawing.Size(645, 100)
    $promptBox.AcceptsReturn = $true
    $dialog.Controls.Add($promptBox)

    # Send button
    $sendButton = New-Object System.Windows.Forms.Button
    $sendButton.Text = "Send"
    $sendButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $sendButton.Location = New-Object System.Drawing.Point(20, 195)
    $sendButton.Size = New-Object System.Drawing.Size(100, 35)
    $sendButton.BackColor = [System.Drawing.Color]::FromArgb(25, 118, 210)
    $sendButton.ForeColor = [System.Drawing.Color]::White
    $sendButton.FlatStyle = "Flat"
    $sendButton.FlatAppearance.BorderSize = 0
    $sendButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dialog.Controls.Add($sendButton)

    # Status label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Status: Ready"
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $statusLabel.Location = New-Object System.Drawing.Point(130, 202)
    $statusLabel.Size = New-Object System.Drawing.Size(400, 25)
    $dialog.Controls.Add($statusLabel)

    # Response label
    $responseLabel = New-Object System.Windows.Forms.Label
    $responseLabel.Text = "Response:"
    $responseLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $responseLabel.Location = New-Object System.Drawing.Point(20, 240)
    $responseLabel.Size = New-Object System.Drawing.Size(200, 25)
    $dialog.Controls.Add($responseLabel)

    # Response text box (multiline, read-only)
    $responseBox = New-Object System.Windows.Forms.TextBox
    $responseBox.Multiline = $true
    $responseBox.ScrollBars = "Both"
    $responseBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $responseBox.Location = New-Object System.Drawing.Point(20, 270)
    $responseBox.Size = New-Object System.Drawing.Size(645, 250)
    $responseBox.ReadOnly = $true
    $responseBox.BackColor = [System.Drawing.Color]::White
    $responseBox.WordWrap = $true
    $dialog.Controls.Add($responseBox)

    # Clear button
    $clearButton = New-Object System.Windows.Forms.Button
    $clearButton.Text = "Clear"
    $clearButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $clearButton.Location = New-Object System.Drawing.Point(20, 535)
    $clearButton.Size = New-Object System.Drawing.Size(100, 35)
    $clearButton.BackColor = [System.Drawing.Color]::FromArgb(255, 152, 0)
    $clearButton.ForeColor = [System.Drawing.Color]::White
    $clearButton.FlatStyle = "Flat"
    $clearButton.FlatAppearance.BorderSize = 0
    $clearButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dialog.Controls.Add($clearButton)

    # Exit button
    $exitDialogButton = New-Object System.Windows.Forms.Button
    $exitDialogButton.Text = "Close"
    $exitDialogButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $exitDialogButton.Location = New-Object System.Drawing.Point(565, 535)
    $exitDialogButton.Size = New-Object System.Drawing.Size(100, 35)
    $exitDialogButton.BackColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
    $exitDialogButton.ForeColor = [System.Drawing.Color]::White
    $exitDialogButton.FlatStyle = "Flat"
    $exitDialogButton.FlatAppearance.BorderSize = 0
    $exitDialogButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dialog.Controls.Add($exitDialogButton)

    # Clear button click
    $clearButton.Add_Click({
        $promptBox.Text = ""
        $responseBox.Text = ""
        $statusLabel.Text = "Status: Ready"
        $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
        $promptBox.Focus()
    })

    # Exit button click
    $exitDialogButton.Add_Click({
        $dialog.Close()
    })

    # Send button click
    $sendButton.Add_Click({
        $prompt = $promptBox.Text.Trim()

        if ([string]::IsNullOrEmpty($prompt)) {
            $statusLabel.Text = "Status: Please enter a prompt"
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 0, 0)
            return
        }

        # Disable send button during request
        $sendButton.Enabled = $false
        $responseBox.Text = ""

        # Update status
        $statusLabel.Text = "Status: Sending prompt..."
        $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(25, 118, 210)
        $dialog.Refresh()

        try {
            # Update status
            $statusLabel.Text = "Status: Waiting for response..."
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(156, 39, 176)
            $dialog.Refresh()

            # Save prompt to temp file to avoid quoting issues
            # Use WriteAllText to avoid BOM issues with UTF8
            $tempFile = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllText($tempFile, $prompt, [System.Text.UTF8Encoding]::new($false))

            # Call CodexClient.ps1 reading prompt from file
            $cmd = @"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
`$p = Get-Content -Path '$tempFile' -Raw -Encoding UTF8
& '$clientPath' -Prompt `$p -Raw
Remove-Item '$tempFile' -Force -ErrorAction SilentlyContinue
"@
            $output = & powershell -ExecutionPolicy Bypass -Command $cmd 2>&1

            # Parse response
            $responseText = ""
            $gotResponse = $false

            foreach ($line in $output) {
                $lineStr = $line.ToString()
                if ($lineStr -match '^\{') {
                    try {
                        $json = $lineStr | ConvertFrom-Json
                        if ($json.status -eq "success" -and $json.result.message) {
                            $responseText = $json.result.message
                            $gotResponse = $true
                        } elseif ($json.status -eq "error") {
                            $responseText = "ERROR: $($json.error)"
                            $gotResponse = $true
                        }
                    } catch {
                        # Not valid JSON
                    }
                }
            }

            if ($gotResponse) {
                # Clean up response - remove BOM and trim
                $cleanResponse = $responseText -replace '^\xEF\xBB\xBF', '' -replace '^\uFEFF', ''
                $responseBox.Text = $cleanResponse.Trim()
                $statusLabel.Text = "Status: Complete"
                $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            } else {
                # Show raw output if no JSON found
                $rawOutput = ($output | Out-String) -replace '^\xEF\xBB\xBF', '' -replace '^\uFEFF', ''
                $responseBox.Text = $rawOutput.Trim()
                $statusLabel.Text = "Status: Complete (raw output)"
                $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
            }

        } catch {
            $statusLabel.Text = "Status: Error - $($_.Exception.Message)"
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 0, 0)
            $responseBox.Text = $_.Exception.Message
        } finally {
            $sendButton.Enabled = $true
        }
    })

    # Show dialog as child of parent
    [void]$dialog.ShowDialog($ParentForm)
}

# Define scripts with descriptions
$scripts = @(
    @{
        Name = "CodexService.ps1"
        Description = "Start a Codex AI agent that accepts JSON requests via Named Pipe"
        SelectDirectory = $true
        Color = [System.Drawing.Color]::FromArgb(46, 125, 50)  # Green
    },
    @{
        Name = "demo.ps1"
        Description = "Interactive demo - test the service with a sample request"
        Color = [System.Drawing.Color]::FromArgb(25, 118, 210)  # Blue
    },
    @{
        Name = "CodexClient.ps1"
        Description = "Send a custom prompt to the Codex agent and view the response"
        PromptDialog = $true
        Color = [System.Drawing.Color]::FromArgb(25, 118, 210)  # Blue
    },
    @{
        Name = "Summarize-Files.ps1"
        Description = "Batch summarize files listed in a CSV using AI"
        Color = [System.Drawing.Color]::FromArgb(156, 39, 176)  # Purple
    },
    @{
        Name = "Install-Skill.ps1"
        Description = "Install the AIclilistener skill so Codex can use this service automatically"
        Color = [System.Drawing.Color]::FromArgb(255, 152, 0)  # Orange
    },
    @{
        Name = "Install-PdfToText.ps1"
        Description = "Install pdftotext (Poppler) to enable PDF text extraction"
        Color = [System.Drawing.Color]::FromArgb(255, 152, 0)  # Orange
    },
    @{
        Name = "Test-PdfExtract.ps1"
        Description = "Test PDF text extraction on a specific file"
        Color = [System.Drawing.Color]::FromArgb(121, 85, 72)  # Brown
    },
    @{
        Name = "Test-Pipe.ps1"
        Description = "Low-level Named Pipe connectivity test"
        Color = [System.Drawing.Color]::FromArgb(121, 85, 72)  # Brown
    }
)

# Create form (25% wider and 25% taller)
$form = New-Object System.Windows.Forms.Form
$form.Text = "AIclilistener Menu"
$form.Size = New-Object System.Drawing.Size(625, 675)
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

        if ($info.PromptDialog) {
            # Show the Codex Client prompt dialog
            Show-CodexClientDialog -ParentForm $form

        } elseif ($info.SelectDirectory) {
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

        } else {
            # Spawn script in new command prompt window (menu stays open)
            Start-Process cmd.exe -ArgumentList "/k", "powershell -ExecutionPolicy Bypass -File `"$path`" && echo. && echo Press Enter to close... && pause >nul"
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
