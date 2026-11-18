# Proves the executable has no hidden dependency outside Windows itself.
#
# This exists because a runtime smoke test is NOT sufficient: the GitHub runner image
# happens to have OpenSSL on PATH, so an exe that imports libcrypto-3-x64.dll started
# fine there and then failed on a clean machine with
#   "libcrypto-3-x64.dll was not found"
# Reading the PE import directory is environment independent and catches that class of
# bug before anything is packaged.

function Get-PeImportedDlls {
    param([Parameter(Mandatory = $true)][string]$ExePath)

    $bytes = [IO.File]::ReadAllBytes($ExePath)
    $e_lfanew = [BitConverter]::ToInt32($bytes, 0x3C)
    $coff = $e_lfanew + 4
    $numSections = [BitConverter]::ToUInt16($bytes, $coff + 2)
    $optSize = [BitConverter]::ToUInt16($bytes, $coff + 16)
    $opt = $coff + 20
    $magic = [BitConverter]::ToUInt16($bytes, $opt)
    if ($magic -eq 0x20B) { $ddOff = $opt + 112 } else { $ddOff = $opt + 96 }
    $importRva = [BitConverter]::ToUInt32($bytes, $ddOff + 8)
    if ($importRva -eq 0) { return @() }

    $sections = @()
    $secOff = $opt + $optSize
    for ($i = 0; $i -lt $numSections; $i++) {
        $s = $secOff + ($i * 40)
        $sections += [pscustomobject]@{
            VirtualSize    = [BitConverter]::ToUInt32($bytes, $s + 8)
            VirtualAddress = [BitConverter]::ToUInt32($bytes, $s + 12)
            RawSize        = [BitConverter]::ToUInt32($bytes, $s + 16)
            RawPtr         = [BitConverter]::ToUInt32($bytes, $s + 20)
        }
    }
    function RvaToOffset([uint32]$rva) {
        foreach ($s in $sections) {
            $span = [Math]::Max($s.VirtualSize, $s.RawSize)
            if ($rva -ge $s.VirtualAddress -and $rva -lt ($s.VirtualAddress + $span)) {
                return [int]($rva - $s.VirtualAddress + $s.RawPtr)
            }
        }
        return -1
    }

    $dlls = @()
    $off = RvaToOffset $importRva
    $i = 0
    while ($true) {
        $d = $off + ($i * 20)
        $nameRva = [BitConverter]::ToUInt32($bytes, $d + 12)
        $firstThunk = [BitConverter]::ToUInt32($bytes, $d + 16)
        if ($nameRva -eq 0 -and $firstThunk -eq 0) { break }
        $nOff = RvaToOffset $nameRva
        $end = $nOff
        while ($bytes[$end] -ne 0) { $end++ }
        $dlls += [Text.Encoding]::ASCII.GetString($bytes, $nOff, $end - $nOff)
        $i++
        if ($i -gt 300) { break }
    }
    return $dlls
}

# DLLs that ship with Windows and are always present on a supported Windows x64 install.
$script:AllowedSystemDlls = @(
    'kernel32.dll','user32.dll','gdi32.dll','comdlg32.dll','ole32.dll','oleaut32.dll',
    'comctl32.dll','dwmapi.dll','msimg32.dll','opengl32.dll','shlwapi.dll','dbghelp.dll',
    'version.dll','wldap32.dll','ws2_32.dll','wsock32.dll','advapi32.dll','crypt32.dll',
    'shell32.dll','uuid.dll','bcrypt.dll','secur32.dll','iphlpapi.dll','winmm.dll',
    'mfplat.dll','msvcrt.dll','ucrtbase.dll','ntdll.dll','userenv.dll','psapi.dll',
    'setupapi.dll','winhttp.dll','wininet.dll','dnsapi.dll','mswsock.dll','normaliz.dll',
    'powrprof.dll','shcore.dll','oleacc.dll','uxtheme.dll','imm32.dll','hid.dll',
    'd3d11.dll','dxgi.dll','dwrite.dll','d2d1.dll','windowscodecs.dll','propsys.dll'
)

function Test-PeImports {
    param(
        [Parameter(Mandatory = $true)][string]$ExePath,
        [string]$SystemRoot = $env:SystemRoot
    )

    $imports = @(Get-PeImportedDlls -ExePath $ExePath)
    $problems = @()
    $report = @()

    foreach ($dll in $imports) {
        $lower = $dll.ToLowerInvariant()
        $isOsPattern = ($lower -match '^(api-ms-win-|ext-ms-win-)')
        $isAllowed = $isOsPattern -or ($script:AllowedSystemDlls -contains $lower)
        $inSystem32 = $false
        if ($SystemRoot) { $inSystem32 = Test-Path (Join-Path $SystemRoot ("System32\" + $dll)) }

        $report += [pscustomobject]@{ Dll = $dll; IsOsPattern = $isOsPattern; Allowed = $isAllowed; InSystem32 = $inSystem32 }
        if (-not $isAllowed) {
            $problems += "$dll is not a Windows system DLL - the build would need it next to aseprite.exe"
        } elseif (-not $inSystem32) {
            $problems += "$dll is not present in %SystemRoot%\System32"
        }
    }

    return [pscustomobject]@{ Imports = $imports; Report = $report; Problems = $problems }
}
