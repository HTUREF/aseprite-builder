# aseprite-builder

Public build workspace that compiles **Aseprite for Windows x64** on a GitHub-hosted
`windows-2025` standard runner, triggered manually, and publishes the verified ZIP to a
**private** output repository.

This repository intentionally contains **no Aseprite source and no binaries** - only the
workflow and the build/verification scripts.

## What it builds

| Item | Value |
| --- | --- |
| Aseprite | v1.3.18.6 |
| Source commit | `331e898ef405d919539c03fd1675691cfa16c3a3` |
| Skia | `m124-08a5439a6b` (official prebuilt, `Skia-Windows-Release-x64.zip`) |
| Target | Windows x64 GUI, Skia backend, Lua scripting, RelWithDebInfo |
| Runner | `windows-2025` (4 vCPU / 16 GB RAM) |
| Job timeout | 60 minutes |
| Parallelism | `cmake --build build --target aseprite --parallel 4` |

The Skia version is never guessed. `scripts/fetch-skia.ps1` reads
`laf/misc/skia-tag.txt` **from the pinned source tree** and fails the job if it does not
match the pinned `SKIA_TAG`. The archive bytes are additionally checked against a pinned
SHA-256, and Skia is never compiled from source.

## Pipeline

1. **Preflight** - reports real runner facts (vCPU, RAM, disk, VS, Windows SDK, CMake,
   Ninja) and proves the toolchain is already present; nothing is installed.
2. **Conditional disk reclaim** - only when free space is below 20 GB, and never touching
   Visual Studio, the Windows SDK, CMake, Ninja or Git.
3. **Pinned source** - checks out `aseprite/aseprite` at the exact tag, with recursive
   submodules, then asserts `HEAD == ASEPRITE_SHA` and that every submodule is populated.
4. **Skia** - version cross-checked against `laf/misc/skia-tag.txt`, archive SHA-256
   verified, extracted to `skia/out/Release-x64`.
5. **Configure / build** - Ninja + MSVC x64 from `vcvars64.bat`, only the `aseprite`
   target, 4 jobs.
6. **Verify** - the compile exit code is not trusted. The step reads the PE header
   (machine must be `0x8664`), runs `--version` / `--help`, executes a Lua probe with
   `-b --script` (proof that scripting is really compiled in), and re-runs the binary from
   an isolated staging directory containing only packaged files.
7. **Package** - every runtime file, no `.obj`/`.lib`/`.pdb`/intermediate output.
8. **Publish** - private release only.

## Required repository secrets

Set on **this** repository (Settings -> Secrets and variables -> Actions):

| Secret | Purpose |
| --- | --- |
| `PRIVATE_OUTPUT_TOKEN` | Fine-grained PAT, "Only select repositories" -> the private output repo, permission **Contents: Read and write**. Nothing else. |
| `PRIVATE_OUTPUT_REPO` | `<owner>/<private-output-repo>`. Stored as a secret so the private repository name never appears in this public repository's files or logs. |

The workflow's own `GITHUB_TOKEN` is read-only (`permissions: contents: read`) and is
never used for writing anywhere.

## Running

```bash
gh workflow run build-aseprite.yml -f publish=true --repo <owner>/aseprite-builder
gh run watch --repo <owner>/aseprite-builder
```

## Output

The private release contains:

- `aseprite-windows-x64.zip` - the complete portable runtime file set
- `build-manifest.json` - versions, source SHA, Skia SHA, build args, runner facts, timings, ZIP SHA-256
- `SHA256SUMS.txt`

## Licensing

Aseprite source is published under its own EULA. Compiled binaries are private, are not
uploaded to this public repository, and are not redistributed.
