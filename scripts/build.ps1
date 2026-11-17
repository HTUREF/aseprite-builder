# 08 Builds only the final aseprite executable target, 4 jobs (runner has 4 vCPU).
$ErrorActionPreference = 'Stop'
$t0 = Get-Date
. ./scripts/msvc-env.ps1
Import-MsvcEnv

$root  = (Get-Location).Path
$build = Join-Path $root 'build'
$jobs = 4
if ($env:BUILD_PARALLEL) { $jobs = [int]$env:BUILD_PARALLEL }
$vcpu = 4
if ($env:RUNNER_VCPU) { $vcpu = [int]$env:RUNNER_VCPU }
if ($jobs -gt $vcpu) {
    Write-Host "Requested -parallel $jobs exceeds $vcpu vCPU; clamping to $vcpu."
    $jobs = $vcpu
}
Write-Host "Runner vCPU: $vcpu  ->  cmake --build --target aseprite --parallel $jobs"

$freeBefore = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host "Free disk before build: $freeBefore GB"

& cmake --build $build --target aseprite --parallel $jobs
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }

$exe = Join-Path $build 'bin/aseprite.exe'
if (-not (Test-Path $exe)) { throw "Build reported success but $exe does not exist." }

$sec = [int]((Get-Date) - $t0).TotalSeconds
$freeAfter = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host ""
Write-Host "Built $exe ($((Get-Item $exe).Length) bytes) in $sec s"
Write-Host "Free disk after build: $freeAfter GB"
Add-Content -Path $env:GITHUB_ENV -Value "DUR_build=$sec"
Add-Content -Path $env:GITHUB_ENV -Value "DISK_FREE_AFTER_BUILD_GB=$freeAfter"
Add-Content -Path $env:GITHUB_ENV -Value "BUILD_JOBS=$jobs"
