# Third-party dependencies, each found as an installed package first and otherwise downloaded at a
# pinned version, checked against its SHA-256 (FetchContent with FIND_PACKAGE_ARGS). The CI presets
# set FETCHCONTENT_TRY_FIND_PACKAGE_MODE=NEVER, so CI always builds the pinned sources.
#
# - nlohmann/json (header-only) reads and writes the module's JSON documents; the module SDK parses
#   no JSON itself, so another JSON library will do as well. It is compiled into the module, which
#   therefore needs no shared library of its own; its license is packaged when it was downloaded
#   (cmake/ModulePackage.cmake).
# - GoogleTest, only with BUILD_TESTING, for the in-process unit tests.
#
# TEMPLATE: add the module's own dependencies here the same way. Prefer static or header-only
# libraries: a module archive should need only the system's libraries (CI checks this).

include_guard(GLOBAL)

include(FetchContent)

# The versions praenora-runtime pins.
FetchContent_Declare(nlohmann_json
    URL "https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz"
    URL_HASH SHA256=42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa
    DOWNLOAD_EXTRACT_TIMESTAMP ON
    FIND_PACKAGE_ARGS 3.11 CONFIG)
set(JSON_Install OFF CACHE INTERNAL "No install rules for nlohmann/json")
FetchContent_MakeAvailable(nlohmann_json)

if(BUILD_TESTING)
    FetchContent_Declare(googletest
        URL "https://github.com/google/googletest/releases/download/v1.18.0/googletest-1.18.0.tar.gz"
        URL_HASH SHA256=6e3191c1455468b3fc35a417fb565c1c5071aee1b7e7f85e30cf48a98d37d8b5
        DOWNLOAD_EXTRACT_TIMESTAMP ON
        FIND_PACKAGE_ARGS 1.11 CONFIG NAMES GTest)
    set(INSTALL_GTEST OFF CACHE INTERNAL "No install rules for GoogleTest")
    set(BUILD_GMOCK OFF CACHE INTERNAL "No GoogleMock")
    # The test executable uses the same C runtime as everything else (/MD, /MDd).
    set(gtest_force_shared_crt ON CACHE INTERNAL "GoogleTest with the shared C runtime")
    FetchContent_MakeAvailable(googletest)
endif()
