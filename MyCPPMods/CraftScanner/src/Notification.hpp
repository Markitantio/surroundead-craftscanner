#pragma once

#include <string>

namespace CraftScanner {

extern volatile bool g_bTeardownDetected;

namespace Notification {

bool Show(const std::wstring& message, double durationSec);

} // namespace Notification

} // namespace CraftScanner