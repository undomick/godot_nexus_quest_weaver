# Converts images to RGBA (adds alpha channel) to avoid Godot's "RGB8 not supported" warning.
# Uses .NET System.Drawing - no external tools required.
#
# Usage: .\convert_to_rgba.ps1

Add-Type -AssemblyName System.Drawing

$assetsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pairs = @(
    @{ src = "portrait.png"; dest = "portrait.png" },
    @{ src = "portrait2.png"; dest = "portrait2.png" },
    @{ src = "bg_winter.jpg"; dest = "bg_winter.png" }
)

foreach ($p in $pairs) {
    $src = Join-Path $assetsDir $p.src
    if (-not (Test-Path $src)) {
        Write-Warning "Skip (not found): $($p.src)"
        continue
    }
    $dest = Join-Path $assetsDir $p.dest
    Write-Host "Converting $($p.src) -> $($p.dest) (RGBA)..."

    $orig = $null
    $bitmap = $null
    try {
        $orig = [System.Drawing.Image]::FromFile((Resolve-Path $src).Path)
        $bitmap = New-Object System.Drawing.Bitmap($orig.Width, $orig.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bitmap)
        $g.DrawImage($orig, 0, 0)
        $g.Dispose()
        $orig.Dispose()
        $orig = $null

        $savePath = $dest
        if ($src -eq $dest) {
            $savePath = [System.IO.Path]::GetTempFileName()
        }
        $bitmap.Save($savePath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        $bitmap = $null

        if ($src -eq $dest) {
            Move-Item -Force $savePath $dest
        }
    }
    finally {
        if ($orig) { $orig.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
    }
}

if (Test-Path (Join-Path $assetsDir "bg_winter.png")) {
    Write-Host ""
    Write-Host "bg_winter.png created. Update main_quest_test.tscn to use it, then delete bg_winter.jpg"
}
Write-Host "Done. Reimport in Godot (right-click asset -> Reimport) or restart editor."
