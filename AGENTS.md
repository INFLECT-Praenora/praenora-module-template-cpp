# AGENTS.md

A guide for coding agents and human contributors working in this repository. Read it before
changing anything. [README.md](README.md) covers the same ground for users: setup, presets,
deployment, releases.

## Purpose

This repository holds **one Praenora module written in C++**. The module is a library that the
Praenora runtime ([praenora-runtime](https://github.com/INFLECT-Praenora/praenora-runtime)) loads
at run time and that implements capabilities of the protocol catalog. It is built with the runtime's
module SDK (CMake package `Praenora`, component `ModuleSDK`) and its header-only C++ adapter
(`praenora/sdk/module.hpp`).

The repository started from the template `praenora-module-template-cpp`, whose sample module is
`my-module` (capability `my-module.summarize@0.1.0`). While that sample is still here, treat it as
the thing to replace, following README.md, "Make it yours".

The runtime is referred to only by its GitHub URL. Its documentation, at the pinned version:
- [module developer guide](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/module-developer-guide.md)
- [module ABI](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/module-abi.md)
- [manifest](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/manifest.md)
- [threading and ownership](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/threading-and-ownership.md)
- [protocol and catalog](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/protocol.md)
- [compatibility policy](https://github.com/INFLECT-Praenora/praenora-runtime/blob/v0.2.0/docs/specs/compatibility-policy.md)

Where this file and those documents disagree, the runtime's documents win. Fix this file.

## Ground rules

- **One module per repository.** Do not add a second module target. A second capability of the
  same module is fine: list it in `MODULE_CAPABILITIES`.
- **The identity lives in one place**, the block at the top of `CMakeLists.txt`:
  - `project(... VERSION x.y.z ...)`
  - `MODULE_NAME`, `MODULE_CAPABILITIES`
  - `MODULE_REQUIRES_SERVICES`, `MODULE_OPTIONAL_SERVICES`

  Never write the module's name, version or capabilities into C++ sources or the manifest
  template. They reach them as `PRAENORA_MODULE_NAME`, `PRAENORA_MODULE_VERSION`,
  `PRAENORA_MODULE_CAPABILITIES` and `@...@` variables. Keep the `project()` and
  `set(MODULE_NAME ...)` lines on one line each: CI reads them with `sed`.
- **Never edit generated files.** The manifest `build/<preset>/<name>/<name>.pmm.json` comes from
  `module.pmm.json.in`, and the demo configuration `build/<preset>/examples/workflow.yaml` comes
  from `examples/workflow.yaml.in`.
- **Verify before you claim.** Every change ends with a build and `ctest` that pass, and you report
  what you ran and what it printed. A change to packaging also runs the target `package` and
  `.github/scripts/check-archive.sh build/<preset>`.
- **Releases are made only by the workflow**, from `main` with `publish`, and published by a
  maintainer. Never create tags or releases by hand, and never push to `main` directly.
- **No secrets** in the repository, the workflow or test data.
- **Keep the documentation in step.** A change that alters a command, a preset, a label, the
  layout or the archive's contents updates README.md and this file in the same change.

## Layout

| Path | Responsibility |
|---|---|
| `CMakeLists.txt` | Identity block; `MODULE_SOURCES` (sources besides `src/module.cpp`, compiled by the library and the unit tests); `praenora_add_module(module ...)` (the target is always `module`); catalog detection; includes. |
| `src/module.hpp` | The module class, derived from `praenora::sdk::Module`, in a header so the unit tests can include it. |
| `src/module.cpp` | `PRAENORA_SDK_DEFINE_MODULE(<class>)` only: the exported entry point and the static table. |
| `module.pmm.json.in` | Manifest template: summary, authors, repository, `parameters_schema`, `features`, `requires`, `tests`. |
| `vectors.json` | Test vectors (`module-test-vectors` 0.1.0), shipped beside the manifest. |
| `catalog/` | Catalog entries the module defines, shipped in `share/praenora/module-catalog/`. Delete it when every capability is built in. |
| `examples/` | Demo workflow: definition (`examples/catalog/`, not shipped), data, configuration template. |
| `tests/` | `module_test.cpp` (GoogleTest + the SDK test kit) and `CMakeLists.txt`, which registers every test. |
| `cmake/PraenoraRuntimePin.cmake` | The pinned runtime release (version, archive names, SHA-256 per platform key). |
| `cmake/PraenoraRuntime.cmake` | `PRAENORA_RUNTIME_SOURCE` (`auto`, `fetch`, `find`), `find_package(Praenora)`, the `praenora` tool. |
| `cmake/ModuleDependencies.cmake` | nlohmann/json and GoogleTest via FetchContent (find first, pinned URL and SHA-256). |
| `cmake/ModuleSettings.cmake` | `module_apply_compile_settings()`, `module_capabilities_json()`. |
| `cmake/ModulePackage.cmake` | Install rules (component `module`) and CPack naming. |
| `.github/workflows/build.yml` | CI: PR builds on four platform keys; manual `publish` on `main` drafts a release. |
| `.github/scripts/check-archive.sh` | Archive check: library dependencies, then the contract checks of the packaged module. |

## Commands

```sh
cmake --preset dev                  # configure (downloads the pinned runtime on first use)
cmake --build --preset dev          # build the module and the tests
ctest --preset dev                  # every test; -L unit|documents|contract|workflow for one label
cmake --build --preset dev --target package   # the archive, in build/dev/package/
```

- On Windows, use the preset `windows-dev`.
- To build exactly as CI does, use `ci-<key>` with the host's key.
- `ctest` does not build: build first.

The `praenora` tool of the runtime in use is `PRAENORA_EXECUTABLE` in `build/<preset>/CMakeCache.txt`.
It can be used directly:
- `modules check <manifest> --catalog-path catalog`
- `validate --document <file>`
- `catalog list --catalog-path catalog`
- `run <config> --module-path <dir> --catalog-path catalog --catalog-path examples/catalog --trace`

## Module rules

These hold for every module. The adapter enforces part of them, and the contract checks test part.

- **ABI.**
  - Only `praenora_module_get_api` is exported (`praenora_add_module()` compiles with hidden
    visibility).
  - Nothing but C types crosses the boundary: no C++ objects, exceptions, `FILE*`, or memory one
    side allocates and the other frees.
  - Inputs are borrowed for the call; copy what you keep.
  - Outputs are returned as the result document `{"outputs": {"<port>": {"data": ...}}}`. Only
    declared ports may appear, and every required one must.
- **Errors.** Throw `praenora::sdk::Error(code, message[, details_json])`:
  - `PRAENORA_STATUS_INVALID_ARGUMENT` for a document that cannot be read (the contract checks send
    `{`);
  - `PRAENORA_STATUS_DATA_INVALID` for data of the wrong shape or values;
  - `PRAENORA_STATUS_UNSUPPORTED`, `RESOURCE_EXHAUSTED`, `CANCELLED` and `FAILED` as their names
    say;
  - module-specific codes from `PRAENORA_STATUS_MODULE_BASE` (10000) up, never 100 to 9999.

  The adapter catches every exception at the boundary.
- **Threading.**
  - The runtime calls one instance from one thread, one call at a time.
  - `features.concurrency` `"instance"` (the sample's) declares instances independent. Use
    `"module"` if the library has global state that instances share.
  - Threads a module starts are joined before `destroy` returns.
  - Long loops poll `host.cancel_requested()` and then throw `CANCELLED`.
- **Determinism**, so that runs are reproducible byte for byte; the contract check
  `invoke.determinism` tests part of it:
  - no global mutable state;
  - no file I/O in algorithm code (everything comes through the documents);
  - no wall clock, timers or process ids;
  - randomness only from the step's seed in the initialize document;
  - no hash-table or pointer order in outputs (use `std::map` or sort);
  - no uninitialized memory or undefined behavior;
  - locale-independent number formatting (nlohmann/json is);
  - GCC and Clang build with `-ffp-contract=off` (`module_apply_compile_settings()`).
- **Parameters.** Every parameter is described in `parameters_schema` (JSON Schema draft-07), with
  a `default` where one makes sense. The runtime validates parameters and fills in defaults before
  `create`. The module still refuses bad values with `INVALID_ARGUMENT`.
- **Services.**
  - Declare every runtime service in the identity block. A module sees only declared services.
  - Look a service up once, in the constructor, with `host.service(name, major)`.
  - Check for NULL and for the table's `struct_size`.
- **Dependencies.** The archive must need only the system's libraries (CI's check). Prefer
  header-only or static libraries, add them in `cmake/ModuleDependencies.cmake` with a pinned
  version and SHA-256, link them with `LINK_LIBRARIES`, and package their licenses in
  `cmake/ModulePackage.cmake` when they are compiled in.

## Catalog entries

- New capabilities and message types go in `catalog/capabilities/<id>/<version>.json` and
  `catalog/messages/<id>/<version>.json`. Their schemas are the runtime's `capability-definition`
  0.1 and `message-type` 0.1. Message schemas are JSON Schema draft-07 and accept `x-` extension
  properties, as the runtime's types do.
- Ids are lower-case dotted names (`^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)*$`) with a prefix of your
  own. `pmp.` and `example.` belong to the runtime.
- An entry is identified by `id@version`; the runtime refuses a second entry with the same one.
  Once released, an entry is immutable: change it by adding a new version, and declare the new
  capability version in `MODULE_CAPABILITIES` (capabilities match exactly).
- Reuse the built-in message types (`pmp.observation-batch`, `pmp.prediction-set`, ...) where they
  fit. `praenora catalog list` shows them.
- `ctest -L documents` validates every entry. `ctest -L contract` checks the module's outputs
  against its message types.

## Versioning

- The module's version (`project(VERSION)`) is semantic. Configurations pin exact versions, so
  any change a user could notice needs a new version.
- Raise it in the pull request that prepares a release. A release with `publish` refuses a version
  whose tag exists.
- The ABI, SDK and PMP versions in the manifest come from the SDK the build used. Rebuilding
  against a new runtime pin updates them. Never write them by hand.

## Tests

- **`unit`**: the module class in process, with `FakeHost` and `DirectModule` from
  `praenora/sdk/testing.hpp`.
  - Write the test first and watch it fail.
  - Use hand-derived expected values, not values computed by the code under test.
  - Keep a malformed-invocation test and a determinism test.
- **`documents`, `contract`, `workflow`**: run the runtime's `praenora` tool against the built
  module. Every change to the module must keep them passing. A failing contract check names its
  check id and what differed.
- **`vectors.json`** is part of the module's contract: change it together with the behavior. The
  vectors' expected outputs must be exact, or carry a `tolerance`.

Before a release can be adopted:
- the module's own tests pass;
- `praenora modules check` passes on its manifest;
- its test vectors ship with it (the runtime's module acceptance gate).

## CI and releases

- `.github/workflows/build.yml` mirrors the runtime's workflow:
  - the platform keys and runners `linux-x64-release`/`ubuntu-24.04`,
    `macos-arm64-release`/`macos-26`, `windows-x64-release`/`windows-2022` and
    `windows-x64-debug`/`windows-2022`;
  - the presets `ci-<key>`;
  - actions pinned by commit, with the version in a comment.
- Keep the matrix, the `ci-<key>` presets and the keys of `cmake/PraenoraRuntimePin.cmake` in step.
- Runner labels are fixed image versions, never `-latest`.
- Releases follow README.md, "Releasing".

## Raising the runtime pin

Only when a maintainer asks for it:
1. Update every line of `cmake/PraenoraRuntimePin.cmake` together.
2. Update the documentation links' tag in README.md and this file.
3. Reconfigure and run every test.

A new runtime minor version can change the SDK, the ABI minor, the manifest format or the catalog.
Read its module developer guide and release notes first.

## Style

- C++17, formatted with `.clang-format` (LLVM based, 100 columns, 4 spaces). `.editorconfig` covers
  the rest: LF, UTF-8, 2 spaces for JSON and YAML, 4 elsewhere.
- Comments say why, and what a reader cannot see in the code. Each file starts with a short
  comment saying what it is for.
- Commit messages: imperative subject line, body explaining why.
