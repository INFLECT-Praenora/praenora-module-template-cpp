# Settings shared by the module library and its tests.

include_guard(GLOBAL)

option(MODULE_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

# module_apply_compile_settings(<target>): warnings, and -ffp-contract=off on GCC and Clang so that
# no multiply and add are fused into one rounding, which narrows the differences between platforms
# (the runtime's module developer guide, "Determinism and portability").
function(module_apply_compile_settings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /utf-8 /permissive- /Zc:__cplusplus /EHsc
            $<$<BOOL:${MODULE_WARNINGS_AS_ERRORS}>:/WX>)
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "^(GNU|Clang|AppleClang)$")
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -ffp-contract=off
            $<$<BOOL:${MODULE_WARNINGS_AS_ERRORS}>:-Werror>)
        # GCC 13's -Wdangling-reference reports references to what nlohmann/json's accessors
        # return when given a temporary key, which are not dangling.
        if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU"
           AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 13)
            target_compile_options(${target} PRIVATE -Wno-dangling-reference)
        endif()
    endif()
endfunction()

# module_capabilities_json(<out-var> <id@version>...): the capabilities as the JSON array that
# praenora_add_module() defines as PRAENORA_MODULE_CAPABILITIES, [{"id":"<id>","version":"<v>"},...].
function(module_capabilities_json out_var)
    set(json "")
    foreach(capability IN LISTS ARGN)
        if(NOT capability MATCHES "^([^@]+)@([^@]+)$")
            message(FATAL_ERROR "capability '${capability}' is not <id>@<version>")
        endif()
        if(NOT json STREQUAL "")
            string(APPEND json ",")
        endif()
        string(APPEND json "{\"id\":\"${CMAKE_MATCH_1}\",\"version\":\"${CMAKE_MATCH_2}\"}")
    endforeach()
    set(${out_var} "[${json}]" PARENT_SCOPE)
endfunction()
