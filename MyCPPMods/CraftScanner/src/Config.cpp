#include "Config.hpp"
#include "CS_Common.hpp"

#include <Windows.h>
#include <filesystem>
#include <algorithm>

namespace CraftScanner {

// Path to the INI. We try the Mod folder first (same as DLL lives in),
// then fall back to the current working directory.
static std::wstring IniPath() {
    wchar_t buf[MAX_PATH] = {};
    HMODULE self = nullptr;
    // GetModuleHandleEx with FROM_ADDRESS to get our DLL handle
    GetModuleHandleExW(
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
        GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&IniPath),
        &self);
    if (self && GetModuleFileNameW(self, buf, MAX_PATH)) {
        std::filesystem::path p(buf);
        // dll is in Mods\CraftScanner\dlls\CraftScanner.dll
        // INI is in Mods\CraftScanner\CraftScanner.ini
        std::filesystem::path candidate =
            p.parent_path().parent_path() / L"CraftScanner.ini";
        if (std::filesystem::exists(candidate)) return candidate.wstring();
        candidate = p.parent_path() / L"CraftScanner.ini";
        if (std::filesystem::exists(candidate)) return candidate.wstring();
    }
    return L"CraftScanner.ini";
}

static std::wstring ReadStr(const std::wstring& ini,
                            const wchar_t* section,
                            const wchar_t* key,
                            const std::wstring& fallback) {
    wchar_t buf[1024] = {};
    DWORD n = GetPrivateProfileStringW(
        section, key, fallback.c_str(), buf,
        static_cast<DWORD>(std::size(buf)), ini.c_str());
    if (n == 0) return fallback;
    return std::wstring(buf, n);
}

static int32_t ReadInt(const std::wstring& ini,
                       const wchar_t* section,
                       const wchar_t* key,
                       int32_t fallback) {
    return static_cast<int32_t>(
        GetPrivateProfileIntW(section, key, fallback, ini.c_str()));
}

static double ReadDouble(const std::wstring& ini,
                         const wchar_t* section,
                         const wchar_t* key,
                         double fallback) {
    std::wstring s = ReadStr(ini, section, key, L"");
    if (s.empty()) return fallback;
    try { return std::stod(s); } catch (...) { return fallback; }
}

static bool ReadBool(const std::wstring& ini,
                     const wchar_t* section,
                     const wchar_t* key,
                     bool fallback) {
    int32_t v = ReadInt(ini, section, key, fallback ? 1 : 0);
    return v != 0;
}

// Split "a,b,c" -> {"a","b","c"}, trimming whitespace.
static std::vector<std::wstring> SplitList(const std::wstring& s) {
    std::vector<std::wstring> out;
    std::wstring cur;
    for (wchar_t c : s) {
        if (c == L',') {
            if (!cur.empty()) out.push_back(cur);
            cur.clear();
        } else if (c != L' ' && c != L'\t') {
            cur.push_back(c);
        }
    }
    if (!cur.empty()) out.push_back(cur);
    return out;
}

CSConfig LoadConfig() {
    CSConfig cfg;
    const std::wstring ini = IniPath();

    cfg.Enabled     = ReadBool  (ini, L"Settings", L"Enabled",     cfg.Enabled);
    cfg.VerboseLog  = ReadBool  (ini, L"Settings", L"VerboseLog",  cfg.VerboseLog);
    cfg.Hotkey      = ReadStr   (ini, L"Settings", L"Hotkey",      cfg.Hotkey);
    cfg.DurationSec = ReadDouble(ini, L"Settings", L"DurationSec", cfg.DurationSec);
    cfg.MaxLines    = ReadInt   (ini, L"Settings", L"MaxLines",    cfg.MaxLines);

    cfg.ShowAll        = ReadBool(ini, L"Filter", L"ShowAll", cfg.ShowAll);
    cfg.IncludeTypes   = SplitList(ReadStr(ini, L"Filter", L"IncludeTypes",   L""));
    cfg.IncludeItemIds = SplitList(ReadStr(ini, L"Filter", L"IncludeItemIds", L""));

    cfg.Title      = ReadStr (ini, L"Display", L"Title",       cfg.Title);
    cfg.SortByCount= ReadBool(ini, L"Display", L"SortByCount", cfg.SortByCount);
    cfg.ShowEmpty  = ReadBool(ini, L"Display", L"ShowEmpty",   cfg.ShowEmpty);

    return cfg;
}

std::wstring GetIniValue(const wchar_t* section, const wchar_t* key,
                         const std::wstring& fallback) {
    return ReadStr(IniPath(), section, key, fallback);
}

} // namespace CraftScanner