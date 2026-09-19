# Suppress MSVC noise: C4996 (deprecated CRT), C4244 (wchar_t->char narrowing)
add_compile_options(/wd4996 /wd4244)
add_compile_definitions(NOMINMAX WIN32_LEAN_AND_MEAN)
add_subdirectory(CraftScanner)