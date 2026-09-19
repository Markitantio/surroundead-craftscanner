#include <Mod/CppUserModBase.hpp>
#include <UE4SSProgram.hpp>

#include "CraftScannerHooks.hpp"
#include "CS_Common.hpp"

using namespace RC;

class CraftScannerMod : public CppUserModBase {
public:
    CraftScannerMod() {
        ModName        = STR("CraftScanner");
        ModVersion     = STR("0.1.0");
        ModDescription = STR("Shows a notification with crafting resources across the entire player inventory.");
        ModAuthors     = STR("madiko12");

        CraftScanner::Log(L"constructed");
    }

    ~CraftScannerMod() override = default;

    void on_unreal_init() override {
        CraftScanner::Log(L"on_unreal_init()");
        CraftScanner::Install();
    }

    void on_update() override {
        CraftScanner::Update();
    }
};

#define CS_API __declspec(dllexport)

extern "C" {
    CS_API CppUserModBase* start_mod() {
        return new CraftScannerMod();
    }

    CS_API void uninstall_mod(CppUserModBase* mod) {
        delete mod;
    }
}