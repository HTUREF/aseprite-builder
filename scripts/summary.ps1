# 12 Writes a job summary. Runs even after an earlier step failed.
$ErrorActionPreference = 'Continue'
$lines = @()
$lines += '# Aseprite Windows x64 build'
$lines += ''
$lines += '| Field | Value |'
$lines += '| --- | --- |'
$lines += '| Aseprite version | ' + $env:APP_VERSION + ' |'
$lines += '| Source tag / commit | ' + $env:ASEPRITE_TAG + ' / ' + $env:ASEPRITE_SHA + ' |'
$lines += '| Skia | ' + $env:SKIA_TAG + ' |'
$lines += '| Runner | windows-2025, ' + $env:RUNNER_VCPU + ' vCPU, ' + $env:RUNNER_RAM_GB + ' GB RAM |'
$lines += '| PE machine | ' + $env:PE_MACHINE + ' |'
$lines += '| Lua enabled | ' + $env:LUA_ENABLED + ' (' + $env:LUA_VERSION + ') |'
$lines += '| Build seconds | ' + $env:DUR_build + ' |'
$lines += '| ZIP bytes | ' + $env:ZIP_SIZE + ' |'
$lines += '| ZIP SHA-256 | ' + $env:ZIP_SHA256 + ' |'
$lines += '| Private release | ' + $env:RELEASE_URL + ' |'
$lines += '| GUI smoke | ' + $env:GUI_SMOKE + ' |'
$lines += ''
$lines += 'Workflow run: ' + $env:GITHUB_SERVER_URL + '/' + $env:GITHUB_REPOSITORY + '/actions/runs/' + $env:GITHUB_RUN_ID
Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value ($lines -join [Environment]::NewLine)
$lines | ForEach-Object { Write-Host $_ }
