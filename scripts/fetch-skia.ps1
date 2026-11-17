# 05 Downloads the official prebuilt Skia that matches the pinned laf/misc/skia-tag.txt.
# The version is never guessed: laf/misc/skia-tag.txt at the pinned laf commit
# contains "m124-08a5439a6b" and laf/misc/skia-url.sh turns that into the URL below.
$ErrorActionPreference = 'Stop'
$t0 = Get-Date

$url = "https://github.com/aseprite/skia/releases/download/$env:SKIA_TAG/$env:SKIA_ASSET"
Write-Host "Skia tag    : $env:SKIA_TAG   (from laf/misc/skia-tag.txt at the pinned laf commit)"
Write-Host "Skia archive: $env:SKIA_ASSET"
Write-Host "Skia URL    : $url"

$lafTagFile = 'src-aseprite/laf/misc/skia-tag.txt'
if (-not (Test-Path $lafTagFile)) { throw "Missing $lafTagFile - laf submodule not populated?" }
$actualTag = (Get-Content $lafTagFile -Raw).Trim()
Write-Host "skia-tag.txt: $actualTag"
if ($actualTag -ne $env:SKIA_TAG) {
    throw "Skia version mismatch: source requires '$actualTag' but the workflow pins '$env:SKIA_TAG'."
}

$archive = Join-Path (Get-Location).Path $env:SKIA_ASSET
& curl.exe --fail --silent --show-error --location --retry 3 --retry-delay 5 --ssl-revoke-best-effort --output $archive $url
if ($LASTEXITCODE -ne 0) { throw "Skia download failed: $LASTEXITCODE" }

$size = (Get-Item $archive).Length
$hash = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
Write-Host "Downloaded  : $size bytes"
Write-Host "SHA-256     : $hash"
Write-Host "Expected    : $env:SKIA_SHA256"
if ($hash -ne $env:SKIA_SHA256.ToLowerInvariant()) {
    throw "Skia archive integrity check FAILED (expected $env:SKIA_SHA256, got $hash)"
}
Write-Host "Skia archive integrity verified against the pinned SHA-256."

Expand-Archive -Path $archive -DestinationPath (Join-Path (Get-Location).Path 'skia') -Force
Remove-Item $archive -Force

$libDir = Join-Path (Get-Location).Path 'skia/out/Release-x64'
if (-not (Test-Path $libDir)) { throw "Skia library dir missing after extraction: $libDir" }
$libs = @(Get-ChildItem $libDir -Filter *.lib -ErrorAction SilentlyContinue)
if ($libs.Count -eq 0) { throw "No .lib files in $libDir - Skia package looks incomplete." }
Write-Host "Skia libraries: $($libs.Count) .lib files in out/Release-x64"
$libs | Select-Object -First 40 -ExpandProperty Name | ForEach-Object { Write-Host "  $_" }

Add-Content -Path $env:GITHUB_ENV -Value "SKIA_ARCHIVE_SIZE=$size"
Add-Content -Path $env:GITHUB_ENV -Value "DUR_skia=$([int]((Get-Date) - $t0).TotalSeconds)"
