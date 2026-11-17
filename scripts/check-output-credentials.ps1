# 02b Fail-fast probe of the private output credential.
# Runs BEFORE the ~25 minute compile so a wrong token costs a minute, not a build.
# It only reads the destination repository and asserts that the token carries write
# (push) permission - creating and deleting a throwaway release proved unnecessary
# and left draft releases behind (a draft has no git tag ref, so --cleanup-tag 422s).
$ErrorActionPreference = 'Stop'

if (-not $env:PRIVATE_OUTPUT_TOKEN) { throw 'secret PRIVATE_OUTPUT_TOKEN is not configured on this repository.' }
if (-not $env:PRIVATE_OUTPUT_REPO)   { throw 'secret PRIVATE_OUTPUT_REPO is not configured on this repository.' }

$env:GH_TOKEN = $env:PRIVATE_OUTPUT_TOKEN
$env:GH_HOST  = 'github.com'

$info = & gh api ("repos/" + $env:PRIVATE_OUTPUT_REPO) --jq '.full_name + " | private=" + (.private|tostring) + " | push=" + (.permissions.push|tostring)' 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "PRIVATE_OUTPUT_TOKEN cannot read the output repository. A 404 here (rather than 401) means the token is valid but cannot see this repository: check 'Repository access -> Only select repositories' and the 'Contents: Read and write' permission. Detail: $info"
}

Write-Host "Output repository: $info"

if ("$info" -notmatch 'private=true') {
    throw 'The output repository is not private - refusing to publish Aseprite binaries into a public repository.'
}

if ("$info" -notmatch 'push=true') {
    throw 'PRIVATE_OUTPUT_TOKEN has no write permission on the output repository (needs Contents: Read and write).'
}

Write-Host 'Credential check PASSED: token can read the private repository and holds write permission.'
