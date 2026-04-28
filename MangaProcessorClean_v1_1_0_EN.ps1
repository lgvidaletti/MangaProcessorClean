# MangaProcessorClean v1.1.0
# Author: Luigi Vidaletti + CREAO AI
# Description: Manga image processor for Kindle Scribe, powered by ImageMagick
# Repository: github.com/seuusuario/MangaProcessorClean

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- CHECK FOR IMAGEMAGICK ---
$magickCheck = Get-Command magick -ErrorAction SilentlyContinue
if (-not $magickCheck) {
    [System.Windows.Forms.MessageBox]::Show(
        "ImageMagick was not found on this system.`n`nPlease install it from: https://imagemagick.org/script/download.php#windows`n`nMake sure to check 'Add application directory to your system path' during setup.`nThen restart PowerShell and try again.",
        "ImageMagick not found",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit
}

# --- HELP TEXTS FOR EACH PARAMETER ---
$script:HelpTexts = @{
    "ResizeH"  = "RESIZE HORIZONTAL (width x height)`n`nUsed when the image is wider than it is tall.`nDefault: 2480x1860`n`nThis is exactly the resolution the Kindle Scribe`ndisplays in landscape mode at 300 DPI.`n`nIf the original image is smaller, it gets upscaled`nusing a Lanczos filter (high quality) and centered.`nAny empty space is filled with the detected background color."
    "ResizeV"  = "RESIZE VERTICAL (width x height)`n`nUsed when the image is taller than it is wide.`nDefault: 1860x2480`n`nThis is the most common manga page orientation (portrait).`nSame logic as Resize H: 300 DPI, Lanczos filter, centered with extent."
    "Fuzz"     = "FUZZ (color tolerance)`n`nUsed when automatically detecting the image background.`nDefault: 5%`n`nExamples:`n  0% -> only matches the exact color`n  5% -> allows slight variations (great for JPEG artifacts)`n 10% -> allows moderate variations`n 15% -> might confuse background with actual content`n`nIncrease this if the background isn't being detected correctly."
    "Unsharp"  = "UNSHARP MASK (sharpness)`n`nFormat: radius x sigma + strength + threshold`nDefault: 0x0.6+0.7+0.02`n`n  radius 0     -> calculated automatically`n  sigma 0.6   -> base blur softness`n  strength 0.7 -> sharpening intensity`n  threshold 0.02 -> only sharpens where there's real contrast`n`nMore aggressive: 0x1.0+1.5+0.01`nSofter:          0x0.4+0.4+0.05"
    "Contrast" = "CONTRAST STRETCH (histogram adjustment)`n`nFormat: min%xmax% - clips the histogram edges`nDefault: 0.5%x0.5%`n`n0.5%x0.5% -> gentle clipping on shadows and highlights`n1.0%x1.0% -> stronger, increases overall contrast`n2.0%x1.0% -> deeper shadows`n`nNote: For washed-out grays in manga,`nuse the Level parameter below instead."
    "Level"    = "LEVEL (black and white remapping)`n`nFormat: X%,Y%  where X=new black point, Y=new white point`nDefault: 0%,100% (no change)`n`nThis is the go-to fix for grayish manga!`n`n  0%,100% -> no change`n  5%,95%  -> slight correction`n 10%,90% -> good starting point for washed-out manga`n 15%,85% -> deeper blacks, cleaner whites`n 20%,80% -> aggressive — may lose halftone details`n`nUnlike Contrast Stretch, Level actually REDEFINES`nthe black and white points in the histogram."
    "Quality"  = "JPEG QUALITY (compression)`n`nScale: 1 (terrible) to 100 (maximum)`nDefault: 95`n`nThis script also uses 4:4:4 chroma (no color subsampling)`nand dct-method=float for maximum JPEG precision.`n`n90 -> excellent quality, smaller file`n95 -> great balance (recommended)`n100 -> visually lossless, larger file`n`nFor Kindle Scribe, anywhere between 92-95 is the sweet spot."
    "Threads"  = "PARALLEL THREADS`n`nHow many images to process at the same time.`nDefault: half your CPU's logical core count`n`nExamples for an 8-core CPU:`n  2 -> conservative, keeps the system responsive`n  4 -> good balance (recommended)`n  8 -> max, uses every core`n`nGoing too high may slow the system during processing.`nImageMagick already uses multiple cores per image internally,`nso 4-6 threads is usually the sweet spot."
}

# --- WORKER SCRIPTBLOCK (runs in a separate runspace/thread) ---
$script:WorkerBlock = {
    param($file, $ROOT, $OUTPUT, $resizeH, $resizeV, $fuzz, $unsharp, $contrast, $level, $quality, $skipExist)

    $result = [PSCustomObject]@{
        RelPath    = ""
        Outfile    = ""
        Orient     = ""
        Bg         = ""
        SampleX    = 0
        SampleY    = 0
        PixelVal   = 255
        Status     = "ok"
        ErrorMsg   = ""
    }

    try {
        $filename     = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $relativePath = $file.Substring($ROOT.Length).TrimStart("\","/")
        $dirPart      = Split-Path $relativePath -Parent
        if ($dirPart -match "^[A-Z]:") { $dirPart = $dirPart.Substring(2).TrimStart("\") }
        $targetDir    = if ([string]::IsNullOrWhiteSpace($dirPart)) { $OUTPUT } else { Join-Path $OUTPUT $dirPart }
        $outfile      = Join-Path $targetDir ($filename + "_upscale.jpg")

        $result.RelPath = $relativePath
        $result.Outfile = $outfile

        # SKIP ALREADY PROCESSED FILES
        if ($skipExist -and (Test-Path $outfile)) {
            $result.Status = "skipped"
            return $result
        }

        # DETECT ORIENTATION
        $orientation = & magick identify -format "%[fx:w>h]" "$file" 2>$null
        if (!$orientation) { $orientation = 0 }
        $isHorizontal = "$orientation" -match "1|true"
        $result.Orient = if ($isHorizontal) { "Horizontal" } else { "Vertical" }

        # DETECT BACKGROUND COLOR
        $sampleX = 0; $sampleY = 0; $val = 255; $bg = "white"
        $trim = & magick "$file" -fuzz $fuzz -trim -format "%@" info: 2>$null
        if ($trim) {
            if ($trim -match "\+(\d+)\+(\d+)$") {
                $sampleX = [math]::Max(0, [int]([int]$matches[1] / 2))
                $sampleY = [math]::Max(0, [int]([int]$matches[2] / 2))
            }
            $color = & magick "$file" -format "%[pixel:p{$sampleX,$sampleY}]" info: 2>$null
            if ($color -match "gray\((\d+)\)") { $val = [int]$matches[1] }
            elseif ($color -match "srgb\((\d+),(\d+),(\d+)\)") { $val = ([int]$matches[1] + [int]$matches[2] + [int]$matches[3]) / 3 }
            $bg = if ($val -lt 128) { "black" } else { "white" }
        }
        $result.Bg       = $bg
        $result.SampleX  = $sampleX
        $result.SampleY  = $sampleY
        $result.PixelVal = $val

        # CREATE OUTPUT FOLDER (thread-safe with -Force)
        if (!(Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # IMAGE PROCESSING
        $resizeParam = if ($isHorizontal) { $resizeH } else { $resizeV }
        $extentParam = $resizeParam

        $levelArgs = @()
        if ($level -ne "0%,100%" -and $level -ne "0%, 100%") {
            $levelArgs = @("-level", $level)
        }

        & magick "$file" `
            -filter Lanczos `
            -resize $resizeParam `
            -background $bg `
            -gravity center `
            -extent $extentParam `
            @levelArgs `
            -unsharp $unsharp `
            -contrast-stretch $contrast `
            -define jpeg:dct-method=float `
            -sampling-factor 4:4:4 `
            -strip `
            -quality $quality `
            "$outfile" 2>$null

        if ($LASTEXITCODE -ne 0) {
            $result.Status   = "error"
            $result.ErrorMsg = "magick returned exit code $LASTEXITCODE"
        }

    } catch {
        $result.Status   = "error"
        $result.ErrorMsg = $_.Exception.Message
    }

    return $result
}

# --- MAIN FORM ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "MangaProcessorClean v1.1.0"
$form.ClientSize = New-Object System.Drawing.Size(820, 830)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor = [System.Drawing.Color]::White

function New-Label($text, $x, $y, $w = 160, $h = 24) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.Location = New-Object System.Drawing.Point($x, $y)
    $lbl.Size = New-Object System.Drawing.Size($w, $h)
    $lbl.ForeColor = [System.Drawing.Color]::White
    return $lbl
}

function New-TextBox($default, $x, $y, $w = 180, $h = 26) {
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text = $default
    $tb.Location = New-Object System.Drawing.Point($x, $y)
    $tb.Size = New-Object System.Drawing.Size($w, $h)
    $tb.BackColor = [System.Drawing.Color]::FromArgb(55, 55, 55)
    $tb.ForeColor = [System.Drawing.Color]::White
    $tb.BorderStyle = "FixedSingle"
    return $tb
}

function New-HelpButton($tag, $x, $y) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "?"
    $btn.Tag = $tag
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    $btn.Size = New-Object System.Drawing.Size(28, 26)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 120)
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = "Flat"
    $btn.Add_Click({
        $key = $this.Tag
        $msg = $script:HelpTexts[$key]
        [System.Windows.Forms.MessageBox]::Show($msg, "Help - $key", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })
    return $btn
}

# --- INPUT FOLDER SECTION ---
$form.Controls.Add((New-Label "INPUT FOLDER" 20 20 300 22))

$txtFolder = New-TextBox "" 20 46 620 28
$form.Controls.Add($txtFolder)

$btnFolder = New-Object System.Windows.Forms.Button
$btnFolder.Text = "Browse Folder"
$btnFolder.Location = New-Object System.Drawing.Point(650, 44)
$btnFolder.Size = New-Object System.Drawing.Size(150, 30)
$btnFolder.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnFolder.ForeColor = [System.Drawing.Color]::White
$btnFolder.FlatStyle = "Flat"
$btnFolder.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select the manga root folder"
    if ($dlg.ShowDialog() -eq "OK") {
        $txtFolder.Text = $dlg.SelectedPath
    }
})
$form.Controls.Add($btnFolder)

# --- PROCESSING PARAMETERS SECTION ---
$form.Controls.Add((New-Label "PROCESSING PARAMETERS" 20 92 400 22))

$paramY = 118
$paramStep = 38

# Resize Horizontal
$form.Controls.Add((New-Label "Resize Horizontal:" 20 $paramY))
$txtResizeH = New-TextBox "2480x1860" 190 $paramY
$form.Controls.Add($txtResizeH)
$form.Controls.Add((New-HelpButton "ResizeH" 378 $paramY))

$paramY += $paramStep

# Resize Vertical
$form.Controls.Add((New-Label "Resize Vertical:" 20 $paramY))
$txtResizeV = New-TextBox "1860x2480" 190 $paramY
$form.Controls.Add($txtResizeV)
$form.Controls.Add((New-HelpButton "ResizeV" 378 $paramY))

$paramY += $paramStep

# Fuzz
$form.Controls.Add((New-Label "Fuzz:" 20 $paramY))
$txtFuzz = New-TextBox "5%" 190 $paramY
$form.Controls.Add($txtFuzz)
$form.Controls.Add((New-HelpButton "Fuzz" 378 $paramY))

$paramY += $paramStep

# Unsharp
$form.Controls.Add((New-Label "Unsharp:" 20 $paramY))
$txtUnsharp = New-TextBox "0x0.6+0.7+0.02" 190 $paramY 180 26
$form.Controls.Add($txtUnsharp)
$form.Controls.Add((New-HelpButton "Unsharp" 378 $paramY))

$paramY += $paramStep

# Contrast Stretch
$form.Controls.Add((New-Label "Contrast Stretch:" 20 $paramY))
$txtContrast = New-TextBox "0.5%x0.5%" 190 $paramY
$form.Controls.Add($txtContrast)
$form.Controls.Add((New-HelpButton "Contrast" 378 $paramY))

$paramY += $paramStep

# Level — highlighted in yellow (most impactful param for low-quality manga)
$lblLevel = New-Label "Level (Black/White):" 20 $paramY 170 24
$lblLevel.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 80)
$form.Controls.Add($lblLevel)
$txtLevel = New-TextBox "0%,100%" 190 $paramY
$form.Controls.Add($txtLevel)
$form.Controls.Add((New-HelpButton "Level" 378 $paramY))

$paramY += $paramStep

# JPEG Quality
$form.Controls.Add((New-Label "JPEG Quality:" 20 $paramY))
$txtQuality = New-TextBox "95" 190 $paramY
$form.Controls.Add($txtQuality)
$form.Controls.Add((New-HelpButton "Quality" 378 $paramY))

$paramY += $paramStep + 6

# --- THREADS + SKIP CHECKBOX (same row) ---
$cpuCount  = [Environment]::ProcessorCount
$defThread = [math]::Max(1, [int]($cpuCount / 2))

$lblThreads = New-Label "Parallel threads:" 20 $paramY 140 26
$lblThreads.ForeColor = [System.Drawing.Color]::FromArgb(100, 220, 255)
$form.Controls.Add($lblThreads)

$numThreads = New-Object System.Windows.Forms.NumericUpDown
$numThreads.Location  = New-Object System.Drawing.Point(165, ($paramY - 2))
$numThreads.Size      = New-Object System.Drawing.Size(60, 26)
$numThreads.Minimum   = 1
$numThreads.Maximum   = $cpuCount
$numThreads.Value     = $defThread
$numThreads.BackColor = [System.Drawing.Color]::FromArgb(55, 55, 55)
$numThreads.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($numThreads)

$lblCpuInfo = New-Label "(CPU: $cpuCount cores)" 232 $paramY 140 26
$lblCpuInfo.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblCpuInfo)

$form.Controls.Add((New-HelpButton "Threads" 378 $paramY))

$chkSkip = New-Object System.Windows.Forms.CheckBox
$chkSkip.Text      = "Skip already processed images"
$chkSkip.Location  = New-Object System.Drawing.Point(420, $paramY)
$chkSkip.Size      = New-Object System.Drawing.Size(300, 26)
$chkSkip.Checked   = $true
$chkSkip.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($chkSkip)

$paramY += 38

# --- LIVE STATUS BAR ---
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = "Ready. Select a folder and hit Process."
$lblStatus.Location  = New-Object System.Drawing.Point(20, $paramY)
$lblStatus.Size      = New-Object System.Drawing.Size(780, 20)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
$lblStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$form.Controls.Add($lblStatus)

$paramY += 26

# --- PROGRESS BAR ---
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, $paramY)
$progressBar.Size     = New-Object System.Drawing.Size(780, 22)
$progressBar.Minimum  = 0
$progressBar.Value    = 0
$form.Controls.Add($progressBar)

$paramY += 32

# --- LOG PANEL ---
$form.Controls.Add((New-Label "LOG" 20 $paramY 60 20))
$paramY += 22

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location   = New-Object System.Drawing.Point(20, $paramY)
$txtLog.Size       = New-Object System.Drawing.Size(780, 190)
$txtLog.ReadOnly   = $true
$txtLog.BackColor  = [System.Drawing.Color]::FromArgb(20, 20, 20)
$txtLog.ForeColor  = [System.Drawing.Color]::LightGray
$txtLog.Font       = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.ScrollBars = "Vertical"
$form.Controls.Add($txtLog)

$paramY += 200

# --- BOTTOM BUTTONS: PROCESS + FAQ ---
$btnProcess = New-Object System.Windows.Forms.Button
$btnProcess.Text      = "PROCESS IMAGES"
$btnProcess.Location  = New-Object System.Drawing.Point(20, $paramY)
$btnProcess.Size      = New-Object System.Drawing.Size(580, 44)
$btnProcess.BackColor = [System.Drawing.Color]::FromArgb(0, 160, 80)
$btnProcess.ForeColor = [System.Drawing.Color]::White
$btnProcess.FlatStyle = "Flat"
$btnProcess.Font      = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnProcess)

$btnFAQ = New-Object System.Windows.Forms.Button
$btnFAQ.Text      = "FAQ / About"
$btnFAQ.Location  = New-Object System.Drawing.Point(610, $paramY)
$btnFAQ.Size      = New-Object System.Drawing.Size(190, 44)
$btnFAQ.BackColor = [System.Drawing.Color]::FromArgb(80, 60, 120)
$btnFAQ.ForeColor = [System.Drawing.Color]::White
$btnFAQ.FlatStyle = "Flat"
$btnFAQ.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($btnFAQ)

# --- FAQ / ABOUT TEXT ---
$faqText = @"
MangaProcessorClean v1.1.0
==========================

WHY DOES THIS TOOL EXIST?
The Kindle Scribe has a 300 DPI e-ink screen — great hardware for reading
manga. The problem is that most manga files out there, even from official
sources, come with:

  - Low resolution that doesn't use the screen's potential
  - Wrong aspect ratios that create ugly black bars or stretching
  - Washed-out gray tones where you'd expect solid black
  - Dirty backgrounds that confuse margin detection
  - Poor JPEG compression with visible artifacts

MangaProcessorClean fixes all of that with a full image processing pipeline
built on top of ImageMagick.

WHAT DOES IT DO?
1. SMART RESIZING
   - Detects whether each page is horizontal or vertical
   - Resizes to the exact Kindle Scribe resolution (300 DPI)
   - Uses the Lanczos filter — the best choice for upscaling
   - Centers the result with -extent and fills empty space with the real background color

2. AUTOMATIC BACKGROUND DETECTION
   - Uses -fuzz + -trim to find the actual image edges
   - Samples pixels near the borders to decide: black or white background?
   - Prevents the classic problem: black background filled with white (or vice versa)
   - Works even with JPEG artifacts (that's what the Fuzz setting is for)

3. CONTRAST FIXES FOR MANGA
   - Contrast Stretch: clips the histogram edges to boost overall contrast
   - Level: redefines the black and white points — the key fix for
     washed-out manga where black became gray
   - Unsharp Mask: sharpens line art and text without creating halos

4. HIGH-QUALITY COMPRESSION
   - sampling-factor 4:4:4: full chroma, no color subsampling
   - dct-method=float: maximum JPEG precision
   - Configurable quality setting (default 95)

5. FOLDER STRUCTURE IS PRESERVED
   - Full subfolder hierarchy is kept inside the output folder:
     MangaRoot/Chapter01/001.jpg -> output/Chapter01/001_upscale.jpg
   - Originals are never touched
   - Any existing output folder is automatically excluded from scanning

6. PARALLEL PROCESSING (v1.1.0)
   - Uses RunspacePool to process N images at the same time
   - N is configurable right in the UI (default = half your CPU cores)
   - A WinForms Timer collects results on the main thread, so the UI never freezes
   - Speed gain is roughly proportional to the thread count

HOW TO USE
1. Click "Browse Folder" and pick the manga root folder
2. Adjust parameters if needed (defaults work well for most manga)
3. For washed-out manga: set Level to something like 10%,90%
4. Set how many parallel threads you want
5. Click "PROCESS IMAGES"
6. Processed images will be in [folder]/output/

REQUIREMENTS
- ImageMagick (free): https://imagemagick.org/script/download.php#windows
- PowerShell 5.1+ (already included in Windows 10/11)

CHANGELOG
v1.1.0 - Parallel processing
  - RunspacePool with configurable thread count in the UI
  - WinForms Timer for safe result polling without UI freezes
  - Live status bar showing progress in real time
  - Help button for the Threads parameter

v1.0.0 - First public release
  - Windows Forms GUI (no WPF, no XAML, no external dependencies)
  - 7 configurable parameters with contextual help buttons
  - Automatic orientation and background detection
  - Level parameter for fixing washed-out manga
  - Skip already-processed files (checkbox, on by default)
  - Real-time log showing orientation and background per image
  - Progress bar and final summary
  - ImageMagick check on startup with install link
  - Per-file try/catch — one bad file won't stop everything

LICENSE
MIT License - free to use, modify, and share.
Credit is appreciated but not required.
"@

$btnFAQ.Add_Click({
    $faqForm = New-Object System.Windows.Forms.Form
    $faqForm.Text          = "MangaProcessorClean v1.1.0 - FAQ & About"
    $faqForm.ClientSize    = New-Object System.Drawing.Size(720, 600)
    $faqForm.StartPosition = "CenterParent"
    $faqForm.BackColor     = [System.Drawing.Color]::FromArgb(30, 30, 30)

    $faqBox = New-Object System.Windows.Forms.RichTextBox
    $faqBox.Text       = $faqText
    $faqBox.Location   = New-Object System.Drawing.Point(10, 10)
    $faqBox.Size       = New-Object System.Drawing.Size(700, 540)
    $faqBox.ReadOnly   = $true
    $faqBox.BackColor  = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $faqBox.ForeColor  = [System.Drawing.Color]::White
    $faqBox.Font       = New-Object System.Drawing.Font("Consolas", 9)
    $faqBox.ScrollBars = "Vertical"
    $faqForm.Controls.Add($faqBox)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text      = "Close"
    $btnClose.Location  = New-Object System.Drawing.Point(290, 558)
    $btnClose.Size      = New-Object System.Drawing.Size(140, 32)
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.FlatStyle = "Flat"
    $btnClose.Add_Click({ $faqForm.Close() })
    $faqForm.Controls.Add($btnClose)

    $faqForm.ShowDialog() | Out-Null
})

# --- LOG HELPER (main thread only) ---
function Write-Log($msg, $color = "LightGray") {
    $txtLog.SelectionStart  = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor  = [System.Drawing.Color]::$color
    $txtLog.AppendText("$msg`n")
    $txtLog.ScrollToCaret()
}

# --- PROCESSING LOGIC WITH RUNSPACEPOOL ---
$btnProcess.Add_Click({

    $ROOT = $txtFolder.Text.TrimEnd("\")
    if ([string]::IsNullOrWhiteSpace($ROOT) -or !(Test-Path $ROOT)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid folder before processing.", "No folder selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $resizeH   = $txtResizeH.Text.Trim()
    $resizeV   = $txtResizeV.Text.Trim()
    $fuzz      = $txtFuzz.Text.Trim()
    $unsharp   = $txtUnsharp.Text.Trim()
    $contrast  = $txtContrast.Text.Trim()
    $level     = $txtLevel.Text.Trim()
    $quality   = $txtQuality.Text.Trim()
    $skipExist = $chkSkip.Checked
    $nThreads  = [int]$numThreads.Value

    foreach ($param in @($resizeH, $resizeV, $fuzz, $unsharp, $contrast, $level, $quality)) {
        if ([string]::IsNullOrWhiteSpace($param)) {
            [System.Windows.Forms.MessageBox]::Show("All parameters must be filled in before processing.", "Empty parameter", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
    }

    $OUTPUT = Join-Path $ROOT "output"
    if (!(Test-Path $OUTPUT)) { New-Item -ItemType Directory -Path $OUTPUT | Out-Null }

    $txtLog.Clear()
    Write-Log "=== MangaProcessorClean v1.1.0 ===" "Cyan"
    Write-Log "Folder  : $ROOT" "Gray"
    Write-Log "Threads : $nThreads of $([Environment]::ProcessorCount) logical cores" "Cyan"
    Write-Log "Params  : ResizeH=$resizeH | ResizeV=$resizeV | Fuzz=$fuzz | Level=$level | Quality=$quality" "Gray"
    Write-Log "----------------------------------------------" "Gray"

    $allFiles = Get-ChildItem -Path $ROOT -Recurse -Filter *.jpg |
                Where-Object { $_.FullName -notmatch "\\output\\" }
    $total = $allFiles.Count

    if ($total -eq 0) {
        Write-Log "No .jpg images found in the selected folder." "Yellow"
        return
    }

    Write-Log "$total images found. Starting processing..." "White"

    $progressBar.Maximum  = $total
    $progressBar.Value    = 0
    $btnProcess.Enabled   = $false
    $btnFolder.Enabled    = $false

    # --- BUILD RUNSPACE POOL ---
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $nThreads)
    $pool.ApartmentState = "MTA"
    $pool.Open()

    # --- FIRE ALL JOBS ---
    $jobs = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($fileItem in $allFiles) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($script:WorkerBlock)
        [void]$ps.AddArgument($fileItem.FullName)
        [void]$ps.AddArgument($ROOT)
        [void]$ps.AddArgument($OUTPUT)
        [void]$ps.AddArgument($resizeH)
        [void]$ps.AddArgument($resizeV)
        [void]$ps.AddArgument($fuzz)
        [void]$ps.AddArgument($unsharp)
        [void]$ps.AddArgument($contrast)
        [void]$ps.AddArgument($level)
        [void]$ps.AddArgument($quality)
        [void]$ps.AddArgument($skipExist)

        $jobs.Add(@{
            PS     = $ps
            Handle = $ps.BeginInvoke()
            Done   = $false
        })
    }

    # Counters accessible from the timer closure
    $script:CountProcessed = 0
    $script:CountSkipped   = 0
    $script:CountErrors    = 0
    $script:TotalJobs      = $total

    # --- POLLING TIMER: collects results safely on the main thread ---
    $pollTimer = New-Object System.Windows.Forms.Timer
    $pollTimer.Interval = 300

    $pollTimer.Add_Tick({

        foreach ($job in $jobs) {
            if ($job.Done) { continue }
            if (-not $job.Handle.IsCompleted) { continue }

            # Collect result from completed job
            try {
                $result = $job.PS.EndInvoke($job.Handle)
            } catch {
                $result = [PSCustomObject]@{
                    Status   = "error"
                    RelPath  = "unknown"
                    ErrorMsg = $_.Exception.Message
                    Orient   = ""; Bg = ""; SampleX = 0; SampleY = 0; PixelVal = 0; Outfile = ""
                }
            }
            $job.PS.Dispose()
            $job.Done = $true

            switch ($result.Status) {
                "skipped" {
                    $script:CountSkipped++
                    Write-Log "[SKIPPED] $($result.RelPath)" "DarkGray"
                }
                "error" {
                    $script:CountErrors++
                    Write-Log "[ERROR] $($result.RelPath)" "Red"
                    Write-Log "  $($result.ErrorMsg)" "Red"
                }
                default {
                    $script:CountProcessed++
                    Write-Log "[OK] $($result.RelPath)" "White"
                    Write-Log "  Orientation : $($result.Orient)" "Yellow"
                    Write-Log "  Background  : $($result.Bg) (pixel $($result.SampleX),$($result.SampleY) = val $($result.PixelVal))" "Cyan"
                    Write-Log "  Saved to    : $($result.Outfile)" "Green"
                }
            }
        }

        $done   = $script:CountProcessed + $script:CountSkipped + $script:CountErrors
        $active = ($jobs | Where-Object { -not $_.Done -and $_.Handle.IsCompleted -eq $false } | Measure-Object).Count

        $progressBar.Value = [math]::Min($progressBar.Maximum, $done)
        $lblStatus.Text    = "Done: $($script:CountProcessed)  |  Skipped: $($script:CountSkipped)  |  Errors: $($script:CountErrors)  |  Active: $active  |  Total: $($script:TotalJobs)"

        # Check if all jobs have finished
        $remaining = ($jobs | Where-Object { -not $_.Done } | Measure-Object).Count
        if ($remaining -eq 0) {
            $pollTimer.Stop()
            $pool.Close()
            $pool.Dispose()

            $progressBar.Value = $progressBar.Maximum
            $lblStatus.Text    = "All done! Processed: $($script:CountProcessed) | Skipped: $($script:CountSkipped) | Errors: $($script:CountErrors)"

            Write-Log "===============================================" "Cyan"
            Write-Log "FINISHED: $($script:CountProcessed) processed | $($script:CountSkipped) skipped | $($script:CountErrors) errors" "Lime"
            Write-Log "Output folder: $OUTPUT" "Gray"
            Write-Log "===============================================" "Cyan"

            $btnProcess.Enabled = $true
            $btnFolder.Enabled  = $true

            [System.Windows.Forms.MessageBox]::Show(
                "All done!`n`nProcessed : $($script:CountProcessed)`nSkipped   : $($script:CountSkipped)`nErrors    : $($script:CountErrors)`n`nOutput folder: $OUTPUT",
                "MangaProcessorClean v1.1.0",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    })

    $pollTimer.Start()
})

[System.Windows.Forms.Application]::Run($form)
