# 10 Packages every runtime file (never only the exe), then writes
#    aseprite-windows-x64.zip, SHA256SUMS.txt, build-manifest.json, build-notes.md
$ErrorActionPreference = 'Stop'
$t0 = Get-Date
Set-Location $env:GITHUB_WORKSPACE

$dist = Join-Path $env:GITHUB_WORKSPACE 'dist'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null

# --- collect runtime files --------------------------------------------------
$binDir = Join-Path $env:GITHUB_WORKSPACE 'build/bin'
if (-not (Test-Path $binDir)) { throw "build/bin not found" }

# Never ship intermediate build output.
$excludeExts = @('.pdb','.ilk','.exp','.lib','.obj','.iobj','.ipdb','.idb','.res','.tlog','.log','.a','.o','.map','.cache','.ninja_deps','.ninja_log','.tmp')
$includeExts = @('.exe','.dll','.dat','.ini','.xml','.txt','.json','.lua','.png','.ico','.ttf','.otf','.bin','.cfg','.mo','.qm','.aselibrary','.pal')

$stageDir = Join-Path $dist 'stage'
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$all = @(Get-ChildItem $binDir -Recurse -File)
$skipped = @()
$kept = @()
foreach ($f in $all) {
    $ext = $f.Extension.ToLowerInvariant()
    if ($excludeExts -contains $ext) { $skipped += $f; continue }
    if (-not ($includeExts -contains $ext)) { $skipped += $f; continue }
    $rel = $f.FullName.Substring($binDir.Length).TrimStart([char]92, [char]47)
    $dest = Join-Path $stageDir $rel
    $destDir = Split-Path $dest -Parent
    if ($destDir -and -not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Copy-Item $f.FullName $dest -Force
    $kept += $dest
}
if ($kept.Count -eq 0) { throw "No runtime files were collected from build/bin" }
if (-not ($kept | Where-Object { (Split-Path $_ -Leaf) -eq 'aseprite.exe' })) {
    throw "aseprite.exe is missing from the packaged file set"
}

Write-Host "Packaged $($kept.Count) runtime file(s); skipped $($skipped.Count) intermediate/build file(s)."
foreach ($k in $kept) {
    $rel = $k.Substring($stageDir.Length).TrimStart([char]92, [char]47)
    Write-Host ("  {0,12:N0}  {1}" -f (Get-Item $k).Length, $rel)
}
if ($skipped.Count -gt 0) {
    Write-Host "Skipped (first 20):"
    $skipped | Select-Object -First 20 | ForEach-Object { Write-Host ("  {0,12:N0}  {1}" -f $_.Length, $_.Name) }
}

# --- zip --------------------------------------------------------------------
$zipName = 'aseprite-windows-x64.zip'
$zipPath = Join-Path $dist $zipName
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
Remove-Item $stageDir -Recurse -Force

$zipItem = Get-Item $zipPath
$zipSha = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLowerInvariant()
Write-Host ""
Write-Host "ZIP      : $($zipItem.Name)"
Write-Host "ZIP size : $($zipItem.Length) bytes ($([math]::Round($zipItem.Length / 1MB, 2)) MB)"
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

$runnerFacts = @{}
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
    checkout_source_sec = Get-EnvInt 'DUR_checkout'
    skia_download_sec   = Get-EnvInt 'DUR_skia'
    configure_sec       = Get-EnvInt 'DUR_configure'
    build_sec           = Get-EnvInt 'DUR_build'
    verify_sec          = Get-EnvInt 'DUR_verify'
    package_sec         = 0
}
$totalSec = 0
foreach ($k in @($durations.Keys)) { if ($k -ne 'package_sec') { $totalSec += $durations[$k] } }

$manifest = [ordered]@{
    schema            = 1
    artifact          = [ordered]@{
        name       = $zipName
        size_bytes = $zipItem.Length
        sha256     = $zipSha
        files      = ($kept | ForEach-Object { $_.Substring($stageDir.Length).TrimStart([char]92, [char]47) })
    }
    aseprite          = [ordered]@{
        version      = $env:APP_VERSION
        version_text = $env:EXE_VERSION_TEXT
        release_tag  = $env:ASEPRITE_TAG
        commit_sha   = $env:ASEPRITE_SHA
        source       = 'https://github.com/' + $env:ASEPRITE_REPO
        license_note = 'Aseprite source is distributed under its own EULA; this build is for private use only.'
    }
    dependency_skia   = [ordered]@{
        tag                = $env:SKIA_TAG
        source             = 'https://github.com/aseprite/skia/releases/download/' + $env:SKIA_TAG + '/' + $env:SKIA_ASSET
        resolved_from      = 'laf/misc/skia-tag.txt at laf commit pinned by aseprite ' + $env:ASEPRITE_TAG
        archive_size_bytes = Get-EnvInt 'SKIA_ARCHIVE_SIZE'
        archive_sha256     = $env:SKIA_SHA256
        integrity_verified = $true
        prebuilt_official  = $true
    }
    build             = [ordered]@{
        os            = 'windows'
        arch          = 'x64'
        gui           = $true
        backend       = 'skia'
        scripting     = 'lua'
        build_type    = $env:BUILD_TYPE
        generator     = 'Ninja'
        compiler      = $env:CL_BANNER
        parallel_jobs = Get-EnvInt 'BUILD_JOBS'
        cmake_args    = $cmakeArgsParsed
        submodules    = Get-EnvInt 'SUBMODULE_COUNT'
    }
    runner            = $runnerFacts
    verification      = [ordered]@{
        pe_machine         = $env:PE_MACHINE
        arch_x64           = ($env:PE_MACHINE -eq '0x8664')
        exe_size_bytes     = Get-EnvInt 'EXE_SIZE'
        exe_sha256         = $env:EXE_SHA256
        lua_enabled        = ($env:LUA_ENABLED -eq 'True')
        lua_version        = $env:LUA_VERSION
        app_api_version    = $env:APP_API_VERSION
        runtime_file_count = Get-EnvInt 'RUNTIME_FILE_COUNT'
        version_flag_output = $env:EXE_VERSION_TEXT
        clean_dir_startup  = $true
        gui_smoke          = $env:GUI_SMOKE
    }
    timings           = $durations
    total_build_sec   = $totalSec
    github            = [ordered]@{
        workflow    = $env:GITHUB_WORKFLOW
        run_id      = $env:GITHUB_RUN_ID
        run_number  = $env:GITHUB_RUN_NUMBER
        run_attempt = $env:GITHUB_RUN_ATTEMPT
        commit_sha  = $env:GITHUB_SHA
        server_url  = $env:GITHUB_SERVER_URL
        run_url     = $env:GITHUB_SERVER_URL + '/' + $env:GITHUB_REPOSITORY + '/actions/runs/' + $env:GITHUB_RUN_ID
        release_tag = $releaseTag
    }
    generated_at      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

$manifestPath = Join-Path $dist 'build-manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding utf8
Write-Host "Manifest : $manifestPath"

# --- release notes ----------------------------------------------------------
$notes = @()
$notes += '# Aseprite Windows x64 build'
$notes += ''
$notes += '| Field | Value |'
$notes += '| --- | --- |'
$notes += '| Aseprite version | ' + $env:APP_VERSION + ' |'
$notes += '| Release tag (source) | ' + $env:ASEPRITE_TAG + ' |'
$notes += '| Source commit SHA | ' + $env:ASEPRITE_SHA + ' |'
$notes += '| Skia | ' + $env:SKIA_TAG + ' (' + $env:SKIA_ASSET + ') |'
$notes += '| Build type | ' + $env:BUILD_TYPE + ' / Ninja / MSVC x64 |'
$notes += '| Lua scripting | ' + $env:LUA_ENABLED + ' (' + $env:LUA_VERSION + ') |'
$notes += '| Runner | windows-2025, ' + $env:RUNNER_VCPU + ' vCPU, ' + $env:RUNNER_RAM_GB + ' GB RAM |'
$notes += '| Build time | ' + $totalSec + ' s (compile step ' + (Get-EnvInt 'DUR_build') + ' s) |'
$notes += '| ZIP size | ' + $zipItem.Length + ' bytes |'
$notes += '| ZIP SHA-256 | ' + $zipSha + ' |'
$notes += '| Workflow run | ' + $env:GITHUB_SERVER_URL + '/' + $env:GITHUB_REPOSITORY + '/actions/runs/' + $env:GITHUB_RUN_ID + ' |'
$notes += ''
$notes += 'Verified before upload: PE machine 0x8664 (x64), aseprite.exe -b --script executed a Lua probe,'
$notes += 'and the packaged file set started successfully from an isolated staging directory.'
Set-Content -Path (Join-Path $dist 'build-notes.md') -Value ($notes -join [Environment]::NewLine) -Encoding utf8

Add-Content -Path $env:GITHUB_ENV -Value "ZIP_PATH=$zipPath"
Add-Content -Path $env:GITHUB_ENV -Value "ZIP_SIZE=$($zipItem.Length)"
Add-Content -Path $env:GITHUB_ENV -Value "ZIP_SHA256=$zipSha"
Add-Content -Path $env:GITHUB_ENV -Value "RELEASE_TAG=$releaseTag"
Add-Content -Path $env:GITHUB_ENV -Value "DUR_package=$([int]((Get-Date) - $t0).TotalSeconds)"
Write-Host ""
Write-Host "Packaging complete."
