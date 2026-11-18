# Packaging research notes (archived)

> Snapshot of the source-level research done while setting up this build: submodule pins,
> the Skia download URL pattern emitted by `laf/misc/skia-url.sh`, the archive checksum, and
> where the version string comes from.
>
> Two defects found *after* this snapshot are documented in README.md: the missing portable
> `aseprite.ini` and the hidden `libcrypto-3-x64.dll` dependency.

# Aseprite 1.3.18.6 (commit 331e898) — Windows x64 build & packaging evidence

Researched 2026-11-17 against pinned raw sources, the GitHub REST API, docs.github.com and actions/runner-images.
Everything below is cited; items that could not be executed here are marked UNVERIFIED.

## 0. Commit / submodule SHAs (prerequisite for everything else)

| Thing | Value | Evidence |
|---|---|---|
| Tag `v1.3.18.6` | commit `331e898ef405d919539c03fd1675691cfa16c3a3` | https://api.github.com/repos/aseprite/aseprite/tags (entry `v1.3.18.6`) |
| `laf` submodule | `500768cccc6447e3b7816bedbfcb378a5c5222e5` | aseprite root git-tree at 331e898: entry `laf`, type `commit`; `.gitmodules`: `path = laf`, `url = https://github.com/aseprite/laf.git` |

**Why the given URL 404s:** `https://raw.githubusercontent.com/aseprite/laf/331e898.../misc/skia-url.sh` → 404 because
331e898 is an *aseprite* commit that does not exist in the laf repository. The laf files must be read at
`500768cccc6447e3b7816bedbfcb378a5c5222e5`. (The same file exists on `main`.)

## 1. Skia

### Exact URL pattern emitted by `laf/misc/skia-url.sh`

```bash
skia_tag=$(cat "$script_dir/skia-tag.txt" | xargs)   # version string
skia_build=Release                                   # default; "debug" arg switches to Debug
source "$script_dir/platform.sh"                     # sets is_win / cpu
...
if [ $is_win ] ; then skia_file=Skia-Windows-$skia_build-$cpu.zip
...
echo https://github.com/aseprite/skia/releases/download/$skia_tag/$skia_file
```

Pattern: `https://github.com/aseprite/skia/releases/download/<skia_tag>/Skia-Windows-<Release|Debug>-<x64|x86|arm64>.zip`

### Version string and where it comes from

* `laf/misc/skia-tag.txt` (whole file, one line) contains exactly: **`m124-08a5439a6b`**
* That is the only input to the tag; CPU/OS come from `laf/misc/platform.sh` (MINGW/MSYS → `is_win=1, cpu=x64`).

### Resulting absolute URL for this build (Windows x64, Release)

```
https://github.com/aseprite/skia/releases/download/m124-08a5439a6b/Skia-Windows-Release-x64.zip
```

### Release asset verification (GitHub API + HTTP)

`GET https://api.github.com/repos/aseprite/skia/releases/tags/m124-08a5439a6b` → tag `m124-08a5439a6b`, name `Skia-m124`,
published 2024-06-11T19:01:56Z, prerelease=false, 12 assets. Windows assets:

| asset | bytes |
|---|---|
| Skia-Windows-Debug-x64.zip | 212,342,026 |
| Skia-Windows-Debug-x86.zip | 206,479,276 |
| **Skia-Windows-Release-x64.zip** | **28,759,398** |
| Skia-Windows-Release-x86.zip | 25,994,032 |

`curl -sIL` on the Release-x64 URL returns 302 → `release-assets.githubusercontent.com/.../Skia-Windows-Release-x64.zip`
(asset exists and is served).

### Unzipped directory layout (what you must end up with)

The zip root (per the packaging step of `aseprite/skia/.github/workflows/build.yml`, lines ~100-204) contains:
`include/`, `out/<mode>-<arch>/` (args.gn + `*.lib`), `modules/*/include/`,
`third_party/externals/{freetype,harfbuzz,libpng,libwebp,angle2,swiftshader}/...`.

`laf/cmake/FindSkia.cmake` then expects:

```
<SKIA_DIR>/out/Release-x64/skia.lib          # SKIA_LIBRARY_DIR = ${SKIA_DIR}/out/Release-${SKIA_ARCH}
<SKIA_DIR>/out/Release-x64/skunicode.lib
<SKIA_DIR>/out/Release-x64/skshaper.lib
<SKIA_DIR>/out/Release-x64/args.gn           # read to validate target_cpu
<SKIA_DIR>/include/...                       # target_include_directories(skia INTERFACE ${SKIA_DIR})
<SKIA_DIR>/third_party/externals/freetype/include
<SKIA_DIR>/third_party/externals/harfbuzz/src
```

So with the official workflow's `unzip "$skia_file" -d skia`: **`skia/out/Release-x64/`** is the expected path
(`-DSKIA_DIR=$(realpath skia) -DSKIA_LIBRARY_DIR=$(realpath skia/out/Release-x64)`, `.github/workflows/build.yml`).
No DLL members are packaged — only static `.lib` files and headers.

Official install snippet (build.yml):
```bash
skia_url=$(source $this_dir/laf/misc/skia-url.sh | xargs)
curl --ssl-revoke-best-effort -L -o "$(basename $skia_url)" "$skia_url"
unzip "$(basename $skia_url)" -d skia
```

## 2. Lua / ENABLE_SCRIPTING

* `.gitmodules`: `[submodule "third_party/lua"] path = third_party/lua  url = https://github.com/aseprite/lua`
* Pinned submodule commit: `2a00e6b0013f54ce80b6e3cefe6514e13229987a`; its `lua.h` reports **Lua 5.4.6**.
* `third_party/CMakeLists.txt:168-225` — bundled **source**, built inside the Aseprite CMake project:
  `add_library(lua lapi.c … lzio.c ltests.c)`, `add_library(lauxlib lua/lauxlib.c)`, `add_library(lualib …)`,
  C sources compiled as C++ (`set_source_files_properties(... PROPERTIES LANGUAGE CXX)`), all inside `if(ENABLE_SCRIPTING)`.
* `CMakeLists.txt:59` `set(BUILD_SHARED_LIBS off)` + no `SHARED` keyword ⇒ **static libraries, linked into aseprite.exe**.
* `CMakeLists.txt:81` `option(ENABLE_SCRIPTING "Compile with scripting support" on)` ⇒ Lua is ON by default.
* `CMakeLists.txt:10` `set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")` ⇒ **/MT static CRT**.

**Answer: Lua is statically linked; no `lua.dll` (or any DLL) is needed next to the exe.**

## 3. Runtime file set for a portable package

### Is `data/` embedded?

No — not as one blob. `src/CMakeLists.txt:96-179` copies the whole `data/` tree to **`build/bin/data`** with per-file
`add_custom_command` rules (target `copy_data`, `add_dependencies(aseprite copy_data)` at line 229).
Some individual XML/INI files are generated into C++ headers at build time (`src/app/CMakeLists.txt:5-92`):
`gui.xml` + `widgets/*.xml` → widget headers, `pref.xml` → `pref.xml.h/.cpp`, `strings/en.ini` → `strings.ini.h` + command ids,
`extensions/aseprite-theme/theme.xml` → `theme.xml.h`.

### What is read from disk at runtime (Windows)

`src/app/resource_finder.cpp` (`includeDataDir`): search order is `%AppData%\Aseprite\data\<file>` then
`<exe dir>\data\<file>`.

Mandatory for the GUI:
* `data/fonts/fonts.xml` — `SkinTheme::loadFontData()` throws `"File fonts/fonts.xml not found"` if absent (skin_theme.cpp:435-444).
* `data/extensions/aseprite-theme/` must load as an extension: `package.json` (extensions.cpp requires it), `theme.xml`
  (read from disk at runtime by `SkinTheme::loadXml`), `sheet.png` (`SkinTheme::loadSheet()` throws on failure).
  `sheet.aseprite-data` is only the editable source of the sheet.

Build-time only (no runtime reader found): `gui.xml`, `widgets/`, `pref.xml`, `strings/en.ini`, `icons/` (icons are used only
on Linux, app.cpp:501-525).

### install()/DLL rules

* `src/CMakeLists.txt:236-240`: `install(TARGETS aseprite RUNTIME DESTINATION bin)` and
  `install(DIRECTORY ../data DESTINATION share/aseprite)` — the Unix layout; Windows packages are assembled by copying.
* **No `.dll` copy/install rule exists anywhere** in the top-level, `src/`, `src/app/`, `third_party/` or `laf/` CMake files
  (third-party projects set `SKIP_INSTALL_ALL`). Skia is static; CRT is `/MT` ⇒ no MSVC redistributable required.
* Only dynamically loaded optional library: `wintab32.dll` (tablet API); failure is tolerated, and `--disable-wintab` exists.

### Portable mode

`App::isPortable()` (app.cpp:700-708) = existence of **`<exe dir>\aseprite.ini`**; otherwise config lives in `%AppData%\Aseprite`.

### Definitive minimal set (Windows, GUI, portable)

Verified-required subset (source of truth = `build\bin\data`, produced by the build):

```
aseprite.exe
aseprite.ini                                   # empty file → portable mode
data\fonts\fonts.xml
data\fonts\aseprite_font.png
data\fonts\aseprite_mini.png
data\extensions\aseprite-theme\package.json
data\extensions\aseprite-theme\theme.xml
data\extensions\aseprite-theme\sheet.png
```

Recommendation: ship the **entire `build\bin\data\` folder** (it also carries palettes, extra palettes/themes extensions and
translations users expect). CLI/batch-only use (`-b`) should work with the exe alone, since theme/font loading happens only for
the GUI — UNVERIFIED by execution.

## 4. Verifying the build output

* `CMakeLists.txt:173` (and the per-config repeats, e.g. :181) `set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")`
  ⇒ with Ninja (single-config) the binary is **`build/bin/aseprite.exe`**.
  Confirmed by the official workflow: `export ASEPRITE=$PWD/build/bin/aseprite`.
* Useful non-GUI flags (src/app/cli/app_options.cpp): `-b`/`--batch`, `--version`, `--help`/`-?`, `--verbose`/`-v`, `--debug`,
  `--list-layers`, `--list-layer-hierarchy`, `--list-tags`, `--list-slices`, `--save-as`, `--sheet`/`--data`/`--format`,
  `--oneframe`, `--ignore-empty`, and (scripting only) `--script`, `--script-param`, `--shell`.
* **`--version` does NOT print Lua state.** `DefaultCliDelegate::showVersion()` is literally
  `std::cout << get_app_name() << ' ' << get_app_version() << '\n';` (default_cli_delegate.cpp) ⇒ `Aseprite <version>` only.
* `--help` DOES reveal it: usage header is `<name> v<version> | A pixel art program` plus the option list, and
  `--script`/`--script-param`/`--shell` are registered only under `#ifdef ENABLE_SCRIPTING` (app_options.cpp:28-29, 144-152).
  If Lua is not compiled in, those flags are absent (and `--script` becomes an unknown option).

### Version string caveat (important for assertions)

`src/ver/CMakeLists.txt` sets `VERSION "1.x-dev"`, then (option `UPDATE_VERSION_WITH_GIT`, default ON) runs
`git describe --tags --always --dirty`, strips a leading `v`, and finally appends `-dev`:

| checkout state | `--version` prints |
|---|---|
| tag present (fetch-depth 0) | `Aseprite 1.3.18.6-dev` |
| no tags, `.git` present | `Aseprite 1.x-331e898-dev` |
| no `.git` (source zip) | `Aseprite 1.x-dev` |

Use `actions/checkout@v4` with `fetch-depth: 0` if the version must read 1.3.18.6; otherwise assert the prefix
`Aseprite 1.` (exactly what `tests/cli/version.sh` does).

### Concrete commands that prove Lua is enabled

```bat
:: 1. cheapest: option exists only when ENABLE_SCRIPTING is on
build\bin\aseprite.exe --help | findstr /C:"--script"

:: 2. real Lua execution, exit code 0 = engine ran and assertions passed
build\bin\aseprite.exe -b --script tests\scripts\version.lua
echo exit=%ERRORLEVEL%

:: 3. inline proof
> "%TEMP%\prove.lua" echo print(app.version)
build\bin\aseprite.exe -b --script "%TEMP%\prove.lua"

:: 4. full CLI+scripting suite (needs bash, e.g. Git Bash preinstalled on the runner)
set ASEPRITE=%CD%\build\bin\aseprite.exe
cd tests && bash run-tests.sh
```

Script failures propagate: `cli_processor.cpp:537-548` returns the script's exit code, and `-1` on exception, so a deliberately
broken script must yield non-zero. The negative test "`--script` is rejected" is not reliable by exit code alone — use
`--help | findstr` for that.

## 5. GitHub-hosted runner facts (windows-2025)

Source: https://docs.github.com/en/actions/reference/runners/github-hosted-runners (the requested
`about-github-hosted-runners` URL now redirects to the `concepts/runners/github-hosted-runners` page; the reference page holds
the spec table) and https://docs.github.com/en/actions/concepts/runners/github-hosted-runners.

| Public repositories (standard runners) | CPU | RAM | SSD | Arch | Labels |
|---|---|---|---|---|---|
| Windows | **4** | **16 GB** | **14 GB** | x64 | `windows-latest`, **`windows-2025`**, `windows-2025-vs2026`, `windows-2022` |

| Private repositories | CPU | RAM | SSD | Labels |
|---|---|---|---|---|
| Windows | 2 | 8 GB | 14 GB | same four labels |

* Quote: "Use of the standard GitHub-hosted runners is free and unlimited on public repositories." The billing docs add that
  "Standard GitHub-hosted runners in public repositories" are free independently and do **not** reduce included compute usage.
* `windows-2025` is a valid standard-runner label (listed in the public-repo table above).
  `windows-latest` is grouped in the same row as `windows-2025` (exact `windows-latest` → image mapping is not spelled out on
  that page: UNVERIFIED, but it resolves to the Server 2025 image today).
* Preinstalled (actions/runner-images `images/windows/Windows2025-Readme.md`, image 20261111.331.1, OS 10.0.26100):
  * **Visual Studio Enterprise 2022 17.14.37906.3** — `C:\Program Files\Microsoft Visual Studio\2022\Enterprise`
  * **Windows SDK 10.0.26100.0** (the only SDK installed)
  * **CMake 3.31.6**, **Ninja 1.13.2** (both on PATH — the Aseprite workflow calls bare `cmake`/`ninja`)
  * MSVC x64 environment: Aseprite's own CI uses `TheMrMilchmann/setup-msvc-dev@v4` (arch x64); alternatively
    `vcvarsall.bat x64` / `ilammy/msvc-dev-cmd`.
  * Git for Windows / bash, unzip and curl are present (the workflow's Windows job runs bash + curl + unzip).

## UNVERIFIED / limits of this evidence

1. Byte-level listing of `Skia-Windows-Release-x64.zip` (layout derived from aseprite/skia's packaging globs, not from unzipping).
2. Whether `data/` can be omitted entirely for `-b` CLI-only use (inferred from the GUI-only theme/font code paths).
3. Absolute install paths of cmake/ninja binaries on the image (versions verified; only VS + SDK paths are stated in the readme).
4. `windows-latest` → `windows-2025` mapping is implied by the docs table row, not stated explicitly.
5. Whether official 1.3.18.6 release binaries print without the `-dev` suffix (their release pipeline is not public).