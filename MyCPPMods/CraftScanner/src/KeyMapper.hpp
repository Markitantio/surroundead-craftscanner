#pragma once

#include <string>
#include <optional>
#include <Input/Handler.hpp>

namespace CraftScanner {

// Maps a user-facing key name ("F1".."F12", "A".."Z", "0".."9") to RC::Input::Key.
// Uses VK codes cast to the enum (portable across UE4SS 3.0.1 builds).
inline std::optional<RC::Input::Key> MapKeyName(const std::wstring& name) {
    if (name.empty()) return std::nullopt;

    // Uppercase copy
    std::wstring s = name;
    for (auto& c : s) c = towupper(c);

    // F1..F12
    if (s.size() >= 2 && s[0] == L'F') {
        int n = 0;
        for (size_t i = 1; i < s.size(); ++i) {
            if (s[i] < L'0' || s[i] > L'9') { n = 0; break; }
            n = n * 10 + (s[i] - L'0');
        }
        if (n >= 1 && n <= 12) {
            return static_cast<RC::Input::Key>(VK_F1 + (n - 1));
        }
    }

    // Single letter A..Z
    if (s.size() == 1 && s[0] >= L'A' && s[0] <= L'Z') {
        return static_cast<RC::Input::Key>(s[0]);
    }

    // Single digit 0..9
    if (s.size() == 1 && s[0] >= L'0' && s[0] <= L'9') {
        return static_cast<RC::Input::Key>(s[0]);
    }

    // Special keys
    if (s == L"SPACE")   return static_cast<RC::Input::Key>(VK_SPACE);
    if (s == L"TAB")     return static_cast<RC::Input::Key>(VK_TAB);
    if (s == L"ENTER")   return static_cast<RC::Input::Key>(VK_RETURN);
    if (s == L"ESCAPE")  return static_cast<RC::Input::Key>(VK_ESCAPE);
    if (s == L"INSERT")  return static_cast<RC::Input::Key>(VK_INSERT);
    if (s == L"DELETE")  return static_cast<RC::Input::Key>(VK_DELETE);
    if (s == L"HOME")    return static_cast<RC::Input::Key>(VK_HOME);
    if (s == L"END")     return static_cast<RC::Input::Key>(VK_END);
    if (s == L"PGUP")    return static_cast<RC::Input::Key>(VK_PRIOR);
    if (s == L"PGDOWN")  return static_cast<RC::Input::Key>(VK_NEXT);
    if (s == L"UP")      return static_cast<RC::Input::Key>(VK_UP);
    if (s == L"DOWN")    return static_cast<RC::Input::Key>(VK_DOWN);
    if (s == L"LEFT")    return static_cast<RC::Input::Key>(VK_LEFT);
    if (s == L"RIGHT")   return static_cast<RC::Input::Key>(VK_RIGHT);

    return std::nullopt;
}

} // namespace CraftScanner