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

# Function to show PDF text extraction dialog
function Show-PdfExtractDialog {
    param([System.Windows.Forms.Form]$ParentForm)

    # Show file picker for PDF
    $openDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openDialog.Title = "Select a PDF file to extract text from"
    $openDialog.Filter = "PDF files (*.pdf)|*.pdf|All files (*.*)|*.*"
    $openDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')

    $result = $openDialog.ShowDialog($ParentForm)
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $pdfPath = $openDialog.FileName

    # Create viewer dialog
    $viewer = New-Object System.Windows.Forms.Form
    $viewer.Text = "PDF Text Extraction - $(Split-Path $pdfPath -Leaf)"
    $viewer.Size = New-Object System.Drawing.Size(800, 600)
    $viewer.StartPosition = "CenterParent"
    $viewer.FormBorderStyle = "Sizable"
    $viewer.MinimumSize = New-Object System.Drawing.Size(400, 300)
    $viewer.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)

    # Status label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Extracting text from: $pdfPath"
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $statusLabel.Location = New-Object System.Drawing.Point(20, 15)
    $statusLabel.Size = New-Object System.Drawing.Size(740, 20)
    $statusLabel.Anchor = "Top,Left,Right"
    $viewer.Controls.Add($statusLabel)

    # Text box for extracted text
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = "Both"
    $textBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $textBox.Location = New-Object System.Drawing.Point(20, 45)
    $textBox.Size = New-Object System.Drawing.Size(745, 450)
    $textBox.ReadOnly = $true
    $textBox.BackColor = [System.Drawing.Color]::White
    $textBox.WordWrap = $false
    $textBox.Anchor = "Top,Bottom,Left,Right"
    $viewer.Controls.Add($textBox)

    # Close button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Close"
    $closeButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $closeButton.Size = New-Object System.Drawing.Size(100, 35)
    $closeButton.Location = New-Object System.Drawing.Point(665, 510)
    $closeButton.BackColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
    $closeButton.ForeColor = [System.Drawing.Color]::White
    $closeButton.FlatStyle = "Flat"
    $closeButton.FlatAppearance.BorderSize = 0
    $closeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $closeButton.Anchor = "Bottom,Right"
    $closeButton.Add_Click({ $viewer.Close() })
    $viewer.Controls.Add($closeButton)

    # Extract text using Test-PdfExtract.ps1 logic
    $testScript = Join-Path $scriptDir "Test-PdfExtract.ps1"
    $libPath = Join-Path $scriptDir "lib\Get-FileText.ps1"

    $viewer.Add_Shown({
        $viewer.Refresh()

        try {
            # Try to use Get-FileText if available
            if (Test-Path $libPath) {
                . $libPath
                $text = Get-FileText -FilePath $pdfPath -MaxChars 100000
                if ($text) {
                    $textBox.Text = $text
                    $statusLabel.Text = "Extracted $($text.Length) characters from: $(Split-Path $pdfPath -Leaf)"
                    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
                } else {
                    $textBox.Text = "[No text extracted - PDF may be scanned images or empty]"
                    $statusLabel.Text = "No text found in PDF"
                    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 100, 0)
                }
            } else {
                # Fallback - try pdftotext directly
                $configPath = Join-Path $scriptDir ".pdftotext-path"
                $pdftotextPath = $null

                if (Test-Path $configPath) {
                    $pdftotextPath = Get-Content $configPath -Raw
                    $pdftotextPath = $pdftotextPath.Trim()
                }

                if (-not $pdftotextPath -or -not (Test-Path $pdftotextPath)) {
                    $pdftotextPath = Get-Command pdftotext -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
                }

                if ($pdftotextPath -and (Test-Path $pdftotextPath)) {
                    $tempOut = [System.IO.Path]::GetTempFileName()
                    & $pdftotextPath -layout $pdfPath $tempOut 2>$null
                    if (Test-Path $tempOut) {
                        $text = Get-Content $tempOut -Raw -Encoding UTF8
                        Remove-Item $tempOut -Force
                        if ($text -and $text.Trim()) {
                            $textBox.Text = $text
                            $statusLabel.Text = "Extracted $($text.Length) characters"
                            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
                        } else {
                            $textBox.Text = "[No text extracted - PDF may be scanned images]"
                            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 100, 0)
                        }
                    }
                } else {
                    $textBox.Text = "[pdftotext not installed - run Install-PdfToText.ps1 first]"
                    $statusLabel.Text = "pdftotext not found"
                    $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 0, 0)
                }
            }
        } catch {
            $textBox.Text = "[Error extracting text: $($_.Exception.Message)]"
            $statusLabel.Text = "Error during extraction"
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 0, 0)
        }
    })

    [void]$viewer.ShowDialog($ParentForm)
}

# Function to show Setup sub-menu
function Show-SetupMenu {
    param([System.Windows.Forms.Form]$ParentForm)

    $setupDialog = New-Object System.Windows.Forms.Form
    $setupDialog.Text = "Setup & Testing"
    $setupDialog.Size = New-Object System.Drawing.Size(500, 350)
    $setupDialog.StartPosition = "CenterParent"
    $setupDialog.FormBorderStyle = "FixedDialog"
    $setupDialog.MaximizeBox = $false
    $setupDialog.MinimizeBox = $false
    $setupDialog.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)

    # Title
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Setup & Testing Tools"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(33, 33, 33)
    $titleLabel.Location = New-Object System.Drawing.Point(20, 15)
    $titleLabel.Size = New-Object System.Drawing.Size(440, 30)
    $setupDialog.Controls.Add($titleLabel)

    $yPos = 55
    $btnHeight = 40
    $btnSpacing = 8
    $btnWidth = 440

    # Setup items
    $setupItems = @(
        @{
            Name = "Install-Skill.ps1"
            Label = "Install Skill"
            Description = "Install the AIclilistener skill for Codex"
            Color = [System.Drawing.Color]::FromArgb(255, 152, 0)
        },
        @{
            Name = "Install-PdfToText.ps1"
            Label = "Install PdfToText"
            Description = "Install pdftotext (Poppler) for PDF support"
            Color = [System.Drawing.Color]::FromArgb(255, 152, 0)
        },
        @{
            Name = "Test-PdfExtract"
            Label = "Test PDF Extraction"
            Description = "Select a PDF and view extracted text"
            Color = [System.Drawing.Color]::FromArgb(121, 85, 72)
            PdfViewer = $true
        },
        @{
            Name = "demo.ps1"
            Label = "Run Demo"
            Description = "Interactive demo - test the service with a sample request"
            Color = [System.Drawing.Color]::FromArgb(25, 118, 210)
        }
    )

    foreach ($item in $setupItems) {
        $btn = New-Object System.Windows.Forms.Button
        $btn.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
        $btn.Location = New-Object System.Drawing.Point(20, $yPos)
        $btn.FlatStyle = "Flat"
        $btn.FlatAppearance.BorderSize = 0
        $btn.BackColor = $item.Color
        $btn.ForeColor = [System.Drawing.Color]::White
        $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $btn.TextAlign = "MiddleLeft"
        $btn.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
        $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btn.Text = "  $($item.Label)`n  $($item.Description)"
        $btn.Tag = $item

        $btn.Add_Click({
            param($sender, $e)
            $info = $sender.Tag

            if ($info.PdfViewer) {
                Show-PdfExtractDialog -ParentForm $setupDialog
            } else {
                $path = Join-Path $scriptDir $info.Name
                if (Test-Path $path) {
                    Start-Process cmd.exe -ArgumentList "/k", "powershell -ExecutionPolicy Bypass -File `"$path`" && echo. && echo Press Enter to close... && pause >nul"
                }
            }
        })

        # Hover effects
        $btn.Add_MouseEnter({
            param($sender, $e)
            $c = $sender.BackColor
            $sender.BackColor = [System.Drawing.Color]::FromArgb(
                [Math]::Min(255, $c.R + 30),
                [Math]::Min(255, $c.G + 30),
                [Math]::Min(255, $c.B + 30)
            )
        })
        $btn.Add_MouseLeave({
            param($sender, $e)
            $sender.BackColor = $sender.Tag.Color
        })

        $setupDialog.Controls.Add($btn)
        $yPos += $btnHeight + $btnSpacing
    }

    # Close button
    $closeBtn = New-Object System.Windows.Forms.Button
    $closeBtn.Text = "Close"
    $closeBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $closeBtn.Size = New-Object System.Drawing.Size($btnWidth, 30)
    $closeBtn.Location = New-Object System.Drawing.Point(20, ($yPos + 10))
    $closeBtn.FlatStyle = "Flat"
    $closeBtn.FlatAppearance.BorderSize = 1
    $closeBtn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $closeBtn.BackColor = [System.Drawing.Color]::White
    $closeBtn.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $closeBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $closeBtn.Add_Click({ $setupDialog.Close() })
    $setupDialog.Controls.Add($closeBtn)

    [void]$setupDialog.ShowDialog($ParentForm)
}

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

# Main scripts (excluding setup items)
$scripts = @(
    @{
        Name = "Setup"
        Description = "Install skills, PDF tools, and run diagnostic tests"
        SetupMenu = $true
        Color = [System.Drawing.Color]::FromArgb(96, 125, 139)  # Blue-gray
    },
    @{
        Name = "CodexService.ps1"
        Description = "Start a Codex AI agent that accepts JSON requests via Named Pipe"
        SelectDirectory = $true
        Color = [System.Drawing.Color]::FromArgb(46, 125, 50)  # Green
    },
    @{
        Name = "CodexClient.ps1"
        Description = "Send a custom prompt to the Codex agent and view the response"
        PromptDialog = $true
        Color = [System.Drawing.Color]::FromArgb(25, 118, 210)  # Blue
    },
    @{
        Name = "Summarize-Files.ps1"
        Description = "Reads file paths from CSV, extracts text, sends to CodexService for AI summary, appends results"
        Color = [System.Drawing.Color]::FromArgb(156, 39, 176)  # Purple
        Height = 56  # 25% taller for longer description
    }
)

# Create form
$form = New-Object System.Windows.Forms.Form
$form.Text = "AIclilistener Menu"
$form.Size = New-Object System.Drawing.Size(625, 450)
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
$subtitleLabel.Text = "Select an option:"
$subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$subtitleLabel.Size = New-Object System.Drawing.Size(580, 20)
$subtitleLabel.Location = New-Object System.Drawing.Point(20, 50)
$form.Controls.Add($subtitleLabel)

# Create buttons
$yPos = 85
$buttonHeight = 45
$buttonSpacing = 8
$buttonWidth = 565

foreach ($script in $scripts) {
    # For non-Setup items, check if script exists
    if (-not $script.SetupMenu) {
        $scriptPath = Join-Path $scriptDir $script.Name
        if (-not (Test-Path $scriptPath)) {
            continue
        }
    }

    # Create button
    $button = New-Object System.Windows.Forms.Button
    $btnHeight = if ($script.Height) { $script.Height } else { $buttonHeight }
    $button.Size = New-Object System.Drawing.Size($buttonWidth, $btnHeight)
    $button.Location = New-Object System.Drawing.Point(20, $yPos)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $script.Color
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $button.TextAlign = "MiddleLeft"
    $button.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand

    # Button text
    $button.Text = "  $($script.Name)`n  $($script.Description)"

    # Store script info in Tag
    $button.Tag = $script

    # Click handler
    $button.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $path = Join-Path $scriptDir $info.Name

        if ($info.SetupMenu) {
            Show-SetupMenu -ParentForm $form

        } elseif ($info.PromptDialog) {
            Show-CodexClientDialog -ParentForm $form

        } elseif ($info.SelectDirectory) {
            # Special handling for CodexService
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

            $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderBrowser.Description = "Select the directory where the Codex agent can write files"
            $folderBrowser.ShowNewFolderButton = $true

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
            Start-Process cmd.exe -ArgumentList "/k", "cd /d `"$selectedDir`" && powershell -ExecutionPolicy Bypass -File `"$path`""

        } else {
            Start-Process cmd.exe -ArgumentList "/k", "powershell -ExecutionPolicy Bypass -File `"$path`" && echo. && echo Press Enter to close... && pause >nul"
        }
    })

    # Hover effects
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
    $yPos += $btnHeight + $buttonSpacing
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
