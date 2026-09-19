#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace CraftScanner {

struct CSConfig {
    // [Settings]
    bool        Enabled        = true;
    bool        VerboseLog     = false;
    std::wstring Hotkey        = L"F2";
    double      DurationSec    = 15.0;
    int32_t     MaxLines       = 40;

    // [Filter]
    bool        ShowAll        = false;
    std::vector<std::wstring> IncludeTypes;    // "Material", "Tool", ...
    std::vector<std::wstring> IncludeItemIds;  // explicit whitelist

    // [Display]
    std::wstring Title         = L"Crafting Resources";
    bool        SortByCount    = true;
    bool        ShowEmpty      = false;
};

// Loads CraftScanner.ini located next to the DLL (or in the Mod folder).
CSConfig LoadConfig();

// Reads a single [Hotkeys]-like value from the INI at call time.
std::wstring GetIniValue(const wchar_t* section, const wchar_t* key,
                         const std::wstring& fallback);

} // namespace CraftScanner