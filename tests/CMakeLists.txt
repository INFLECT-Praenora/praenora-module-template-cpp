# The module's tests (ctest labels):
#   unit       in-process tests of the module class with the SDK's test kit (module_test.cpp)
#   documents  the manifest, the test vectors and every catalog entry, each validated against the
#              schema of its kind by the praenora tool
#   contract   the runtime's contract checks of the built library and its manifest
#              (praenora modules check), with its test vectors
#   workflow   the demo workflow (examples/): validated with the library loaded, then run
# The last three run the praenora tool of the runtime installation (cmake/PraenoraRuntime.cmake)
# and are registered only when it was found. They test the built module: build before ctest.

# The unit tests compile the module class (src/module.hpp) and MODULE_SOURCES themselves, with
# the identity that praenora_add_module() gives the library, so that describe() reports the same
# values. They define their own getter of the function table instead of src/module.cpp's exported
# entry point.
module_capabilities_json(_module_capabilities_json ${MODULE_CAPABILITIES})
string(REPLACE "\"" "\\\"" _module_capabilities_literal "${_module_capabilities_json}")
set(_module_test_sources "")
foreach(_source IN LISTS MODULE_SOURCES)
    get_filename_component(_source "${_source}" ABSOLUTE BASE_DIR "${PROJECT_SOURCE_DIR}")
    list(APPEND _module_test_sources "${_source}")
endforeach()

add_executable(module_test module_test.cpp ${_module_test_sources})
target_include_directories(module_test PRIVATE "${PROJECT_SOURCE_DIR}/src")
target_link_libraries(module_test PRIVATE
    Praenora::ModuleSDK nlohmann_json::nlohmann_json GTest::gtest_main)
target_compile_definitions(module_test PRIVATE
    "PRAENORA_MODULE_NAME=\"${MODULE_NAME}\""
    "PRAENORA_MODULE_VERSION=\"${PROJECT_VERSION}\""
    "PRAENORA_MODULE_CAPABILITIES=\"${_module_capabilities_literal}\"")
module_apply_compile_settings(module_test)

include(GoogleTest)
gtest_discover_tests(module_test PROPERTIES LABELS unit)

if(NOT PRAENORA_TOOL_FOUND)
    return()
endif()

# The built module's manifest and directory; with a multi-configuration generator they hold
# $<CONFIG>, which GENEX_EVAL resolves.
set(_module_manifest "$<GENEX_EVAL:$<TARGET_PROPERTY:module,PRAENORA_MODULE_MANIFEST>>")
set(_module_dir "$<GENEX_EVAL:$<TARGET_PROPERTY:module,PRAENORA_MODULE_DIR>>")
set(_catalog_arguments "")
if(MODULE_HAS_CATALOG)
    list(APPEND _catalog_arguments --catalog-path "${MODULE_CATALOG_DIR}")
endif()

# documents: every document against the schema of its kind.
add_test(NAME documents.manifest
    COMMAND "${PRAENORA_EXECUTABLE}" validate --document "${_module_manifest}")
add_test(NAME documents.vectors
    COMMAND "${PRAENORA_EXECUTABLE}" validate --document "${PROJECT_SOURCE_DIR}/vectors.json")
set(_documents documents.manifest documents.vectors)
set(_examples_catalog "${PROJECT_SOURCE_DIR}/examples/catalog")
file(GLOB_RECURSE _examples_catalog_files CONFIGURE_DEPENDS "${_examples_catalog}/*.json")
foreach(_document IN LISTS MODULE_CATALOG_FILES _examples_catalog_files)
    file(RELATIVE_PATH _name "${PROJECT_SOURCE_DIR}" "${_document}")
    add_test(NAME "documents.${_name}"
        COMMAND "${PRAENORA_EXECUTABLE}" validate --document "${_document}")
    list(APPEND _documents "documents.${_name}")
endforeach()
set_tests_properties(${_documents} PROPERTIES LABELS documents)

# contract: the contract checks, which exit with 0 only when no check failed.
add_test(NAME contract.modules_check
    COMMAND "${PRAENORA_EXECUTABLE}" modules check "${_module_manifest}" ${_catalog_arguments})
set_tests_properties(contract.modules_check PROPERTIES LABELS contract)

# workflow: the demo workflow, generated with the module's name and version, its data beside it.
set(_workflow_template "${PROJECT_SOURCE_DIR}/examples/workflow.yaml.in")
if(EXISTS "${_workflow_template}")
    set(_workflow "${PROJECT_BINARY_DIR}/examples/workflow.yaml")
    configure_file("${_workflow_template}" "${_workflow}" @ONLY)
    file(GLOB_RECURSE _workflow_data CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/examples/data/*")
    foreach(_file IN LISTS _workflow_data)
        file(RELATIVE_PATH _name "${PROJECT_SOURCE_DIR}/examples" "${_file}")
        configure_file("${_file}" "${PROJECT_BINARY_DIR}/examples/${_name}" COPYONLY)
    endforeach()
    set(_workflow_arguments --module-path "${_module_dir}" ${_catalog_arguments})
    if(_examples_catalog_files)
        list(APPEND _workflow_arguments --catalog-path "${_examples_catalog}")
    endif()
    add_test(NAME workflow.validate
        COMMAND "${PRAENORA_EXECUTABLE}" validate "${_workflow}" --load ${_workflow_arguments})
    add_test(NAME workflow.run
        COMMAND "${PRAENORA_EXECUTABLE}" run "${_workflow}" ${_workflow_arguments}
            --output-dir "${PROJECT_BINARY_DIR}/demo-run" --overwrite)
    set_tests_properties(workflow.validate workflow.run PROPERTIES LABELS workflow)
    set_tests_properties(workflow.run PROPERTIES DEPENDS workflow.validate)
endif()
