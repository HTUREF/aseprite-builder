# 02b Fail-fast probe of the private output credential.
# Runs BEFORE the ~25 minute compile so a wrong token costs a minute, not a build.
# Creates a throwaway DRAFT release and deletes it again to prove real write access.
$ErrorActionPreference = 'Stop'

if (-not $env:PRIVATE_OUTPUT_TOKEN) { throw 'secret PRIVATE_OUTPUT_TOKEN is not configured on this repository.' }
if (-not $env:PRIVATE_OUTPUT_REPO)   { throw 'secret PRIVATE_OUTPUT_REPO is not configured on this repository.' }

$env:GH_TOKEN = $env:PRIVATE_OUTPUT_TOKEN
$env:GH_HOST  = 'github.com'

$info = & gh api ("repos/" + $env:PRIVATE_OUTPUT_REPO) --jq '.full_name + " | private=" + (.private|tostring) + " | push=" + (.permissions.push|tostring)' 2>&1
if ($LASTEXITCODE -ne 0) { throw "PRIVATE_OUTPUT_TOKEN cannot read the output repository: $info" }
Write-Host "Output repository: $info"
if ("$info" -notmatch 'private=true') { throw 'The output repository is not private - aborting before any artifact is produced.' }
if ("$info" -notmatch 'push=True') { Write-Host 'WARNING: the API does not report push permission; the draft-release probe below is the real test.' }

$probeTag = 'credential-probe-run-' + $env:GITHUB_RUN_ID + '-' + $env:GITHUB_RUN_ATTEMPT
Write-Host "Creating temporary draft release $probeTag to prove write access..."
& gh release create $probeTag --repo $env:PRIVATE_OUTPUT_REPO --draft --title 'credential probe' --notes 'Temporary probe release; deleted immediately.' 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'PRIVATE_OUTPUT_TOKEN cannot create releases in the output repository. Check that it is a Fine-grained PAT with Contents: Read and write scoped to that repository.'
}

& gh release delete $probeTag --repo $env:PRIVATE_OUTPUT_REPO --cleanup-tag --yes 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Probe release was created but could not be deleted; refusing to continue.' }

Write-Host 'Credential check PASSED: the token can create and delete releases in the private repository.'
