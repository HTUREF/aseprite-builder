# 07 CMake configure - Ninja, RelWithDebInfo, Skia backend, Lua scripting.
$ErrorActionPreference = 'Stop'
$t0 = Get-Date
. ./scripts/msvc-env.ps1
Import-MsvcEnv

Write-Host "=== Toolchain filling the job (detected, never installed) ==="
$clBanner = (& cmd.exe /d /c "call cl 2>&1" | Select-Object -First 1)
if (-not $clBanner) { throw 'cl.exe not usable after importing the MSVC environment.' }
Write-Host "cl      : $clBanner"
Write-Host "cmake   : $(cmake --version | Select-Object -First 1)"
Write-Host "ninja   : $(ninja --version)"
Write-Host "generator: Ninja (already on the runner, not installed)"

$root  = (Get-Location).Path
$src   = (Resolve-Path 'src-aseprite').Path
$skia  = (Resolve-Path 'skia').Path
$build = Join-Path $root 'build'
$skiaLib = Join-Path $skia 'out/Release-x64'

$cmakeArgs = @(
    '-S', $src
    '-B', $build
    '-G', 'Ninja'
    "-DCMAKE_BUILD_TYPE=$env:BUILD_TYPE"
    '-DENABLE_TESTS=OFF'
    '-DENABLE_SCRIPTING=ON'
    '-DENABLE_CCACHE=OFF'
    '-DLAF_BACKEND=skia'
    "-DSKIA_DIR=$skia"
    "-DSKIA_LIBRARY_DIR=$skiaLib"
)

Write-Host ""
Write-Host ("cmake " + ($cmakeArgs -join ' '))
Write-Host ""
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed with exit code $LASTEXITCODE" }

# Prove the cache really carries the requested configuration.
$cachePath = Join-Path $build 'CMakeCache.txt'
if (-not (Test-Path $cachePath)) { throw "CMakeCache.txt not produced at $cachePath" }
$cache = Get-Content $cachePath -Raw
$expect = [ordered]@{
    'ENABLE_SCRIPTING:BOOL'   = 'ON'
    'ENABLE_TESTS:BOOL'       = 'OFF'
    'LAF_BACKEND:STRING'      = 'skia'
    'CMAKE_BUILD_TYPE:STRING' = $env:BUILD_TYPE
}
foreach ($k in $expect.Keys) {
    $needle = $k + '=' + $expect[$k]
    if (-not $cache.Contains($needle)) {
        throw "CMakeCache.txt does not contain '$needle' - configuration is not what was requested."
    }
    Write-Host "cache OK: $needle"
}
if (-not $cache.Contains('CMAKE_GENERATOR:INTERNAL=Ninja')) { throw 'Generator is not Ninja.' }
Write-Host "cache OK: CMAKE_GENERATOR:INTERNAL=Ninja"

$cmakeArgs | ConvertTo-Json -Compress | Set-Content 'cmake-args.json' -Encoding utf8
Add-Content -Path $env:GITHUB_ENV -Value "DUR_configure=$([int]((Get-Date) - $t0).TotalSeconds)"
Add-Content -Path $env:GITHUB_ENV -Value "CL_BANNER=$clBanner"
