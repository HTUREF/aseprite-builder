# 04 Proves the checked-out source really is the pinned, complete tree.
$ErrorActionPreference = 'Stop'
Push-Location 'src-aseprite'
try {
    $head = (git rev-parse HEAD).Trim()
    Write-Host "HEAD commit : $head"
    Write-Host "Pinned SHA  : $env:ASEPRITE_SHA"
    if ($head -ne $env:ASEPRITE_SHA) {
        throw "Source pin mismatch: checked out $head but the workflow pins $env:ASEPRITE_SHA"
    }

    # Make sure the tag object exists locally: src/ver/CMakeLists.txt derives the
    # application version with 'git describe --tags', so a shallow checkout without
    # the tag would make the binary report "1.x-<sha>-dev" instead of 1.3.18.6.
    & git fetch --depth=1 --force origin ("refs/tags/" + $env:ASEPRITE_TAG + ":refs/tags/" + $env:ASEPRITE_TAG) 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: could not fetch tag $env:ASEPRITE_TAG." }

    $tagSha = (git rev-list -n 1 ("refs/tags/" + $env:ASEPRITE_TAG)).Trim()
    Write-Host ("Tag {0} resolves to {1}" -f $env:ASEPRITE_TAG, $tagSha)
    if ($tagSha -ne $env:ASEPRITE_SHA) { throw "Tag $env:ASEPRITE_TAG does not point at the pinned commit." }

    $describe = (& git describe --tags --always --dirty 2>&1 | Out-String).Trim()
    Write-Host "git describe: $describe"
    if ($describe -notmatch '1\.3\.18\.6') {
        Write-Host "WARNING: git describe does not mention the release tag; the compiled version string may contain a commit id."
    }

    Write-Host ""
    Write-Host "=== Submodule status ==="
    git submodule status --recursive
    $statusLines = @(git submodule status --recursive)
    $uninit = @($statusLines | Where-Object { $_ -match '^-' })
    if ($uninit.Count -gt 0) {
        Write-Host "Uninitialized submodules:"
        $uninit | ForEach-Object { Write-Host "  $_" }
        throw "Incomplete submodules: $($uninit.Count) not initialized"
    }

    foreach ($required in @('laf/CMakeLists.txt','laf/clip/CMakeLists.txt','third_party/lua','src/app')) {
        if (-not (Test-Path $required)) { throw "Missing required source path: $required" }
    }

    $subCount = $statusLines.Count
    Write-Host ""
    Write-Host "All $subCount submodules are initialized at their pinned commits."
    $modified = git status --porcelain
    if ($modified) {
        Write-Host "Working tree changes detected (informational):"
        $modified | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
    }
} finally { Pop-Location }

Add-Content -Path $env:GITHUB_ENV -Value "SUBMODULE_COUNT=$subCount"
Add-Content -Path $env:GITHUB_ENV -Value ("GIT_DESCRIBE=" + $describe)
