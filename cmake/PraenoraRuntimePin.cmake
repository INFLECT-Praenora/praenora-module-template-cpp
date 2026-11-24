# The pinned release of praenora-runtime that this module builds and is checked against.
#
# The runtime's release archives hold the module SDK (the CMake package Praenora, component
# ModuleSDK) and the `praenora` tool, which the tests use for the contract checks. One archive per
# platform key; the keys are those of the runtime's CI and of this repository's CI presets
# (ci-<key>) and workflow matrix (.github/workflows/build.yml).
#
# To raise the pin: take the new release's archive names and SHA-256 digests (each archive has a
# .sha256 file beside it, and the release page lists each asset's digest), update every line below
# together, then reconfigure and run the tests. find_package() asks for the major.minor of
# PRAENORA_RUNTIME_VERSION, so a new minor version of the runtime is adopted here, deliberately.
#
# CI reads PRAENORA_RUNTIME_VERSION and PRAENORA_RUNTIME_REPOSITORY with sed: keep each set() on
# one line, with the value in double quotes.

set(PRAENORA_RUNTIME_VERSION "0.2.0")
set(PRAENORA_RUNTIME_REPOSITORY "https://github.com/INFLECT-Praenora/praenora-runtime")

set(PRAENORA_RUNTIME_PLATFORMS
    linux-x64-release
    macos-arm64-release
    windows-x64-release
    windows-x64-debug)

set(PRAENORA_RUNTIME_ARCHIVE_linux-x64-release
    "praenora-runtime-0.2.0-linux-x86_64-gcc13-release.tar.xz")
set(PRAENORA_RUNTIME_SHA256_linux-x64-release
    "062a9f7700444cab399b51fb47f2276ccdeba2eb08f71ea0bef891ddc6ae6cca")

set(PRAENORA_RUNTIME_ARCHIVE_macos-arm64-release
    "praenora-runtime-0.2.0-macos-arm64-appleclang21-release.tar.xz")
set(PRAENORA_RUNTIME_SHA256_macos-arm64-release
    "b87f78a59df74b3d49cdb01510510d733cb5a8814898b97cd655510c7d05733c")

set(PRAENORA_RUNTIME_ARCHIVE_windows-x64-release
    "praenora-runtime-0.2.0-windows-x86_64-msvc143-release.zip")
set(PRAENORA_RUNTIME_SHA256_windows-x64-release
    "29496b6539464c02726be2604d19c739284c60c22d31a96cf9a8d77c0a858dc6")

set(PRAENORA_RUNTIME_ARCHIVE_windows-x64-debug
    "praenora-runtime-0.2.0-windows-x86_64-msvc143-debug.zip")
set(PRAENORA_RUNTIME_SHA256_windows-x64-debug
    "1b4677736639de1c711d92619c83096971216b505ce7af75a785eddc1196a399")
