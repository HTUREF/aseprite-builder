# 09 Does not trust the compiler's exit code: proves architecture, version,
#    Lua support and that the binary starts from a clean staging directory.
$ErrorActionPreference = 'Stop'
$t0 = Get-Date
Set-Location $env:GITHUB_WORKSPACE

$exe = Join-Path $env:GITHUB_WORKSPACE 'build/bin/aseprite.exe'
if (-not (Test-Path $exe)) { throw "aseprite.exe not found at $exe" }
$exeItem = Get-Item $exe
Write-Host "EXE       : $($exeItem.FullName)"
Write-Host "EXE size  : $($exeItem.Length) bytes"
$exeSha = (Get-FileHash -Algorithm SHA256 -Path $exe).Hash.ToLowerInvariant()
Write-Host "EXE sha256: $exeSha"

# --- architecture: read the PE header directly -------------------------------
$fs = [System.IO.File]::OpenRead($exe)
try {
    $br = New-Object System.IO.BinaryReader($fs)
    $fs.Position = 0x3C
    $peOffset = $br.ReadInt32()
    $fs.Position = $peOffset
    $sig = $br.ReadUInt32()
    if ($sig -ne 0x00004550) { throw ('Not a valid PE file (signature 0x{0:X8})' -f $sig) }
    $machine = $br.ReadUInt16()
} finally { $fs.Close() }
$machineHex = '0x{0:X4}' -f $machine
Write-Host "PE machine: $machineHex"
if ($machine -ne 0x8664) { throw "Architecture check FAILED: PE machine $machineHex is not x64 (0x8664)" }
Write-Host "Architecture: Windows x64 (AMD64) CONFIRMED"

# --- version / help ----------------------------------------------------------
$versionText = ''
try {
    $versionText = (& $exe --version 2>&1 | Out-String).Trim()
} catch { Write-Host "aseprite.exe --version raised: $_" }
Write-Host "aseprite.exe --version -> '$versionText'"
if (-not $versionText) { Write-Host "NOTE: no stdout captured for --version (GUI subsystem binary)." }

$helpText = ''
try {
    $helpText = (& $exe --help 2>&1 | Out-String)
} catch { Write-Host "aseprite.exe --help raised: $_" }
Write-Host "aseprite.exe --help -> $($helpText.Length) chars captured"
if ($helpText) {
    $helpLines = @($helpText -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 12)
    $helpLines | ForEach-Object { Write-Host "  help| $_" }
}

# --- Lua scripting proof ----------------------------------------------------
# The official Aseprite test suite isolates user config with ASEPRITE_USER_FOLDER;
# do the same so no config is written next to the binary and no first-run UI appears.
$userFolder = Join-Path $env:GITHUB_WORKSPACE 'aseprite-user'
if (Test-Path $userFolder) { Remove-Item $userFolder -Recurse -Force }
New-Item -ItemType Directory -Path $userFolder -Force | Out-Null
$env:ASEPRITE_USER_FOLDER = $userFolder

$luaOut = Join-Path $env:GITHUB_WORKSPACE 'lua-report.txt'
if (Test-Path $luaOut) { Remove-Item $luaOut -Force }
$env:LUA_REPORT = $luaOut
$luaScript = Join-Path $env:GITHUB_WORKSPACE 'scripts/lua-check.lua'
Write-Host ""
Write-Host "Running: aseprite.exe -b --script $luaScript"
$luaStdout = ''
$luaExit = -1
try {
    $luaStdout = (& $exe -b --script $luaScript 2>&1 | Out-String).Trim()
    $luaExit = $LASTEXITCODE
} catch { Write-Host "Lua probe raised: $_" }
Write-Host "exit code: $luaExit"
if ($luaStdout) { Write-Host "stdout: $luaStdout" }

$luaEnabled = $false
$luaVersion = ''
$appVersion = ''
$appApiVersion = ''
if (Test-Path $luaOut) {
    $report = @(Get-Content $luaOut)
    Write-Host "--- lua-report.txt ---"
    $report | ForEach-Object { Write-Host "  $_" }
    $reportText = $report -join ';'
    if ($reportText.Contains('scripts_enabled=1') -and $reportText.Contains('lua_script_executed=1')) {
        $luaEnabled = $true
        foreach ($line in $report) {
            if ($line -match '^lua_version=(.*)$')     { $luaVersion = $Matches[1] }
            if ($line -match '^app_version=(.*)$')     { $appVersion = $Matches[1] }
            if ($line -match '^app_api_version=(.*)$') { $appApiVersion = $Matches[1] }
        }
    }
}
if (-not $luaEnabled) {
    throw 'Lua scripting check FAILED: -b --script did not execute the probe (lua-report.txt missing or incomplete).'
}
Write-Host "Lua scripting: ENABLED (interpreter $luaVersion, app.version $appVersion, app.apiVersion $appApiVersion)"

# --- clean staging directory startup ---------------------------------------
Write-Host ""
$binDir = Join-Path $env:GITHUB_WORKSPACE 'build/bin'
$stage = Join-Path $env:GITHUB_WORKSPACE 'stage-clean'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }

# Aseprite does not embed data/: the GUI loads fonts and the default theme from
# <exe dir>/data at runtime, so the staged set must be aseprite.exe + the data tree.
$dataDir = Join-Path $binDir 'data'
if (-not (Test-Path $dataDir)) { throw 'build/bin/data is missing - the GUI could not load fonts or its theme.' }
$requiredResources = @(
    'data/fonts/fonts.xml',
    'data/extensions/aseprite-theme/package.json',
    'data/extensions/aseprite-theme/theme.xml',
    'data/extensions/aseprite-theme/sheet.png',
    'data/EULA.txt'
)
foreach ($r in $requiredResources) {
    if (-not (Test-Path (Join-Path $binDir $r))) { throw "Required runtime resource missing from the build output: $r" }
    Write-Host "resource OK: $r"
}

New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item (Join-Path $binDir 'aseprite.exe') (Join-Path $stage 'aseprite.exe') -Force
Copy-Item $dataDir (Join-Path $stage 'data') -Recurse -Force
$runtimeFiles = @(Get-ChildItem $stage -Recurse -File)
Write-Host "Staged $($runtimeFiles.Count) runtime file(s) (aseprite.exe + the whole data/ tree) into a clean directory."

$cleanOut = Join-Path $stage 'startup-report.txt'
$env:LUA_REPORT = $cleanOut
$cleanUser = Join-Path $env:GITHUB_WORKSPACE 'aseprite-user-clean'
if (Test-Path $cleanUser) { Remove-Item $cleanUser -Recurse -Force }
New-Item -ItemType Directory -Path $cleanUser -Force | Out-Null
$env:ASEPRITE_USER_FOLDER = $cleanUser
Push-Location $stage
try {
    $cleanStdout = (& (Join-Path $stage 'aseprite.exe') -b --script $luaScript 2>&1 | Out-String).Trim()
    $cleanExit = $LASTEXITCODE
} finally { Pop-Location }
Write-Host "Clean-directory run exit code: $cleanExit"
if ($cleanStdout) { Write-Host "Clean-directory stdout: $cleanStdout" }
if (-not (Test-Path $cleanOut)) {
    throw 'Clean-directory startup FAILED: the binary could not run outside the build tree (missing runtime dependency?).'
}
Write-Host "Clean-directory startup: PASSED (runs from an isolated directory holding only packaged files)"

# --- GUI smoke launch (informational; headless runners may refuse) ---------
Write-Host ""
$guiResult = 'not-attempted'
$guiOut = Join-Path $env:GITHUB_WORKSPACE 'gui-launch.out.txt'
$guiErr = Join-Path $env:GITHUB_WORKSPACE 'gui-launch.err.txt'
try {
    $p = Start-Process -FilePath (Join-Path $stage 'aseprite.exe') -PassThru -RedirectStandardOutput $guiOut -RedirectStandardError $guiErr -ErrorAction Stop
    Start-Sleep -Seconds 12
    if ($p.HasExited) {
        $guiResult = 'process-exited-code-' + $p.ExitCode
        $guiText = ''
        foreach ($f in @($guiOut, $guiErr)) { if (Test-Path $f) { $guiText += (Get-Content $f -Raw) } }
        if ($guiText) { Write-Host "GUI output: $guiText" }
        # A missing data/ tree shows up here as a resource-loading error; a headless
        # session shows up as a window/display error and must not fail the build.
        if ($guiText -match 'not found|No such file|fonts\.xml|theme\.xml|sheet\.png|package\.json') {
            throw "GUI smoke FAILED: the packaged binary could not load its runtime resources. Output: $guiText"
        }
        Write-Host "GUI launch: process exited after the 12s probe -> $guiResult (no missing-resource error)"
    } else {
        $guiResult = 'launched-and-stayed-running'
        Write-Host "GUI launch: process still alive after 12s -> UI initialised"
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
} catch {
    $guiResult = 'blocked-by-session'
    Write-Host "GUI launch not possible in this session: $_"
}

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Add-Content -Path $env:GITHUB_ENV -Value "EXE_SHA256=$exeSha"
Add-Content -Path $env:GITHUB_ENV -Value "EXE_SIZE=$($exeItem.Length)"
Add-Content -Path $env:GITHUB_ENV -Value ("EXE_VERSION_TEXT=" + ($versionText -replace '\r?\n',' '))
Add-Content -Path $env:GITHUB_ENV -Value "APP_VERSION=$appVersion"
Add-Content -Path $env:GITHUB_ENV -Value "APP_API_VERSION=$appApiVersion"
Add-Content -Path $env:GITHUB_ENV -Value "LUA_VERSION=$luaVersion"
Add-Content -Path $env:GITHUB_ENV -Value "LUA_ENABLED=$luaEnabled"
Add-Content -Path $env:GITHUB_ENV -Value "GUI_SMOKE=$guiResult"
Add-Content -Path $env:GITHUB_ENV -Value "PE_MACHINE=$machineHex"
Add-Content -Path $env:GITHUB_ENV -Value "RUNTIME_FILE_COUNT=$($runtimeFiles.Count)"
Add-Content -Path $env:GITHUB_ENV -Value "DUR_verify=$([int]((Get-Date) - $t0).TotalSeconds)"
Write-Host ""
Write-Host "All binary verification checks passed."
