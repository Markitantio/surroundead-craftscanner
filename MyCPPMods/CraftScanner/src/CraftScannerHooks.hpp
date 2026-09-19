#pragma once

namespace CraftScanner {

// Called from the mod entry point during installation.
// Registers the hotkey (F2 by default, read from INI) and prepares state.
void Install();

// Called once per frame if you need a tick. Currently a no-op; the mod is
// purely event-driven (hotkey).
void Update();

// True when a teardown was detected (a caught access violation during
// world/object iteration). Once set, the mod stops all game interaction.
extern volatile bool g_bTeardownDetected;

} // namespace CraftScanner