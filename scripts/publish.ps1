# 11 Publishes the already-verified ZIP to the PRIVATE output repository.
#    The public repository's GITHUB_TOKEN stays read-only; only this step receives
#    PRIVATE_OUTPUT_TOKEN, and the token is never printed or persisted.
$ErrorActionPreference = 'Stop'
Set-Location $env:GITHUB_WORKSPACE

if (-not $env:PRIVATE_OUTPUT_TOKEN) { throw 'secret PRIVATE_OUTPUT_TOKEN is not configured on this repository.' }
if (-not $env:PRIVATE_OUTPUT_REPO)   { throw 'secret PRIVATE_OUTPUT_REPO is not configured on this repository.' }

$env:GH_TOKEN = $env:PRIVATE_OUTPUT_TOKEN
$env:GH_HOST  = 'github.com'

Write-Host "Target repository: $($env:PRIVATE_OUTPUT_REPO.Substring(0,3))... (masked)"

# Runs a native command and returns its merged output without letting stderr abort
# the script (a native command's stderr merged into the pipeline can raise a
# terminating NativeCommandError under $ErrorActionPreference = 'Stop').
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

# Fail fast if the credential cannot reach the destination repository.
$p1 = Invoke-Native -Exe 'gh' -Arguments @('api', ('repos/' + $env:PRIVATE_OUTPUT_REPO), '--jq', '.full_name + " private=" + (.private|tostring)')
$probe = $p1.Output
if ($p1.ExitCode -ne 0) { throw "PRIVATE_OUTPUT_TOKEN cannot read the output repository: $probe" }
Write-Host "Credential check: OK"

$tag = $env:RELEASE_TAG
$dist = Join-Path $env:GITHUB_WORKSPACE 'dist'
$assets = @(
    (Join-Path $dist 'aseprite-windows-x64.zip'),
    (Join-Path $dist 'build-manifest.json'),
    (Join-Path $dist 'SHA256SUMS.txt')
)
foreach ($a in $assets) { if (-not (Test-Path $a)) { throw "Missing asset: $a" } }

# Refuse to overwrite an existing release: every build gets its own tag.
$existing = Invoke-Native -Exe 'gh' -Arguments @('release', 'view', $tag, '--repo', $env:PRIVATE_OUTPUT_REPO, '--json', 'tagName')
if ($existing.ExitCode -eq 0) { throw "Release $tag already exists - refusing to overwrite." }

Write-Host "Creating private release $tag"
$attempt = 0
$ok = $false
while ($attempt -lt 3 -and -not $ok) {
    $attempt++
    Write-Host "  attempt $attempt of 3"
    & gh release create $tag @assets --repo $env:PRIVATE_OUTPUT_REPO --title ("Aseprite " + $env:ASEPRITE_TAG + " Windows x64 (build " + $env:GITHUB_RUN_NUMBER + ")") --notes-file (Join-Path $dist 'build-notes.md')
    if ($LASTEXITCODE -eq 0) { $ok = $true } else { Start-Sleep -Seconds (10 * $attempt) }
}
if (-not $ok) { throw 'gh release create failed after 3 attempts.' }

# Verify what actually landed in the private release.
$pv = Invoke-Native -Exe 'gh' -Arguments @('release', 'view', $tag, '--repo', $env:PRIVATE_OUTPUT_REPO, '--json', 'tagName,url,assets')
$view = $pv.Output
if ($pv.ExitCode -ne 0) { throw "Could not read back the created release: $view" }
Write-Host "Release JSON: $view"

$rel = $view | ConvertFrom-Json
$expected = @{}
foreach ($a in $assets) { $expected[(Split-Path $a -Leaf)] = (Get-Item $a).Length }
foreach ($name in $expected.Keys) {
    $asset = $rel.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if (-not $asset) { throw "Asset $name is missing from the private release." }
    if ($asset.size -ne $expected[$name]) {
        throw "Asset $name size mismatch: uploaded $($asset.size) vs local $($expected[$name])"
    }
    Write-Host "  verified asset $name ($($asset.size) bytes)"
}

Add-Content -Path $env:GITHUB_ENV -Value "RELEASE_URL=$($rel.url)"
Add-Content -Path $env:GITHUB_ENV -Value "PUBLISHED=true"
Write-Host "Published $($assets.Count) assets to the private repository."
