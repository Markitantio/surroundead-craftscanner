#pragma once

// --- Windows FIRST, with NOMINMAX ---
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <Windows.h>

#include <string>
#include <cstdint>
#include <vector>
#include <unordered_map>
#include <type_traits>
#include <cstring>

// ---- UE4SS core ----
#include <UE4SSProgram.hpp>
#include <DynamicOutput/Output.hpp>
#include <String/StringType.hpp>

// ---- Unreal SDK ----
#include <Unreal/Common.hpp>
#include <Unreal/NameTypes.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UFunction.hpp>
#include <Unreal/UObjectGlobals.hpp>

using namespace RC;
using namespace RC::Unreal;

namespace CraftScanner {

// ------------------------------------------------------------
// Version
// ------------------------------------------------------------
constexpr const wchar_t* CS_VERSION = L"0.1.0";

// ------------------------------------------------------------
// Logging
// ------------------------------------------------------------
inline void Log(const std::wstring& msg) {
    Output::send<LogLevel::Verbose>(STR("[CraftScanner] ") + msg);
}

// ------------------------------------------------------------
// Offsets
// ------------------------------------------------------------
namespace Offsets {
    constexpr int32_t Player_JigMultiComponent    = 0x07F0;
    constexpr int32_t Player_JigHelperComp        = 0x06D8;
    constexpr int32_t Player_PlayerController     = 0x13C8;
    constexpr int32_t UObject_ObjectFlags         = 0x08;

    constexpr int32_t Jig_MainJigContainers       = 0xC0;
    constexpr int32_t Jig_MainContainersIDs       = 0xF8;

    constexpr int32_t RCI_Size                    = 0x50;
    constexpr int32_t RCI_ContainerItems          = 0x40;

    constexpr int32_t CPI_Size                    = 0xD8;
    constexpr int32_t CPI_IsContainer             = 0x10;
    constexpr int32_t CPI_ItemInfo                = 0x28;

    constexpr int32_t RII_DataAsset               = 0x00;
    constexpr int32_t RII_Count                   = 0x08;

    constexpr int32_t DA_ItemId                   = 0x30;
    constexpr int32_t DA_ItemType                 = 0x68;

    constexpr int32_t TArray_Data                 = 0x00;
    constexpr int32_t TArray_Num                  = 0x08;
    constexpr int32_t TArray_Max                  = 0x0C;
}

// ------------------------------------------------------------
// SEH-safe POD read (Windows.h provides EXCEPTION_EXECUTE_HANDLER)
// ------------------------------------------------------------
template<typename T>
inline bool SafeRead(const void* base, int32_t offset, T* out) {
    static_assert(std::is_trivially_copyable_v<T>, "SafeRead requires POD");
    if (!base || !out) return false;
    __try {
        *out = *reinterpret_cast<const T*>(
            reinterpret_cast<const uint8_t*>(base) + offset);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

inline void* SafeReadPtr(const void* base, int32_t offset) {
    void* p = nullptr;
    if (!SafeRead(base, offset, &p)) return nullptr;
    return p;
}

// POD-only ProcessEvent wrapper. The caller must pass a POD buffer.
// This exists because __try cannot appear in a function that has
// C++ objects with destructors on the stack.
inline bool SafeProcessEvent(UObject* obj, UFunction* fn, void* params) {
    if (!obj || !fn) return false;
    __try {
        obj->ProcessEvent(fn, params);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

struct RawTArray {
    void*   Data = nullptr;
    int32_t Num  = 0;
    int32_t Max  = 0;
};
inline bool SafeReadTArray(const void* base, int32_t offset, RawTArray* out) {
    if (!out) return false;
    void* d = nullptr;
    int32_t n = 0, m = 0;
    if (!SafeRead(base, offset + Offsets::TArray_Data, &d)) return false;
    if (!SafeRead(base, offset + Offsets::TArray_Num,  &n)) return false;
    if (!SafeRead(base, offset + Offsets::TArray_Max,  &m)) return false;
    out->Data = d; out->Num = n; out->Max = m;
    return true;
}

// ------------------------------------------------------------
// Pending-kill
// ------------------------------------------------------------
inline bool IsPendingKill(UObject* o) {
    if (!o) return true;
    uint32_t flags = 0;
    if (!SafeRead(o, Offsets::UObject_ObjectFlags, &flags)) return true;
    return (flags & 0x42000000u) != 0;
}

// ------------------------------------------------------------
// Pawn
// ------------------------------------------------------------
UObject* ResolveCurrentPawn();

// ------------------------------------------------------------
// FName
// ------------------------------------------------------------
struct RawFName {
    uint32_t ComparisonIndex = 0;
    uint32_t Number          = 0;
};

inline bool SafeReadFName(const void* base, int32_t offset, RawFName* out) {
    if (!out) return false;
    if (!SafeRead(base, offset + 0, &out->ComparisonIndex)) return false;
    if (!SafeRead(base, offset + 4, &out->Number))          return false;
    return true;
}

// No __try inside: index is bounded, ToString is safe.
std::wstring RawFNameToString(const RawFName& raw);

} // namespace CraftScanner