cmake_minimum_required(VERSION 3.24)

# The macOS deployment target must be known before project() runs the compiler checks. It is
# ignored on other platforms.
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version targeted by the build")

# ---------------------------------------------------------------------------------------------
# TEMPLATE: the module's identity. Set it here, once: the manifest, describe(), the tests, the
# package's name and the CI's release tag all derive from these lines. Keep each on one line; CI
# reads the version and the name with sed.
#
#   project(<cmake project> VERSION <x.y.z>)  The module's semantic version (and the release tag
#                                             v<x.y.z>).
#   MODULE_NAME               The module name: lower-case words of letters, digits and '-',
#                             separated by dots. It is also the library's file name.
#   MODULE_CAPABILITIES       Each implemented capability as <id>@<version>, as the protocol
#                             catalog names it (the runtime's built-in catalog, or catalog/).
#   MODULE_REQUIRES_SERVICES  Runtime services the module cannot work without, as
#   MODULE_OPTIONAL_SERVICES  <name>@<major>.<minor>, and those it uses when present, for example
#                             praenora.simulation@0.0.
project(my_module VERSION 0.1.0 LANGUAGES C CXX)
set(MODULE_NAME my-module)
set(MODULE_CAPABILITIES my-module.summarize@0.1.0)
set(MODULE_REQUIRES_SERVICES "")
set(MODULE_OPTIONAL_SERVICES "")
# ---------------------------------------------------------------------------------------------

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(BUILD_TESTING "Build the module's tests" ON)

# The module SDK and the praenora tool (cmake/PraenoraRuntime.cmake), third-party dependencies
# (cmake/ModuleDependencies.cmake) and the settings shared by the module and its tests.
include(PraenoraRuntime)
include(ModuleDependencies)
include(ModuleSettings)

# The protocol catalog entries the module defines (catalog/): capability definitions, message
# types. Leave the folder out when the module implements only capabilities of the runtime's
# built-in catalog.
set(MODULE_CATALOG_DIR "${PROJECT_SOURCE_DIR}/catalog")
file(GLOB_RECURSE MODULE_CATALOG_FILES CONFIGURE_DEPENDS "${MODULE_CATALOG_DIR}/*.json")
if(MODULE_CATALOG_FILES)
    set(MODULE_HAS_CATALOG TRUE)
else()
    set(MODULE_HAS_CATALOG FALSE)
endif()

# The module: its library (<name>.so, or .dll on Windows, exporting only praenora_module_get_api),
# its manifest <name>.pmm.json generated from module.pmm.json.in, and its test vectors, together in
# <build>/<name>/ and, installed, in lib/praenora/modules/<name>/, where the runtime finds modules
# by itself. The target is named `module` whatever the module's name.
#
# TEMPLATE: list the module's source files besides src/module.cpp (which holds only the entry
# point) in MODULE_SOURCES, relative to this directory. The unit tests compile them too.
set(MODULE_SOURCES "")
set(_module_service_arguments "")
if(MODULE_REQUIRES_SERVICES)
    list(APPEND _module_service_arguments REQUIRES_SERVICES ${MODULE_REQUIRES_SERVICES})
endif()
if(MODULE_OPTIONAL_SERVICES)
    list(APPEND _module_service_arguments OPTIONAL_SERVICES ${MODULE_OPTIONAL_SERVICES})
endif()
praenora_add_module(module
    NAME ${MODULE_NAME}
    VERSION ${PROJECT_VERSION}
    CAPABILITIES ${MODULE_CAPABILITIES}
    ${_module_service_arguments}
    SOURCES src/module.cpp ${MODULE_SOURCES}
    MANIFEST_TEMPLATE module.pmm.json.in
    TEST_VECTORS vectors.json
    INSTALL_DESTINATION "lib/praenora/modules/${MODULE_NAME}"
    INSTALL_COMPONENT module
    LINK_LIBRARIES nlohmann_json::nlohmann_json)
module_apply_compile_settings(module)

# The installation and the archive (cmake/ModulePackage.cmake).
include(ModulePackage)

if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()
