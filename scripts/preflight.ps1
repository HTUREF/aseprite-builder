# 02 Preflight: report runner facts and reclaim disk if needed.
# Never removes Visual Studio, Windows SDK, CMake, Ninja or Git.
$ErrorActionPreference = 'Stop'

Write-Host "=== Runner ==="
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$os  = Get-CimInstance Win32_OperatingSystem
$vcpu = $cs.NumberOfLogicalProcessors
$ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$cpus = @($cpu.Name)[0]

Write-Host "ImageOS        : $env:ImageOS"
Write-Host "ImageVersion   : $env:ImageVersion"
Write-Host "OS             : $($os.Caption) build $($os.BuildNumber)"
Write-Host "CPU            : $cpus"
Write-Host "vCPU (logical) : $vcpu"
Write-Host "RAM            : $ramGb GB"
Write-Host "Runner label   : windows-2025"

$drive = Get-PSDrive C
$totalGb = [math]::Round(($drive.Used + $drive.Free) / 1GB, 1)
$freeGb  = [math]::Round($drive.Free / 1GB, 1)
Write-Host "Disk C:        : $totalGb GB total, $freeGb GB free"

Write-Host ""
Write-Host "=== Toolchain (must already be present, never installed) ==="
$tools = [ordered]@{}
foreach ($t in @('git','cmake','ninja','curl','gh','7z')) {
  $c = Get-Command $t -ErrorAction SilentlyContinue
  if ($c) {
    $v = switch ($t) {
      'git'   { (git --version) }
      'cmake' { (cmake --version | Select-Object -First 1) }
      'ninja' { (ninja --version) }
      'curl'  { (curl --version | Select-Object -First 1) }
      'gh'    { (gh --version | Select-Object -First 1) }
      default { 'present' }
    }
    $tools[$t] = "$v @ $($c.Source)"
  } else {
    $tools[$t] = 'MISSING'
  }
}
$tools.GetEnumerator() | ForEach-Object { Write-Host ("{0,-6} : {1}" -f $_.Key, $_.Value) }

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found: $vswhere" }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
if (-not $vsPath) { throw 'No Visual Studio installation with the MSVC x64 C++ toolset was found.' }
$vcvars64 = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars64)) { throw "vcvars64.bat not found: $vcvars64" }
Write-Host "Visual Studio : $vsPath"

$sdkRoot = Join-Path "${env:ProgramFiles(x86)}" 'Windows Kits\10\Include'
$sdkVersions = if (Test-Path $sdkRoot) { (Get-ChildItem $sdkRoot -Directory | Select-Object -ExpandProperty Name) -join ', ' } else { 'UNKNOWN' }
Write-Host "Windows SDK   : $sdkVersions"

Add-Content -Path $env:GITHUB_ENV -Value "RUNNER_VCPU=$vcpu"
Add-Content -Path $env:GITHUB_ENV -Value "RUNNER_RAM_GB=$ramGb"
Add-Content -Path $env:GITHUB_ENV -Value "RUNNER_CPU=$cpus"
Add-Content -Path $env:GITHUB_ENV -Value "DISK_TOTAL_GB=$totalGb"
Add-Content -Path $env:GITHUB_ENV -Value "DISK_FREE_BEFORE_GB=$freeGb"
Add-Content -Path $env:GITHUB_ENV -Value "VS_INSTALL_PATH=$vsPath"

# Record the machine-readable facts for the manifest.
$facts = [ordered]@{
  runner_label   = 'windows-2025'
  image_os       = $env:ImageOS
  image_version  = $env:ImageVersion
  os_caption     = $os.Caption
  os_build       = $os.BuildNumber
  cpu            = $cpus
  vcpu_logical   = $vcpu
  ram_gb         = $ramGb
  disk_total_gb  = $totalGb
  disk_free_gb   = $freeGb
  visual_studio  = $vsPath
  windows_sdk    = $sdkVersions
  toolchain      = $tools
}
$facts | ConvertTo-Json -Depth 5 | Set-Content -Path 'runner-facts.json' -Encoding utf8
Write-Host ""
Write-Host "Wrote runner-facts.json"
