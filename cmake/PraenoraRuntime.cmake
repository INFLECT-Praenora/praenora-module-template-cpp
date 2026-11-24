# Resolves the Praenora module SDK and the `praenora` tool. Included once by the top-level
# CMakeLists.txt, at its own scope (find_package() must define the SDK's variables there).
#
# The module SDK is the component ModuleSDK of the CMake package Praenora, which every installation
# and every release archive of praenora-runtime holds. It is headers only: compiling a module needs
# nothing else of the runtime. PRAENORA_RUNTIME_SOURCE says where it comes from:
#
#   auto   (default) an installation that find_package() finds (CMAKE_PREFIX_PATH, Praenora_ROOT,
#          or the environment variable PRAENORA_RUNTIME naming an installation's prefix); when
#          there is none, the pinned release archive (fetch).
#   fetch  always the pinned release archive of PRAENORA_RUNTIME_PLATFORM
#          (cmake/PraenoraRuntimePin.cmake): downloaded into PRAENORA_RUNTIME_DOWNLOAD_DIR, checked
#          against its SHA-256 and unpacked, once. The CI presets use this.
#   find   only an installation that find_package() finds; never downloads.
#
# PRAENORA_RUNTIME_PLATFORM is the key of the archive to fetch, by default the build host's:
# linux-x64-release, macos-arm64-release or windows-x64-release. Other hosts have no archive; use
# PRAENORA_RUNTIME_SOURCE=find with an installation of the runtime built for them.
#
# Afterwards: the target Praenora::ModuleSDK, the function praenora_add_module(), the variables
# PRAENORA_SDK_VERSION, PRAENORA_PMP_VERSION, PRAENORA_ABI_MAJOR, PRAENORA_ABI_MINOR and
# PRAENORA_MODULE_MANIFEST_FORMAT_VERSION, PRAENORA_RUNTIME_PREFIX (the installation's prefix),
# and PRAENORA_EXECUTABLE (cache: the `praenora` tool, first from the installation's bin/, then from
# PATH) with PRAENORA_TOOL_FOUND. Without the tool the tests that run it are not registered, unless
# PRAENORA_REQUIRE_TOOL is ON, which makes a missing tool an error.

include_guard(GLOBAL)

include(PraenoraRuntimePin)

set(PRAENORA_RUNTIME_SOURCE "auto" CACHE STRING
    "Where the Praenora module SDK comes from: auto, fetch or find")
set_property(CACHE PRAENORA_RUNTIME_SOURCE PROPERTY STRINGS auto fetch find)
if(NOT PRAENORA_RUNTIME_SOURCE MATCHES "^(auto|fetch|find)$")
    message(FATAL_ERROR "PRAENORA_RUNTIME_SOURCE is '${PRAENORA_RUNTIME_SOURCE}'; use auto, fetch "
        "or find.")
endif()

# The platform key of the build host, or "" when no archive is published for it.
function(_praenora_runtime_host_platform out_var)
    string(TOLOWER "${CMAKE_HOST_SYSTEM_PROCESSOR}" cpu)
    set(key "")
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux" AND cpu MATCHES "^(x86_64|amd64)$")
        set(key "linux-x64-release")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" AND cpu MATCHES "^(arm64|aarch64)$")
        set(key "macos-arm64-release")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows" AND cpu MATCHES "^(x86_64|amd64)$")
        set(key "windows-x64-release")
    endif()
    set(${out_var} "${key}" PARENT_SCOPE)
endfunction()

_praenora_runtime_host_platform(_praenora_host_platform)
set(PRAENORA_RUNTIME_PLATFORM "${_praenora_host_platform}" CACHE STRING
    "The platform key of the praenora-runtime archive to fetch")
set_property(CACHE PRAENORA_RUNTIME_PLATFORM PROPERTY STRINGS ${PRAENORA_RUNTIME_PLATFORMS})
set(PRAENORA_RUNTIME_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/_praenora-runtime" CACHE PATH
    "Where the praenora-runtime archive is downloaded and unpacked")
option(PRAENORA_REQUIRE_TOOL "Fail when the praenora tool is not found" OFF)

string(REGEX MATCH "^[0-9]+\\.[0-9]+" _praenora_runtime_series "${PRAENORA_RUNTIME_VERSION}")

# _praenora_runtime_fetch(<prefix-var>): downloads, checks and unpacks the pinned archive of
# PRAENORA_RUNTIME_PLATFORM, unless it is unpacked already, and sets <prefix-var> to its prefix.
function(_praenora_runtime_fetch prefix_var)
    set(key "${PRAENORA_RUNTIME_PLATFORM}")
    if(key STREQUAL "" OR NOT key IN_LIST PRAENORA_RUNTIME_PLATFORMS)
        list(JOIN PRAENORA_RUNTIME_PLATFORMS ", " keys)
        message(FATAL_ERROR "Praenora runtime: no release archive for the platform key "
            "'${key}' (host: ${CMAKE_HOST_SYSTEM_NAME} ${CMAKE_HOST_SYSTEM_PROCESSOR}). Set "
            "PRAENORA_RUNTIME_PLATFORM to one of ${keys}, or build against an installation of "
            "praenora-runtime with -DPRAENORA_RUNTIME_SOURCE=find -DPraenora_ROOT=<its prefix>.")
    endif()
    set(archive "${PRAENORA_RUNTIME_ARCHIVE_${key}}")
    set(sha256 "${PRAENORA_RUNTIME_SHA256_${key}}")
    string(REGEX REPLACE "\\.(tar\\.xz|zip)$" "" name "${archive}")
    set(dir "${PRAENORA_RUNTIME_DOWNLOAD_DIR}")
    set(prefix "${dir}/${name}")
    set(stamp "${dir}/${name}.sha256")
    set(config "${prefix}/lib/cmake/Praenora/PraenoraConfig.cmake")

    if(EXISTS "${stamp}" AND EXISTS "${config}")
        file(READ "${stamp}" unpacked_sha256)
        string(STRIP "${unpacked_sha256}" unpacked_sha256)
        if(unpacked_sha256 STREQUAL sha256)
            message(STATUS "Praenora runtime: ${name} already unpacked in ${dir}")
            set(${prefix_var} "${prefix}" PARENT_SCOPE)
            return()
        endif()
    endif()

    set(url "${PRAENORA_RUNTIME_REPOSITORY}/releases/download/v${PRAENORA_RUNTIME_VERSION}/${archive}")
    message(STATUS "Praenora runtime: downloading ${archive}")
    file(MAKE_DIRECTORY "${dir}")
    file(DOWNLOAD "${url}" "${dir}/${archive}" STATUS status TLS_VERIFY ON)
    list(GET status 0 code)
    if(NOT code EQUAL 0)
        list(GET status 1 reason)
        file(REMOVE "${dir}/${archive}")
        message(FATAL_ERROR "Praenora runtime: could not download ${url}: ${reason}. Without "
            "network access, build against an installation of praenora-runtime "
            "(-DPRAENORA_RUNTIME_SOURCE=find -DPraenora_ROOT=<its prefix>).")
    endif()
    file(SHA256 "${dir}/${archive}" actual_sha256)
    if(NOT actual_sha256 STREQUAL sha256)
        file(REMOVE "${dir}/${archive}")
        message(FATAL_ERROR "Praenora runtime: ${archive} has the SHA-256 ${actual_sha256}, but "
            "cmake/PraenoraRuntimePin.cmake pins ${sha256}.")
    endif()
    file(REMOVE_RECURSE "${prefix}")
    file(ARCHIVE_EXTRACT INPUT "${dir}/${archive}" DESTINATION "${dir}")
    file(REMOVE "${dir}/${archive}")
    if(NOT EXISTS "${config}")
        message(FATAL_ERROR "Praenora runtime: ${archive} holds no ${name}/lib/cmake/Praenora/"
            "PraenoraConfig.cmake.")
    endif()
    file(WRITE "${stamp}" "${sha256}\n")
    set(${prefix_var} "${prefix}" PARENT_SCOPE)
endfunction()

# The SDK. Unless the source is fetch, a package or tool cached from a fetched archive is looked up
# again: after a switch to an installation (find, or Praenora_ROOT in auto), or a raised pin, the
# archive found before must not stay in use. In auto, the fetch below finds it again by its stamp.
if(NOT PRAENORA_RUNTIME_SOURCE STREQUAL "fetch")
    foreach(_praenora_runtime_cached IN ITEMS Praenora_DIR PRAENORA_EXECUTABLE)
        string(FIND "${${_praenora_runtime_cached}}" "${PRAENORA_RUNTIME_DOWNLOAD_DIR}/"
            _praenora_runtime_at)
        if(_praenora_runtime_at EQUAL 0)
            unset(${_praenora_runtime_cached} CACHE)
        endif()
    endforeach()
endif()
set(_praenora_runtime_fetched "")
if(PRAENORA_RUNTIME_SOURCE STREQUAL "fetch")
    _praenora_runtime_fetch(_praenora_runtime_fetched)
elseif(PRAENORA_RUNTIME_SOURCE STREQUAL "auto")
    find_package(Praenora ${_praenora_runtime_series} QUIET COMPONENTS ModuleSDK
        HINTS "$ENV{PRAENORA_RUNTIME}")
    if(NOT Praenora_FOUND)
        message(STATUS "Praenora runtime: no installation of praenora-runtime "
            "${_praenora_runtime_series} found; using the pinned release archive")
        _praenora_runtime_fetch(_praenora_runtime_fetched)
    endif()
endif()
if(_praenora_runtime_fetched)
    # Only the fetched archive: drop a Praenora_DIR cached from another source.
    string(FIND "${Praenora_DIR}" "${_praenora_runtime_fetched}/" _praenora_runtime_at)
    if(NOT _praenora_runtime_at EQUAL 0)
        unset(Praenora_DIR CACHE)
    endif()
    find_package(Praenora ${_praenora_runtime_series} REQUIRED COMPONENTS ModuleSDK
        NO_DEFAULT_PATH PATHS "${_praenora_runtime_fetched}")
elseif(NOT Praenora_FOUND)
    find_package(Praenora ${_praenora_runtime_series} REQUIRED COMPONENTS ModuleSDK
        HINTS "$ENV{PRAENORA_RUNTIME}")
endif()
get_filename_component(PRAENORA_RUNTIME_PREFIX "${Praenora_DIR}/../../.." ABSOLUTE)
message(STATUS "Praenora runtime: SDK ${PRAENORA_SDK_VERSION} (PMP ${PRAENORA_PMP_VERSION}, ABI "
    "${PRAENORA_ABI_MAJOR}.${PRAENORA_ABI_MINOR}) from ${PRAENORA_RUNTIME_PREFIX}")

# The tool: the installation's own first. A cached path that is gone, or that belongs to another
# installation than a fetched archive, is looked up again.
if(PRAENORA_EXECUTABLE AND NOT EXISTS "${PRAENORA_EXECUTABLE}")
    unset(PRAENORA_EXECUTABLE CACHE)
endif()
if(PRAENORA_EXECUTABLE AND _praenora_runtime_fetched)
    string(FIND "${PRAENORA_EXECUTABLE}" "${_praenora_runtime_fetched}/" _praenora_runtime_at)
    if(NOT _praenora_runtime_at EQUAL 0)
        unset(PRAENORA_EXECUTABLE CACHE)
    endif()
endif()
find_program(PRAENORA_EXECUTABLE NAMES praenora HINTS "${PRAENORA_RUNTIME_PREFIX}/bin"
    DOC "The praenora tool of praenora-runtime, which runs the contract checks")
if(PRAENORA_EXECUTABLE)
    set(PRAENORA_TOOL_FOUND TRUE)
    message(STATUS "Praenora runtime: tool ${PRAENORA_EXECUTABLE}")
elseif(PRAENORA_REQUIRE_TOOL)
    message(FATAL_ERROR "Praenora runtime: the praenora tool was not found in "
        "${PRAENORA_RUNTIME_PREFIX}/bin or on PATH, and PRAENORA_REQUIRE_TOOL is ON.")
else()
    set(PRAENORA_TOOL_FOUND FALSE)
    message(STATUS "Praenora runtime: tool not found: the documents, contract and workflow tests "
        "are skipped")
endif()
