# praenora-module-template-cpp

A GitHub template for a [Praenora](https://github.com/INFLECT-Praenora/praenora-runtime) module
written in C++. A repository made from it holds one module: a library that the Praenora runtime
loads at run time and that implements one or more capabilities of the protocol catalog. It builds
against the runtime's module SDK with its C++ adapter, and its tests include the runtime's own
contract checks.

As it comes, the template builds a working sample module, `my-module`, which summarizes each tick's
observations. Replace the sample with your module by following [Make it yours](#make-it-yours).

What a build produces, in `build/<preset>/<name>/` and in the release archives:

- the module library `<name>.so` (`<name>.dll` on Windows), which exports only
  `praenora_module_get_api`, the entry point of the module ABI v0;
- its module manifest `<name>.pmm.json` (PMM 0.2.0), which the runtime reads to find and check the
  module before loading it;
- its test vectors `vectors.json`, which the contract checks run;
- the protocol catalog entries the module defines (capability definitions, message types), from
  `catalog/`.

## Prerequisites

- CMake 3.24 or later.
- A C++17 compiler: GCC, Clang or AppleClang with Ninja, or Visual Studio 2022 (x64).
- Network access on the first configuration, which downloads the pinned runtime release (unless
  you build against an installation of the runtime, below), and nlohmann/json and GoogleTest when
  they are not installed.

The pinned runtime release has archives for Linux x86-64, macOS arm64 and Windows x86-64.

## Quick start

On Linux or macOS:

```sh
cmake --preset dev
cmake --build --preset dev
ctest --preset dev
```

On Windows: `cmake --preset windows-dev`, `cmake --build --preset windows-dev` and
`ctest --preset windows-dev`.

The first configuration downloads the runtime release that
[`cmake/PraenoraRuntimePin.cmake`](cmake/PraenoraRuntimePin.cmake) pins, checks its SHA-256 and
unpacks it into `build/<preset>/_praenora-runtime/`. It brings the module SDK and the `praenora`
tool. `ctest` builds nothing: build first.

## Make it yours

The module's identity is set once, at the top of [`CMakeLists.txt`](CMakeLists.txt). The manifest,
`describe()`, the tests, the archive's name and the release tag all derive from it. Edit these, in
this order:

1. **Identity**, in `CMakeLists.txt`:
   - `project(<cmake name> VERSION <x.y.z> ...)`, the module's version;
   - `MODULE_NAME`, the module's name and library file name;
   - `MODULE_CAPABILITIES`, each capability it implements as `<id>@<version>`;
   - `MODULE_REQUIRES_SERVICES` and `MODULE_OPTIONAL_SERVICES`, the runtime services it uses, such
     as `praenora.simulation@0.0`.

   Use an id prefix of your own for new capabilities and message types (`pmp.` and `example.` are
   the runtime's).
2. **Manifest template**, [`module.pmm.json.in`](module.pmm.json.in):
   - `summary`, `authors` and `repository`;
   - `parameters_schema`, with a `default` for every parameter that can have one;
   - `features`.

   The `@...@` variables are filled in by the build. Leave them as they are.
3. **Catalog entries**, [`catalog/`](catalog/): the capability definitions and message types your
   module defines, one file per entry (`capabilities/<id>/<version>.json`,
   `messages/<id>/<version>.json`). If your module implements only capabilities of the runtime's
   built-in catalog (`praenora catalog list`), delete `catalog/`.
4. **Code**, [`src/module.hpp`](src/module.hpp) and [`src/module.cpp`](src/module.cpp): your module
   class. Further sources go to `MODULE_SOURCES` in `CMakeLists.txt`, which the library and the
   unit tests both compile. Further dependencies go to
   [`cmake/ModuleDependencies.cmake`](cmake/ModuleDependencies.cmake) and `LINK_LIBRARIES`.
5. **Unit tests**, [`tests/module_test.cpp`](tests/module_test.cpp).
6. **Test vectors**, [`vectors.json`](vectors.json): cases with each capability's id and version,
   the inputs of each tick and the expected outputs. Good vectors come from real runs (a run's
   message trace, `praenora run --trace`).
7. **Demo workflow**, [`examples/`](examples/): a workflow definition that uses your capability,
   its data, and the configuration `workflow.yaml.in`, whose module name and version come from the
   identity. Adapt it, or delete `examples/`; its tests go with it.
8. **License**: [`LICENSE`](LICENSE) is the runtime's MIT license; change it if your module is
   licensed differently.

Then build and run `ctest`. All tests passing means the module's documents are valid, it passes the
runtime's contract checks, and the demo workflow runs.

## Layout

| Path | What it is |
|---|---|
| `CMakeLists.txt` | The identity block and the build: `praenora_add_module()` builds the library and generates the manifest. |
| `CMakePresets.json` | The presets `dev`, `release`, `windows-dev` and `ci-<key>`. |
| `module.pmm.json.in` | The manifest template. |
| `vectors.json` | The test vectors, shipped with the module. |
| `src/` | The module class (`module.hpp`) and the library's entry point (`module.cpp`). |
| `tests/` | The unit tests and the registration of every test. |
| `catalog/` | The catalog entries the module defines, shipped with it. |
| `examples/` | The demo workflow: its definition (not shipped), data and configuration. |
| `cmake/PraenoraRuntimePin.cmake` | The pinned runtime release: version, archives, SHA-256 digests. |
| `cmake/PraenoraRuntime.cmake` | Finds or downloads the module SDK, and finds the `praenora` tool. |
| `cmake/ModuleDependencies.cmake` | nlohmann/json and GoogleTest, found or downloaded at pinned versions. |
| `cmake/ModuleSettings.cmake` | Warnings and floating-point settings, shared by the module and its tests. |
| `cmake/ModulePackage.cmake` | The installation and the archive. |
| `.github/workflows/build.yml` | CI and releases. |
| `.github/scripts/check-archive.sh` | Checks an archive's library dependencies and runs the contract checks on the packaged module. |
| `AGENTS.md` | The guide for coding agents and contributors. |

## Building and testing

| Preset | Generator, configuration | Use |
|---|---|---|
| `dev` | Ninja, Debug | Development on Linux and macOS. |
| `release` | Ninja, Release | A local release build. |
| `windows-dev` | Visual Studio 2022 (x64), Debug | Development on Windows. |
| `ci-<key>` | as CI | The CI build of a platform key, as CI runs it. |

Each preset has a build and a test preset of the same name. The CI presets turn warnings into
errors, always build nlohmann/json and GoogleTest from their pinned sources, and require the
`praenora` tool.

`ctest` labels (`ctest --preset dev -L <label>`):

| Label | Tests |
|---|---|
| `unit` | The module class in process, with the SDK's test kit (`praenora/sdk/testing.hpp`). |
| `documents` | The manifest, the test vectors and every catalog entry, validated against their schemas (`praenora validate --document`). |
| `contract` | The runtime's contract checks of the built module (`praenora modules check`): the library loads, its table and `describe()` agree with the manifest, the lifecycle, the vectors' expected outputs, determinism, a malformed invocation. |
| `workflow` | The demo workflow: validated with the library loaded (`praenora validate --load`), then run for 3 ticks (`praenora run`, outputs in `build/<preset>/demo-run/`). |

The last three need the `praenora` tool. Without it they are not registered, and configuring says
so.

### Where the runtime comes from

`PRAENORA_RUNTIME_SOURCE` decides where the module SDK comes from:

- `auto` (the default): an installation of praenora-runtime 0.2 that `find_package()` finds; if
  there is none, the pinned release archive is downloaded.
- `fetch`: always the pinned release archive (the CI presets).
- `find`: only an installation; nothing is downloaded.

To build against a runtime installation, for example a local build of the runtime installed with
`cmake --install`:

```sh
cmake --preset dev -DPRAENORA_RUNTIME_SOURCE=find -DPraenora_ROOT=/path/to/runtime/prefix
```

You can also set the environment variable `PRAENORA_RUNTIME` to that prefix.
`PRAENORA_RUNTIME_PLATFORM` chooses the archive to download (`linux-x64-release`,
`macos-arm64-release`, `windows-x64-release` or `windows-x64-debug`; by default the host's). The
SDK is headers only, so any archive serves any configuration; only its `praenora` tool must run on
the host.

On Windows, keep the checkout's path short. The runtime archive's deepest file is about 133
characters below `PRAENORA_RUNTIME_DOWNLOAD_DIR` (by default `build/<preset>/_praenora-runtime`),
and Windows limits paths to 260 characters. Alternatively, set `PRAENORA_RUNTIME_DOWNLOAD_DIR` to a
short directory, as CI does.

On macOS, the `dev` preset uses Homebrew's GoogleTest when it is installed. The linker then warns
that it was built for a newer macOS than the deployment target, which is harmless. To build the
pinned GoogleTest instead, configure with `-DFETCHCONTENT_TRY_FIND_PACKAGE_MODE=NEVER`.

## Deploying into a runtime distribution

The target `package` (`PACKAGE` with Visual Studio) writes
`build/<preset>/package/<name>-<version>-<os>-<arch>-<compiler>-<config>.tar.xz` (`.zip` on
Windows), and a `.sha256` file beside it. CI builds one per platform key, and releases publish
them. An archive holds:

```text
<archive name>/
  lib/praenora/modules/<name>/<name>.so          the library (.dll on Windows)
  lib/praenora/modules/<name>/<name>.pmm.json    its manifest
  lib/praenora/modules/<name>/vectors.json       its test vectors
  share/praenora/module-catalog/...              its catalog entries, in the catalog's layout
  share/praenora/licenses/<name>/...             license files
```

Copy the contents of the archive for the runtime's platform into the runtime installation's
prefix. The runtime then finds the module in `lib/praenora/modules` without further options. The
module's catalog entries are added with one directory, which serves every module deployed this way:

```sh
tar -xJf my-module-0.1.0-linux-x86_64-gcc13-release.tar.xz
cp -R my-module-0.1.0-linux-x86_64-gcc13-release/. "$PREFIX"/
export PRAENORA_CATALOG_PATH="$PREFIX/share/praenora/module-catalog"
"$PREFIX/bin/praenora" modules list
"$PREFIX/bin/praenora" modules check "$PREFIX/lib/praenora/modules/my-module/my-module.pmm.json"
```

`--catalog-path` does the same as `PRAENORA_CATALOG_PATH` for one command. Do not put the runtime's
own `share/praenora/catalog` on the catalog path: it holds the built-in entries, and loading an
entry twice is an error. To keep modules apart from the runtime, unpack them anywhere and name the
directory with `--module-path` or `PRAENORA_MODULE_PATH`, for example
`<dir>/lib/praenora/modules`.

The manifest declares one platform. The runtime refuses a module built for another OS or
architecture (`PLATFORM_MISMATCH`), and one whose ABI major or PMP version it does not support.

## Releasing

[`.github/workflows/build.yml`](.github/workflows/build.yml) follows the runtime's CI:

- **Every pull request to `main`.** On the four platform keys of the runtime's CI
  (`linux-x64-release` on `ubuntu-24.04`, `macos-arm64-release` on `macos-26`,
  `windows-x64-release` and `windows-x64-debug` on `windows-2022`), each job:
  - builds against the runtime archive of its key;
  - runs every test;
  - packages the module;
  - checks that the archive needs only the system's libraries and that the packaged module passes
    the contract checks;
  - keeps the archive as a workflow artifact for 7 days.
- **Run manually on `main` with `publish`.** The same jobs, then a draft release `v<version>` with
  the four archives and their checksums.

To release:

1. In a pull request to `main`, raise the version in `project(... VERSION ...)` in
   `CMakeLists.txt`. A run with `publish` stops when the tag `v<version>` already exists.
2. Merge it.
3. Run the workflow on `main` with *Create a draft release* checked, or
   `gh workflow run build.yml --ref main -f publish=true`.
4. Check the draft release: four archives with their `.sha256` files and the notes. Then publish
   it. Publishing creates the tag.

Recommended repository settings:
- `main` takes changes only through pull requests, and requires the checks `Prepare`,
  `linux-x64-release`, `macos-arm64-release`, `windows-x64-release` and `windows-x64-debug`.
- Tags `v*` are created only by maintainers.

### Raising the runtime pin

When the runtime publishes a release you want to build against:
1. Update every line of [`cmake/PraenoraRuntimePin.cmake`](cmake/PraenoraRuntimePin.cmake)
   together: the version, and each archive's name and SHA-256 (from the release's `.sha256` files
   or its assets' digests).
2. Reconfigure and run the tests.

A new minor version of the runtime can change the SDK. Read its release notes and its module
developer guide. Rebuilding updates the SDK, PMP and ABI versions in the manifest by itself. If the
runtime's CI changes its platform keys or runners, change the matrix in
`.github/workflows/build.yml` and the `ci-<key>` presets to match.

## The runtime's documentation

At the pinned version, v0.2.0:
- [Module developer guide](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/module-developer-guide.md): the SDK, the ABI rules, the C++ adapter, the manifest, services, the test kit, test vectors, contract checks, determinism.
- [Module ABI](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/module-abi.md), [manifest](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/manifest.md), [threading and ownership](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/threading-and-ownership.md): the normative rules.
- [Protocol](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/protocol.md): documents, the catalog and its built-in entries.
- [User guide](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/user-guide.md) and [configuration](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/configuration.md): the `praenora` tool and workflow configurations.

## License

MIT, as the runtime: see [LICENSE](LICENSE).
