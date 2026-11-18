# 10 Packages the runtime file set through the shared stage builder:
#    aseprite.exe + the whole build/bin/data tree + aseprite.ini (portable mode marker)
#    + aseprite.ico. Aseprite does NOT embed data/ into the exe.
$ErrorActionPreference = 'Stop'
$t0 = Get-Date
Set-Location $env:GITHUB_WORKSPACE
. ./scripts/stage-runtime.ps1

$dist = Join-Path $env:GITHUB_WORKSPACE 'dist'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$stageDir = Join-Path $dist 'stage'
$staged = New-RuntimeStage -Destination $stageDir
$kept = $staged.Files
$keptBytes = ($kept | Measure-Object -Property Length -Sum).Sum

$relPaths = @($kept | ForEach-Object { $_.FullName.Substring($stageDir.Length).TrimStart([char]92, [char]47) })
Write-Host "Packaged $($kept.Count) runtime file(s), $keptBytes bytes uncompressed."
Write-Host "  aseprite.exe : $((Get-Item (Join-Path $stageDir 'aseprite.exe')).Length) bytes"
Write-Host "  aseprite.ini : $((Get-Item (Join-Path $stageDir 'aseprite.ini')).Length) bytes (portable mode marker)"
Write-Host "  aseprite.ico : $((Get-Item (Join-Path $stageDir 'aseprite.ico')).Length) bytes (official app icon)"
foreach ($r in $staged.Required) { Write-Host "  verified: $r" }

# --- zip --------------------------------------------------------------------
$zipName = 'aseprite-windows-x64.zip'
$zipPath = Join-Path $dist $zipName
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
Remove-Item $stageDir -Recurse -Force

$zipItem = Get-Item $zipPath
$zipSha = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLowerInvariant()
Write-Host ""
Write-Host "ZIP       : $($zipItem.Name)"
Write-Host "ZIP size  : $($zipItem.Length) bytes ($([math]::Round($zipItem.Length / 1MB, 2)) MB)"
Write-Host "ZIP sha256: $zipSha"
Set-Content -Path (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii -Value ("$zipSha  $zipName")

# --- manifest ---------------------------------------------------------------
function Get-EnvInt([string]$name) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if (-not $v) { return 0 }
    $n = 0
    if ([int]::TryParse($v, [ref]$n)) { return $n }
    return 0
}

$runnerFacts = [ordered]@{}
$factsPath = Join-Path $env:GITHUB_WORKSPACE 'runner-facts.json'
if (Test-Path $factsPath) {
    $obj = Get-Content $factsPath -Raw | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) { $runnerFacts[$p.Name] = $p.Value }
}
$cmakeArgsParsed = @()
$argsPath = Join-Path $env:GITHUB_WORKSPACE 'cmake-args.json'
if (Test-Path $argsPath) { $cmakeArgsParsed = @(Get-Content $argsPath -Raw | ConvertFrom-Json) }

$releaseTag = 'aseprite-' + $env:ASEPRITE_TAG + '-win64-b' + $env:GITHUB_RUN_NUMBER

$durations = [ordered]@{
    skia_download_sec = Get-EnvInt 'DUR_skia'
    configure_sec     = Get-EnvInt 'DUR_configure'
    build_sec         = Get-EnvInt 'DUR_build'
    verify_sec        = Get-EnvInt 'DUR_verify'
    package_sec       = 0
}
$totalSec = 0
foreach ($k in @($durations.Keys)) { if ($k -ne 'package_sec') { $totalSec += $durations[$k] } }

$manifest = [ordered]@{
    schema          = 1
    artifact        = [ordered]@{
        name           = $zipName
        size_bytes     = $zipItem.Length
        sha256         = $zipSha
        file_count     = $kept.Count
        unpacked_bytes = $keptBytes
        layout         = 'aseprite.exe + aseprite.ini + aseprite.ico + data/ at the archive root'
        files          = $relPaths
    }
    aseprite        = [ordered]@{
        version      = $env:APP_VERSION
        version_text = $env:EXE_VERSION_TEXT
        release_tag  = $env:ASEPRITE_TAG
        commit_sha   = $env:ASEPRITE_SHA
        git_describe = $env:GIT_DESCRIBE
        source       = 'https://github.com/' + $env:ASEPRITE_REPO
        license_note = 'Aseprite source is published under its own EULA; these binaries are for private use only.'
    }
    icon            = [ordered]@{
        file            = 'aseprite.ico'
        sizes           = @('16','20','24','28','32','48','64','128','256')
        source          = 'data/icons/ase.ico at the pinned Aseprite commit (official asset)'
        embedded_in_exe = $true
        embedded_as     = 'ICON resource 0 from src/main/win/resources_win32.rc'
        other_icons     = 'data/icons/doc.ico and data/icons/ext.ico ship alongside for file associations'
    }
    dependency_skia = [ordered]@{
        tag                  = $env:SKIA_TAG
        source               = 'https://github.com/aseprite/skia/releases/download/' + $env:SKIA_TAG + '/' + $env:SKIA_ASSET
        resolved_from        = 'laf/misc/skia-tag.txt at the laf commit pinned by aseprite ' + $env:ASEPRITE_TAG
        archive_size_bytes   = Get-EnvInt 'SKIA_ARCHIVE_SIZE'
        archive_sha256       = $env:SKIA_SHA256
        integrity_verified   = $true
        prebuilt_official    = $true
        compiled_from_source = $false
    }
    build           = [ordered]@{
        os             = 'windows'
        arch           = 'x64'
        gui            = $true
        backend        = 'skia'
        scripting      = 'lua'
        build_type     = $env:BUILD_TYPE
        generator      = 'Ninja'
        compiler       = $env:CL_BANNER
        parallel_jobs  = Get-EnvInt 'BUILD_JOBS'
        cmake_args     = $cmakeArgsParsed
        submodules     = Get-EnvInt 'SUBMODULE_COUNT'
        static_runtime = $true
    }
    runner          = $runnerFacts
    verification    = [ordered]@{
        pe_machine              = $env:PE_MACHINE
        arch_x64                = ($env:PE_MACHINE -eq '0x8664')
        exe_size_bytes          = Get-EnvInt 'EXE_SIZE'
        exe_sha256              = $env:EXE_SHA256
        lua_enabled             = ($env:LUA_ENABLED -eq 'True')
        lua_version             = $env:LUA_VERSION
        app_api_version         = $env:APP_API_VERSION
        version_flag_output     = $env:EXE_VERSION_TEXT
        clean_dir_startup       = $true
        portable_mode           = ($env:PORTABLE_MODE -eq 'True')
        portable_writes_outside = ($env:PORTABLE_WRITES_OUTSIDE -eq 'True')
        no_hidden_dependencies  = $true
        imported_dlls           = (($env:IMPORTED_DLLS -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        gui_smoke               = $env:GUI_SMOKE
        required_resources      = $staged.Required
    }
    runtime_notes   = [ordered]@{
        needs_dlls        = $false
        needs_vc_redist   = $false
        portable_mode     = 'ON by default. The shipped aseprite.ini beside the exe makes App::isPortable() true, so the user folder (aseprite.ini, Aseprite.log, user.aseprite-brushes, palettes/) lives inside the application directory and nothing is written to %APPDATA%. Delete aseprite.ini to fall back to per-user configuration.'
        data_dir_required = 'data/ must stay next to aseprite.exe; the GUI loads fonts and its default theme from there.'
        writable_location = 'Settings live beside the executable, so keep the folder in a writable location (not under Program Files).'
    }
    timings         = $durations
    total_measured_sec = $totalSec
    github          = [ordered]@{
        workflow    = $env:GITHUB_WORKFLOW
        run_id      = $env:GITHUB_RUN_ID
        run_number  = $env:GITHUB_RUN_NUMBER
        run_attempt = $env:GITHUB_RUN_ATTEMPT
        commit_sha  = $env:GITHUB_SHA
        server_url  = $env:GITHUB_SERVER_URL
        run_url     = $env:GITHUB_SERVER_URL + '/' + $env:GITHUB_REPOSITORY + '/actions/runs/' + $env:GITHUB_RUN_ID
        release_tag = $releaseTag
    }
    generated_at    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $dist 'build-manifest.json') -Encoding utf8
Write-Host "Manifest  : build-manifest.json"

# --- release notes ----------------------------------------------------------
$notes = @()
$notes += '# Aseprite Windows x64 build'
$notes += ''
$notes += '| Field | Value |'
$notes += '| --- | --- |'
$notes += '| Aseprite version | ' + $env:APP_VERSION + ' |'
$notes += '| Source tag | ' + $env:ASEPRITE_TAG + ' |'
$notes += '| Source commit SHA | ' + $env:ASEPRITE_SHA + ' |'
$notes += '| Skia | ' + $env:SKIA_TAG + ' (' + $env:SKIA_ASSET + ', official prebuilt) |'
$notes += '| Build type | ' + $env:BUILD_TYPE + ' / Ninja / MSVC x64 / static CRT |'
$notes += '| Lua scripting | ' + $env:LUA_ENABLED + ' (' + $env:LUA_VERSION + ') |'
$notes += '| Runner | windows-2025, ' + $env:RUNNER_VCPU + ' vCPU, ' + $env:RUNNER_RAM_GB + ' GB RAM |'
$notes += '| Compile step | ' + (Get-EnvInt 'DUR_build') + ' s at --parallel ' + (Get-EnvInt 'BUILD_JOBS') + ' |'
$notes += '| ZIP size | ' + $zipItem.Length + ' bytes |'
$notes += '| ZIP SHA-256 | ' + $zipSha + ' |'
$notes += '| Files in ZIP | ' + $kept.Count + ' |'
$notes += '| Portable mode | ' + $env:PORTABLE_MODE + ' - ships aseprite.ini, writes only inside its own folder |'
$notes += '| Icon | aseprite.ico, 9 sizes up to 256x256; also embedded in aseprite.exe |'
$notes += '| Workflow run | ' + $env:GITHUB_SERVER_URL + '/' + $env:GITHUB_REPOSITORY + '/actions/runs/' + $env:GITHUB_RUN_ID + ' |'
$notes += ''
$notes += 'Verified before upload: PE machine 0x8664 (x64); ' + [char]96 + 'aseprite.exe --version' + [char]96 + ' executed;'
$notes += [char]96 + 'aseprite.exe -b --script' + [char]96 + ' ran a Lua probe; required runtime resources present; the packaged'
$notes += 'set started from an isolated directory; and running it produced no files outside that'
$notes += 'directory (portable mode, no %APPDATA% writes).'
$notes += ''
$notes += 'No DLLs and no VC++ redistributable are needed (Skia is static, CRT is /MT).'
Set-Content -Path (Join-Path $dist 'build-notes.md') -Value ($notes -join [Environment]::NewLine) -Encoding utf8

Add-Content -Path $env:GITHUB_ENV -Value "ZIP_PATH=$zipPath"
Add-Content -Path $env:GITHUB_ENV -Value "ZIP_SIZE=$($zipItem.Length)"
Add-Content -Path $env:GITHUB_ENV -Value "ZIP_SHA256=$zipSha"
Add-Content -Path $env:GITHUB_ENV -Value "RELEASE_TAG=$releaseTag"
Add-Content -Path $env:GITHUB_ENV -Value "RUNTIME_FILE_COUNT_PACKAGED=$($kept.Count)"
Add-Content -Path $env:GITHUB_ENV -Value "DUR_package=$([int]((Get-Date) - $t0).TotalSeconds)"
Write-Host ""
Write-Host "Packaging complete."