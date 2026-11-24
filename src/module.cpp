// The module library's one exported entry point, praenora_module_get_api, and its static function
// table, for the module class. praenora_add_module() compiles this file with hidden visibility, so
// nothing else is exported.
//
// TEMPLATE: name your module class here; list further source files in MODULE_SOURCES in
// CMakeLists.txt (not here: the unit tests do not compile this file).
#include "module.hpp"

PRAENORA_SDK_DEFINE_MODULE(my_module::Summarizer)
