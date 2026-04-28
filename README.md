
# MangaProcessorClean

<p align="center">
  <img src="https://img.shields.io/badge/version-1.1.0-brightgreen?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/platform-Windows-0078D6?style=for-the-badge&logo=windows" alt="Platform">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell" alt="PowerShell">
  <img src="https://img.shields.io/badge/ImageMagick-required-FF6B6B?style=for-the-badge" alt="ImageMagick">
  <img src="https://img.shields.io/badge/license-MIT-yellow?style=for-the-badge" alt="License">
</p>

<p align="center">
  <b>A manga image processor for Kindle Scribe — with a simple GUI, automatic background detection, and parallel processing.</b>
</p>

---

## 📖 Why does this exist?

The **Kindle Scribe** has a beautiful **300 DPI** e-ink screen (1860×2480 px) — perfect for reading manga. The problem is that most manga files out there, even from official sources, look terrible on it:

- ❌ Low resolution that doesn't use the screen's full potential
- ❌ Wrong aspect ratios that create ugly black bars or stretching
- ❌ Washed-out gray tones where there should be solid black
- ❌ Dirty backgrounds that confuse edge detection
- ❌ Heavy JPEG compression with visible artifacts

**MangaProcessorClean** fixes all of that. It runs every image through a carefully tuned ImageMagick pipeline and outputs files that are properly sized, sharp, and high-contrast — the way manga is meant to be read.

---

## 🖼️ Screenshot

```
┌─────────────────────────────────────────────────────────────────┐
│  MangaProcessorClean v1.1.0                                     │
├─────────────────────────────────────────────────────────────────┤
│  INPUT FOLDER                                                   │
│  [ C:\Manga\OnePiece                               ] [Browse]   │
│                                                                 │
│  PROCESSING PARAMETERS                                          │
│  Resize Horizontal:  [ 2480x1860      ]  [?]                   │
│  Resize Vertical:    [ 1860x2480      ]  [?]                   │
│  Fuzz:               [ 5%             ]  [?]                   │
│  Unsharp:            [ 0x0.6+0.7+0.02 ]  [?]                  │
│  Contrast Stretch:   [ 0.5%x0.5%     ]  [?]                   │
│  Level (Black/White):[ 0%,100%        ]  [?]  ← yellow         │
│  JPEG Quality:       [ 95             ]  [?]                   │
│                                                                 │
│  Parallel threads: [4▲▼] (CPU: 8 cores) [?]                   │
│  ☑ Skip already processed images                               │
│                                                                 │
│  Done: 47 | Skipped: 0 | Errors: 0 | Active: 3 | Total: 120   │
│  [████████████████████░░░░░░░░░░░]                             │
│                                                                 │
│  LOG                                                            │
│  [OK] Chapter01/001.jpg                                        │
│    Orientation : Vertical (1860x2480)                          │
│    Background  : white (pixel 2,3 = val 241)                   │
│    Saved to    : output\Chapter01\001_upscale.jpg              │
│                                                                 │
│  [ PROCESS IMAGES                 ]  [ FAQ / About ]           │
└─────────────────────────────────────────────────────────────────┘
```

> 📸 *A real screenshot will be added after the first public release.*

---

## ✨ Features

| Feature | Details |
|---|---|
| 🖥️ **Clean GUI** | Pure Windows Forms — no WPF, no XAML, no external dependencies |
| 🔍 **Orientation detection** | Automatically detects landscape vs. portrait per image |
| 🎨 **Background detection** | Pixel sampling with configurable color tolerance (Fuzz) |
| 📐 **Smart resize** | Lanczos filter + centered extent for exact 300 DPI output |
| ⚫ **Gray fix** | Level parameter remaps black/white points in the histogram |
| 🔪 **Sharpening** | Configurable Unsharp Mask to enhance line art and text |
| 🗜️ **High-quality JPEG** | 4:4:4 chroma + DCT float + configurable quality level |
| 📁 **Folder structure kept** | Full subfolder hierarchy preserved inside `output/` |
| ⚡ **Parallel processing** | RunspacePool with configurable thread count in the UI |
| ⏭️ **Smart skip** | Skips already-processed files to avoid redundant work |
| 🛡️ **Error resilience** | Per-file try/catch — one bad image won't stop everything |
| ❓ **Contextual help** | `?` button per parameter with plain-English explanations |
| 📋 **Live log** | Shows orientation + background per image as it processes |
| 🔔 **Dependency check** | Error popup with install link if ImageMagick isn't found |

---

## ⚙️ Requirements

| Requirement | Min. version | Link |
|---|---|---|
| **Windows** | 10 or 11 | — |
| **PowerShell** | 5.1 (already included in Windows) | — |
| **ImageMagick** | 7.x | [Download](https://imagemagick.org/script/download.php#windows) |

> ⚠️ When installing ImageMagick, make sure to check **"Add application directory to your system path"** so the `magick` command is available in PowerShell.

---

## 🚀 Getting started

### Option 1 — Run the script directly (`.ps1`)

1. Download `MangaProcessorClean_v1.1.0_EN.ps1`
2. Open PowerShell in the same folder
3. Run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "MangaProcessorClean_v1.1.0_EN.ps1"
```

### Option 2 — Build an `.exe` (double-click to run)

```powershell
# Install ps2exe (one-time setup)
Install-Module -Name ps2exe -Scope CurrentUser -Force

# Build the exe
powershell.exe -ExecutionPolicy Bypass -Command "Import-Module ps2exe; ps2exe .\MangaProcessorClean_v1.1.0_EN.ps1 .\MangaProcessorClean_v1.1.0.exe -noConsole -title 'MangaProcessorClean v1.1.0'"
```

> The `.exe` still requires ImageMagick to be installed on the target machine. The app will show a helpful error popup with an install link if it's not found.

---

## 📂 Output structure

The script preserves your full folder structure. Typical manga layout:

```
OnePiece/                        ← root folder you selected
├── Chapter001/
│   ├── 001.jpg
│   ├── 002.jpg
│   └── 003.jpg
├── Chapter002/
│   ├── 001.jpg
│   └── 002.jpg
└── output/                      ← created automatically
    ├── Chapter001/
    │   ├── 001_upscale.jpg
    │   ├── 002_upscale.jpg
    │   └── 003_upscale.jpg
    └── Chapter002/
        ├── 001_upscale.jpg
        └── 002_upscale.jpg
```

**Originals are never modified.** All output goes into `output/`.

---

## 🎛️ Parameters

### Resize Horizontal
> **Default:** `2480x1860`

Target resolution for landscape images (wider than tall). This matches the Kindle Scribe screen in landscape mode at 300 DPI. The image is resized with Lanczos and centered using `-extent`. Empty space is filled with the detected background color.

---

### Resize Vertical
> **Default:** `1860x2480`

Target resolution for portrait images (taller than wide). This is the most common manga page orientation. Same logic: Lanczos + centered extent.

---

### Fuzz
> **Default:** `5%`

Color tolerance used when detecting the image background. Applied to `-trim` so ImageMagick can find the real edges even when the background has slight color variations from JPEG compression.

| Value | When to use |
|---|---|
| `0%` | Clean files with no compression artifacts |
| `5%` | Default — good for most JPEG manga |
| `10%` | Heavy JPEG artifacts near the borders |
| `15%+` | Risk of misidentifying content as background |

---

### Unsharp
> **Default:** `0x0.6+0.7+0.02`

Sharpens line art and text using an unsharp mask. Format: `radius x sigma + strength + threshold`.

| Preset | Value | Use case |
|---|---|---|
| Soft | `0x0.4+0.4+0.05` | Images that are already sharp |
| **Default** | `0x0.6+0.7+0.02` | Most manga |
| Aggressive | `0x1.0+1.5+0.01` | Very soft or blurry images |

---

### Contrast Stretch
> **Default:** `0.5%x0.5%`

Clips the histogram edges to increase contrast. The format `X%xY%` defines how many pixels to clip from the shadows and highlights respectively.

> 💡 For **washed-out grays** in low-quality manga, the **Level** parameter below works better.

---

### Level (Black/White) ⭐
> **Default:** `0%,100%` (no change)

This is the most powerful fix for low-quality manga. It redefines the **black and white points** in the histogram, remapping everything in between.

| Value | Effect |
|---|---|
| `0%,100%` | No change |
| `5%,95%` | Gentle correction |
| `10%,90%` | ✅ Good starting point for washed-out manga |
| `15%,85%` | Deep blacks, clean whites |
| `20%,80%` | Aggressive — may lose halftone details |

---

### JPEG Quality
> **Default:** `95`

Controls JPEG compression on the output. Combined with `sampling-factor 4:4:4` (full chroma, no color subsampling) and `dct-method=float` (maximum transform precision).

| Value | Result |
|---|---|
| `90` | Excellent quality, smaller file |
| `95` | ✅ Best balance for e-readers |
| `100` | Visually lossless, larger file |

---

### Parallel Threads
> **Default:** half your CPU's logical core count

Controls how many images get processed at the same time via `RunspacePool`. ImageMagick already uses multiple cores per image internally, so setting this too high can saturate the system without proportional gains.

| CPU cores | Recommended threads |
|---|---|
| 4 | 2 |
| 8 | 4 |
| 16 | 6–8 |

---

## 🔬 How it works (per image)

```
input.jpg
    │
    ├─► magick identify → detect orientation (landscape or portrait?)
    │
    ├─► magick -fuzz X% -trim → get real image boundary offset
    │       └─► magick pixel sample → black or white background?
    │
    └─► magick (main processing pass):
            -filter Lanczos
            -resize [ResizeH or ResizeV]
            -background [black or white]
            -gravity center
            -extent [ResizeH or ResizeV]
            [-level X%,Y%]              ← only if different from 0%,100%
            -unsharp [Unsharp]
            -contrast-stretch [Contrast]
            -define jpeg:dct-method=float
            -sampling-factor 4:4:4
            -strip
            -quality [Quality]
            → output/[subfolder]/[name]_upscale.jpg
```

---

## 📋 Changelog

### v1.1.0 — Parallel Processing
- ⚡ `RunspacePool` with configurable thread count in the UI
- 🔄 `WinForms Timer` for safe result polling without UI freezes
- 📊 Live status bar: done / skipped / errors / active jobs
- ❓ Help button for the Threads parameter

### v1.0.0 — First Public Release
- 🖥️ Pure Windows Forms GUI (no WPF/XAML)
- 🎛️ 7 configurable parameters with contextual help buttons
- 🔍 Automatic orientation detection (landscape / portrait)
- 🎨 Automatic background detection (black / white) via pixel sampling
- ⭐ Level parameter for fixing washed-out gray tones in manga
- ⏭️ Skip already-processed files (checkbox, on by default)
- 📝 Real-time log with orientation, background, and output path per image
- 📈 Progress bar + final summary popup
- 🔔 ImageMagick check at startup with install link
- 🛡️ Per-file try/catch — bad files don't stop the whole batch

---

## 🤝 Contributing

Pull requests are welcome! Interesting areas:

- [ ] CBZ/CBR support (extract, process, repack)
- [ ] Cancel button to stop parallel processing mid-run
- [ ] PNG input support
- [ ] Before/after preview in the UI
- [ ] Saveable parameter profiles

---

## 📄 License

```
MIT License

Copyright (c) 2025 Luigi Vidaletti

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

<p align="center">
  Built with ☕ for the manga reading community on Kindle Scribe.<br>
  If this saved your reading experience, drop a ⭐ on the repo!
</p>
