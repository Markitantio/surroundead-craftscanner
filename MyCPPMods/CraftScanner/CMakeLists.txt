add_library(CraftScanner SHARED
    src/Config.cpp
    src/Notification.cpp
    src/CraftScannerHooks.cpp
    src/CraftScannerMod.cpp
)

target_include_directories(CraftScanner PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Link against UE4SS. The exact target name depends on the RE-UE4SS CMake
# layout in use; 'UE4SS' is the conventional name for its shared library.
target_link_libraries(CraftScanner PRIVATE UE4SS)

set_target_properties(CraftScanner PROPERTIES
    PREFIX ""
    OUTPUT_NAME "CraftScanner"
)