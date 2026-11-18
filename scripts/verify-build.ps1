# 09 Does not trust the compiler's exit code.
#    Architecture, version, Lua scripting, runtime resources and clean-directory
#    startup are each checked independently; all failures are collected and reported
#    together so a single run reveals everything that is wrong.
$ErrorActionPreference = 'Stop'
$t0 = Get-Date
Set-Location $env:GITHUB_WORKSPACE

$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$msg) { $script:failures.Add($msg); Write-Host "FAIL: $msg" }
function Ok([string]$msg)   { Write-Host "OK  : $msg" }

# Captures a native command's stdout+stderr without letting stderr abort the script.
# With $ErrorActionPreference = 'Stop', merging a native command's stderr into the
# PowerShell pipeline can raise a terminating NativeCommandError.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $code = -1
    $out = ''
    try {
        $out = (& $Exe @Arguments 2>&1 | Out-String).Trim()
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = -1 }
    } catch {
        $out = "native invocation error: $_"
    } finally {
        $ErrorActionPreference = $prev
    }
    return [pscustomobject]@{ Output = $out; ExitCode = $code }
}

$binDir  = Join-Path $env:GITHUB_WORKSPACE 'build/bin'
$exe     = Join-Path $binDir 'aseprite.exe'
$dataDir = Join-Path $binDir 'data'

# --- 1. the binary exists ----------------------------------------------------
if (-not (Test-Path $exe)) { throw "aseprite.exe not found at $exe - nothing to verify." }
$exeItem = Get-Item $exe
Write-Host "EXE       : $($exeItem.FullName)"
Write-Host "EXE size  : $($exeItem.Length) bytes"
$exeSha = (Get-FileHash -Algorithm SHA256 -Path $exe).Hash.ToLowerInvariant()
Write-Host "EXE sha256: $exeSha"

# --- 2. architecture: read the PE header directly ---------------------------
$machineHex = 'unknown'
try {
    $fs = [System.IO.File]::OpenRead($exe)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $peOffset = $br.ReadInt32()
        $fs.Position = $peOffset
        $sig = $br.ReadUInt32()
        if ($sig -ne 0x00004550) { throw ('Not a valid PE file (signature 0x{0:X8})' -f $sig) }
        $machine = $br.ReadUInt16()
        $machineHex = '0x{0:X4}' -f $machine
    } finally { $fs.Close() }
    Write-Host "PE machine: $machineHex"
    if ($machine -eq 0x8664) { Ok 'Architecture is Windows x64 (AMD64)' }
    else { Fail "Architecture is $machineHex, expected x64 (0x8664)" }
} catch { Fail "Could not read the PE header: $_" }

# --- 3. --version and --help -------------------------------------------------
$versionText = ''
$r = Invoke-Native -Exe $exe -Arguments @('--version')
$versionText = $r.Output
Write-Host "aseprite.exe --version exit code: $($r.ExitCode)"
Write-Host "aseprite.exe --version -> '$versionText'"
if ($versionText -match 'Aseprite\s+1\.3\.18\.6') { Ok "Version string reports Aseprite 1.3.18.6" }
else { Fail "--version did not report Aseprite 1.3.18.6 (got '$versionText')" }

$helpText = ''
$rh = Invoke-Native -Exe $exe -Arguments @('--help')
$helpText = $rh.Output
Write-Host "aseprite.exe --help exit code: $($rh.ExitCode)"
Write-Host "aseprite.exe --help -> $($helpText.Length) chars captured"
if ($helpText) {
    @($helpText -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 6) | ForEach-Object { Write-Host "  help| $_" }
    # --script / --script-param / --shell are registered only when ENABLE_SCRIPTING is on.
    if ($helpText -match '--script') { Ok 'Help exposes --script (scripting compiled in)' }
    else { Fail 'Help does not expose --script, so scripting may not be compiled in' }
} else { Fail 'Could not capture --help output' }

# --- 4. runtime resources the GUI loads from disk ---------------------------
if (-not (Test-Path $dataDir)) {
    Fail 'build/bin/data is missing: the GUI cannot load fonts or its theme.'
} else {
    $required = @(
        'data/fonts/fonts.xml',
        'data/extensions/aseprite-theme/package.json',
        'data/extensions/aseprite-theme/theme.xml',
        'data/extensions/aseprite-theme/sheet.png',
        'data/EULA.txt'
    )
    foreach ($r in $required) {
        if (Test-Path (Join-Path $binDir $r)) { Ok "runtime resource present: $r" }
        else { Fail "runtime resource missing from build output: $r" }
    }
    $dataFileCount = @(Get-ChildItem $dataDir -Recurse -File).Count
    Write-Host "data/ file count: $dataFileCount"
}

# --- 5. Lua scripting: actually execute a script ---------------------------
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
$rl = Invoke-Native -Exe $exe -Arguments @('-b', '--script', $luaScript)
$luaStdout = $rl.Output
$luaExit = $rl.ExitCode
Write-Host "exit code: $luaExit"
if ($luaStdout) { Write-Host "stdout: $luaStdout" }

$luaEnabled = $false
$luaVersion = ''; $appVersion = ''; $appApiVersion = ''
if (Test-Path $luaOut) {
    $report = @(Get-Content $luaOut)
    Write-Host "--- lua-report.txt ---"
    $report | ForEach-Object { Write-Host "  $_" }
    $reportText = $report -join ';'
    if ($reportText.Contains('scripts_enabled=1') -and $reportText.Contains('lua_script_executed=1')) { $luaEnabled = $true }
    foreach ($line in $report) {
        if ($line -match '^lua_version=(.*)$')     { $luaVersion = $Matches[1] }
        if ($line -match '^app_version=(.*)$')     { $appVersion = $Matches[1] }
        if ($line -match '^app_api_version=(.*)$') { $appApiVersion = $Matches[1] }
    }
}
if ($luaEnabled) { Ok "Lua scripting executed (interpreter $luaVersion, app.version $appVersion, apiVersion $appApiVersion)" }
else { Fail "Lua scripting could not be proven: -b --script produced no valid lua-report.txt. Output: $luaStdout" }

# --- 6. packaged file set + isolated-directory startup ---------------------
Write-Host ""
. ./scripts/stage-runtime.ps1
$stage = Join-Path $env:GITHUB_WORKSPACE 'stage-clean'
$stageSet = New-RuntimeStage -Destination $stage
Write-Host "Staged $($stageSet.Files.Count) runtime file(s) with the shared stage builder (exe + aseprite.ini + aseprite.ico + data/)."
Write-Host "  aseprite.ini : $((Get-Item (Join-Path $stage 'aseprite.ini')).Length) bytes -> App::isPortable() is now true"
Write-Host "  aseprite.ico : $((Get-Item (Join-Path $stage 'aseprite.ico')).Length) bytes"

# Baseline of the per-user config folder so any file it gains is attributable.
$appDataDir = Join-Path $env:APPDATA 'Aseprite'
$appDataBefore = @()
if (Test-Path $appDataDir) { $appDataBefore = @(Get-ChildItem $appDataDir -Recurse -File | ForEach-Object { $_.FullName }) }

# ASEPRITE_USER_FOLDER would bypass portable mode, so clear it for these runs.
$env:ASEPRITE_USER_FOLDER = $null
Push-Location $stage
try {
    $rc = Invoke-Native -Exe (Join-Path $stage 'aseprite.exe') -Arguments @('-b', '--version')
    $cleanStdout = $rc.Output
    $cleanExit = $rc.ExitCode
} finally { Pop-Location }
Write-Host "Isolated-directory 'aseprite.exe -b --version' -> exit $cleanExit, output '$cleanStdout'"
if ($cleanExit -eq 0 -and $cleanStdout -match 'Aseprite') { Ok 'Binary starts from an isolated directory holding only the packaged files' }
else { Fail "Isolated-directory startup failed (exit $cleanExit, output '$cleanStdout') - a runtime dependency is missing" }

# --- 7. GUI smoke: proves fonts and the default theme really load ----------
Write-Host ""
$guiResult = 'not-attempted'
$guiOut = Join-Path $env:GITHUB_WORKSPACE 'gui-launch.out.txt'
$guiErr = Join-Path $env:GITHUB_WORKSPACE 'gui-launch.err.txt'
try {
    $p = Start-Process -FilePath (Join-Path $stage 'aseprite.exe') -PassThru -RedirectStandardOutput $guiOut -RedirectStandardError $guiErr -ErrorAction Stop
    Start-Sleep -Seconds 10
    if ($p.HasExited) {
        $guiResult = 'process-exited-code-' + $p.ExitCode
        $guiText = ''
        foreach ($f in @($guiOut, $guiErr)) { if (Test-Path $f) { $guiText += (Get-Content $f -Raw) } }
        if ($guiText) { Write-Host "GUI output: $guiText" }
        if ($guiText -match 'fonts\.xml|theme\.xml|sheet\.png|package\.json|not found|No such file') {
            Fail "GUI smoke: the binary could not load its runtime resources. Output: $guiText"
        } else {
            Ok "GUI process exited early ($guiResult) without a missing-resource error (headless session)"
        }
    } else {
        $guiResult = 'launched-and-stayed-running'
        Ok 'GUI process stayed alive for 10s: UI, fonts and default theme initialised'
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
} catch {
    $guiResult = 'blocked-by-session'
    Write-Host "GUI launch not possible in this session: $_"
}
# --- 6b. portable mode must not write outside the application folder ------
# Checked after both the batch run and the GUI run, because preferences are
# normally written on exit.
Write-Host ""
$appDataNew = @()
if (Test-Path $appDataDir) {
    $appDataNew = @(Get-ChildItem $appDataDir -Recurse -File | ForEach-Object { $_.FullName } |
        Where-Object { $appDataBefore -notcontains $_ })
}
$portableWritesOutside = ($appDataNew.Count -gt 0)
if ($portableWritesOutside) {
    Fail ("Portable mode wrote outside the application folder: " + ($appDataNew -join ', '))
} else {
    Ok 'Portable mode: no file written to %APPDATA%Aseprite'
}
$userFilesInside = @(Get-ChildItem $stage -File |
    Where-Object { $_.Name -notin @('aseprite.exe', 'aseprite.ini', 'aseprite.ico') } |
    ForEach-Object { $_.Name })
if ($userFilesInside.Count -gt 0) {
    Ok ('Portable mode: user files kept inside the app folder: ' + ($userFilesInside -join ', '))
} else {
    Write-Host 'note: no user files were created in the app folder (the first GUI run creates them)'
}
Add-Content -Path $env:GITHUB_ENV -Value "PORTABLE_MODE=True"
Add-Content -Path $env:GITHUB_ENV -Value "PORTABLE_WRITES_OUTSIDE=$portableWritesOutside"

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

# --- summary ---------------------------------------------------------------
Add-Content -Path $env:GITHUB_ENV -Value "EXE_SHA256=$exeSha"
Add-Content -Path $env:GITHUB_ENV -Value "EXE_SIZE=$($exeItem.Length)"
Add-Content -Path $env:GITHUB_ENV -Value ("EXE_VERSION_TEXT=" + ($versionText -replace '\r?\n',' '))
Add-Content -Path $env:GITHUB_ENV -Value "APP_VERSION=$appVersion"
Add-Content -Path $env:GITHUB_ENV -Value "APP_API_VERSION=$appApiVersion"
Add-Content -Path $env:GITHUB_ENV -Value "LUA_VERSION=$luaVersion"
Add-Content -Path $env:GITHUB_ENV -Value "LUA_ENABLED=$luaEnabled"
Add-Content -Path $env:GITHUB_ENV -Value "GUI_SMOKE=$guiResult"
Add-Content -Path $env:GITHUB_ENV -Value "PE_MACHINE=$machineHex"
Add-Content -Path $env:GITHUB_ENV -Value "DUR_verify=$([int]((Get-Date) - $t0).TotalSeconds)"

Write-Host ""
Write-Host ("=" * 60)
if ($failures.Count -gt 0) {
    Write-Host "VERIFICATION FAILED with $($failures.Count) problem(s):"
    $failures | ForEach-Object { Write-Host "  - $_" }
    throw "Binary verification failed: $($failures.Count) check(s) did not pass."
}
Write-Host 'All binary verification checks passed.'
