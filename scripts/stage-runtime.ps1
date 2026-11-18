# Builds the exact file set that ships in the ZIP.
# Shared by verification and packaging so the tested set and the shipped set cannot drift.
function New-RuntimeStage {
    param([Parameter(Mandatory = $true)][string]$Destination)

    $binDir  = Join-Path $env:GITHUB_WORKSPACE 'build/bin'
    $exePath = Join-Path $binDir 'aseprite.exe'
    $dataDir = Join-Path $binDir 'data'

    if (-not (Test-Path $exePath)) { throw "aseprite.exe not found in $binDir" }
    if (-not (Test-Path $dataDir)) { throw 'build/bin/data not found - the copy_data target did not run' }

    if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Copy-Item $exePath (Join-Path $Destination 'aseprite.exe') -Force
    Copy-Item $dataDir (Join-Path $Destination 'data') -Recurse -Force

    # Portable mode. App::isPortable() (src/app/app.cpp) is true exactly when an
    # aseprite.ini file sits next to the executable. In portable mode the user folder
    # becomes the application directory, so Aseprite.log, user.aseprite-brushes and
    # palettes/default.ase are written HERE instead of %APPDATA%\\Aseprite.
    # Verified empirically: without this file the app creates
    # %APPDATA%\\Aseprite; with it, nothing outside the app folder is touched.
    $ini = Join-Path $Destination 'aseprite.ini'
    if (-not (Test-Path $ini)) { New-Item -ItemType File -Path $ini -Force | Out-Null }

    # Convenience copy of the official application icon. It is the same asset the
    # executable embeds (0 ICON data/icons/ase.ico in src/main/win/resources_win32.rc),
    # so a shortcut can use it without digging inside data/.
    $icon = Join-Path $dataDir 'icons/ase.ico'
    if (Test-Path $icon) { Copy-Item $icon (Join-Path $Destination 'aseprite.ico') -Force }

    # Defensive: never ship intermediate build output.
    $excludeExts = @('.pdb','.ilk','.exp','.lib','.obj','.iobj','.ipdb','.idb','.res','.tlog','.map','.cache','.tmp')
    $stray = @(Get-ChildItem $Destination -Recurse -File | Where-Object { $excludeExts -contains $_.Extension.ToLowerInvariant() })
    if ($stray.Count -gt 0) { $stray | Remove-Item -Force }

    $required = @(
        'aseprite.exe',
        'aseprite.ini',
        'aseprite.ico',
        'data/fonts/fonts.xml',
        'data/extensions/aseprite-theme/package.json',
        'data/extensions/aseprite-theme/theme.xml',
        'data/extensions/aseprite-theme/sheet.png',
        'data/EULA.txt'
    )
    foreach ($r in $required) {
        if (-not (Test-Path (Join-Path $Destination $r))) {
            throw "Required runtime file missing from the stage: $r"
        }
    }

    return [pscustomobject]@{
        Destination = $Destination
        Required    = $required
        Files       = @(Get-ChildItem $Destination -Recurse -File)
    }
}
