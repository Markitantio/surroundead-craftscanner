cmake_minimum_required(VERSION 3.22)
project(CraftScanner CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Path to the RE-UE4SS repository (used for headers/libs and cmake helpers)
set(RE_UE4SS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/RE-UE4SS" CACHE PATH "RE-UE4SS root")

# Include UE4SS as a subproject. EXCLUDE_FROM_ALL prevents its default
# targets from being built unless our mod actually depends on them.
add_subdirectory(${RE_UE4SS_ROOT} ${CMAKE_BINARY_DIR}/RE-UE4SS EXCLUDE_FROM_ALL)

# Our mod
add_subdirectory(MyCPPMods)