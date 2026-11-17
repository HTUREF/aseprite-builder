# 02b Conditional disk reclaim. Only runs when free space is low.
$ErrorActionPreference = 'SilentlyContinue'
$freeGb = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host "Free space before reclaim: $freeGb GB"
if ($freeGb -ge 20) {
  Write-Host "Enough free space ($freeGb GB >= 20 GB), nothing to remove."
  exit 0
}
Write-Host "Free space below 20 GB -> removing caches and preinstalled tooling that this build does not use."

# Explicitly NOT touched: Visual Studio, Windows SDK, MSVC, CMake, Ninja, Git, MSYS2/git bash.
$targets = @(
  'C:\Android',
  'C:\Program Files\Android',
  'C:\ProgramData\Android',
  'C:\Program Files\Microsoft\Android Studio',
  'C:\hostedtoolcache\windows\Java',
  'C:\hostedtoolcache\windows\Android',
  'C:\hostedtoolcache\windows\Ruby'
)
foreach ($t in $targets) {
  if (Test-Path $t) {
    $before = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
    Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
    $after = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
    Write-Host ("removed {0} -> freed {1} GB" -f $t, [math]::Round($after - $before, 2))
  }
}

if (Get-Command docker -ErrorAction SilentlyContinue) {
  $before = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
  docker system prune -a -f 2>&1 | Out-Null
  $after = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
  Write-Host ("docker prune -> freed {0} GB" -f [math]::Round($after - $before, 2))
}

Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$final = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host "Free space after reclaim: $final GB"
Add-Content -Path $env:GITHUB_ENV -Value "DISK_FREE_AFTER_CLEANUP_GB=$final"
