# Imports the Visual Studio x64 developer environment into the CURRENT process.
# Deliberately avoids rewriting GITHUB_ENV PATH semantics: every script that needs
# the MSVC toolchain dot-sources this file and calls Import-MsvcEnv.
function Import-MsvcEnv {
    param([switch] $Force)

    if ($script:MsvcImported -and -not $Force) { return }

    $vsPath = $env:VS_INSTALL_PATH
    if (-not $vsPath) {
        $vswhere = Join-Path "${env:ProgramFiles(x86)}" 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found: $vswhere" }
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
    }
    if (-not $vsPath) { throw 'Visual Studio with the MSVC x64 toolset was not found.' }

    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found: $vcvars" }

    # Run vcvars64.bat and dump the resulting environment, then apply it here.
    $cmdLine = 'call "' + $vcvars + '" >nul 2>&1 && set'
    $lines = & cmd.exe /d /c $cmdLine
    if ($LASTEXITCODE -ne 0) { throw "vcvars64.bat failed with exit code $LASTEXITCODE" }
    if (-not $lines) { throw 'vcvars64.bat produced no environment output.' }

    $applied = 0
    foreach ($line in $lines) {
        if ($line -notmatch '^([^=]+)=(.*)$') { continue }
        $name = $Matches[1]
        $value = $Matches[2]
        # Never let the Visual Studio environment rewrite these.
        if ($name -in @('USERPROFILE','USERNAME','COMPUTERNAME','HOME','HOMEDRIVE','HOMEPATH','TEMP','TMP','SystemRoot','SystemDrive','windir','GITHUB_ENV','GITHUB_PATH','RUNNER_TOOL_CACHE','RUNNER_TEMP','RUNNER_WORKSPACE')) { continue }
        Set-Item -Path "env:$name" -Value $value -ErrorAction SilentlyContinue
        $applied++
    }
    $script:MsvcImported = $true
    Write-Host "Imported $applied environment variables from: $vcvars"
}
