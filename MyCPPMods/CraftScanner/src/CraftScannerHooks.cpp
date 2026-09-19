#include "CraftScannerHooks.hpp"
#include "CS_Common.hpp"
#include "Config.hpp"
#include "Notification.hpp"
#include "KeyMapper.hpp"

#include <algorithm>
#include <unordered_map>
#include <cstring>

#include <Unreal/UFunction.hpp>
#include <Unreal/NameTypes.hpp>
#include <UE4SSProgram.hpp>
#include <Input/Handler.hpp>

namespace CraftScanner {

volatile bool g_bTeardownDetected = false;
static bool g_installed = false;

// ------------------------------------------------------------
// FName -> wstring
// ------------------------------------------------------------
std::wstring RawFNameToString(const RawFName& raw) {
    if (raw.ComparisonIndex == 0) return {};
    if (raw.ComparisonIndex > 0x80000000u) return {};
    FName name = *reinterpret_cast<const FName*>(&raw);
    StringType s = name.ToString();
    return std::wstring(s.begin(), s.end());
}

// ------------------------------------------------------------
// Pawn resolution
// ------------------------------------------------------------
static UObject* TryGetPawnViaController() {
    UObject* pc = UObjectGlobals::FindFirstOf(STR("PlayerController"));
    if (!pc || IsPendingKill(pc)) return nullptr;

    for (const wchar_t* fname : { L"K2_GetPawn", L"GetPawn" }) {
        UFunction* fn = pc->GetFunctionByNameInChain(fname);
        if (!fn) continue;
        uint8_t buf[0x10] = {};
        if (!SafeProcessEvent(pc, fn, buf)) return nullptr;
        UObject* p = *reinterpret_cast<UObject**>(buf);
        if (p && !IsPendingKill(p)) return p;
    }
    return nullptr;
}

UObject* ResolveCurrentPawn() {
    if (g_bTeardownDetected) return nullptr;

    UObject* p = TryGetPawnViaController();
    if (p) return p;

    UObject* fallback = UObjectGlobals::FindFirstOf(STR("BP_PlayerCharacter_C"));
    if (!fallback || IsPendingKill(fallback)) return nullptr;
    return fallback;
}

// ------------------------------------------------------------
// POD-only container scan
// ------------------------------------------------------------
struct RawItem {
    uint32_t idIndex;
    uint32_t idNumber;
    uint32_t typeIndex;
    uint32_t typeNumber;
    int32_t  count;
};

struct RawScan {
    static constexpr int32_t kMax = 4096;
    RawItem items[kMax];
    int32_t count;
    int32_t containersScanned;
    int32_t containersWithItems;
    bool    truncated;
};

static void SafeScanContainers(UObject* jig, RawScan* out) {
    out->count = 0;
    out->containersScanned = 0;
    out->containersWithItems = 0;
    out->truncated = false;

    __try {
        RawTArray containers{};
        if (!SafeReadTArray(jig, Offsets::Jig_MainJigContainers, &containers)) return;
        if (!containers.Data || containers.Num <= 0 || containers.Num > 512) return;

        const uint8_t* cArr = reinterpret_cast<const uint8_t*>(containers.Data);

        for (int32_t ci = 0; ci < containers.Num; ++ci) {
            const uint8_t* c = cArr + (ci * Offsets::RCI_Size);
            out->containersScanned++;

            RawTArray items{};
            if (!SafeReadTArray(c, Offsets::RCI_ContainerItems, &items)) continue;
            if (!items.Data || items.Num <= 0 || items.Num > 4096) continue;

            out->containersWithItems++;
            const uint8_t* iArr = reinterpret_cast<const uint8_t*>(items.Data);

            for (int32_t ii = 0; ii < items.Num; ++ii) {
                const uint8_t* it = iArr + (ii * Offsets::CPI_Size);

                uint8_t isContainer = 0;
                SafeRead(it, Offsets::CPI_IsContainer, &isContainer);
                if (isContainer) continue;

                void* da = SafeReadPtr(it, Offsets::CPI_ItemInfo + Offsets::RII_DataAsset);
                if (!da) continue;

                int32_t cnt = 1;
                SafeRead(it, Offsets::CPI_ItemInfo + Offsets::RII_Count, &cnt);
                if (cnt <= 0) cnt = 1;

                RawFName rawId{};
                RawFName rawType{};
                SafeReadFName(da, Offsets::DA_ItemId, &rawId);
                SafeReadFName(da, Offsets::DA_ItemType, &rawType);
                if (rawId.ComparisonIndex == 0) continue;

                if (out->count >= RawScan::kMax) { out->truncated = true; return; }

                RawItem& e = out->items[out->count++];
                e.idIndex    = rawId.ComparisonIndex;
                e.idNumber   = rawId.Number;
                e.typeIndex  = rawType.ComparisonIndex;
                e.typeNumber = rawType.Number;
                e.count      = cnt;
            }
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        out->count = -1;
    }
}

// ------------------------------------------------------------
// Aggregation
// ------------------------------------------------------------
struct ResourceEntry {
    int64_t      Count = 0;
    std::wstring Id;
    std::wstring Type;
};

static bool MatchesAny(const std::wstring& v,
                       const std::vector<std::wstring>& list) {
    for (const auto& s : list) {
        if (v == s) return true;
        if (v.find(s) != std::wstring::npos) return true;
    }
    return false;
}

static bool PassesFilter(const std::wstring& id,
                         const std::wstring& type,
                         const CSConfig& cfg) {
    if (cfg.ShowAll) return true;
    if (!cfg.IncludeItemIds.empty() && MatchesAny(id, cfg.IncludeItemIds)) return true;
    if (!cfg.IncludeTypes.empty()   && MatchesAny(type, cfg.IncludeTypes)) return true;
    if (cfg.IncludeTypes.empty() && cfg.IncludeItemIds.empty()) {
        if (type.find(L"Material") != std::wstring::npos) return true;
        if (type.find(L"Tool")     != std::wstring::npos) return true;
    }
    return false;
}

static std::wstring BuildReport(
    std::unordered_map<std::wstring, ResourceEntry>& res,
    const CSConfig& cfg) {

    std::vector<ResourceEntry> list;
    list.reserve(res.size());
    for (auto& [id, e] : res) {
        if (!PassesFilter(id, e.Type, cfg)) continue;
        list.push_back(e);
    }

    if (cfg.SortByCount) {
        std::sort(list.begin(), list.end(),
            [](const ResourceEntry& a, const ResourceEntry& b){
                return a.Count > b.Count;
            });
    } else {
        std::sort(list.begin(), list.end(),
            [](const ResourceEntry& a, const ResourceEntry& b){
                return a.Id < b.Id;
            });
    }

    std::wstring out = cfg.Title + L"\n\n";
    int shown = 0;
    for (auto& e : list) {
        if (shown >= cfg.MaxLines) {
            out += L"... and " + std::to_wstring(list.size() - shown) + L" more\n";
            break;
        }
        out += L"  " + e.Id + L" x" + std::to_wstring(e.Count) + L"\n";
        ++shown;
    }
    if (shown == 0) out += L"  (no matching resources)\n";
    return out;
}

// ------------------------------------------------------------
// Hotkey handler
// ------------------------------------------------------------
static void OnShowResources() {
    if (g_bTeardownDetected) return;

    CSConfig cfg = LoadConfig();
    if (!cfg.Enabled) return;

    Log(L"hotkey pressed");

    UObject* pawn = ResolveCurrentPawn();
    if (!pawn) { Log(L"FAILED: no pawn"); return; }

    void* jigRaw = SafeReadPtr(pawn, Offsets::Player_JigMultiComponent);
    if (!jigRaw) { Log(L"FAILED: no jig component @0x07F0"); return; }

    RawScan raw;
    SafeScanContainers(reinterpret_cast<UObject*>(jigRaw), &raw);

    if (raw.count < 0) {
        g_bTeardownDetected = true;
        Log(L"AV during scan - teardown flag set");
        return;
    }

    Log(L"scanned containers: " + std::to_wstring(raw.containersScanned)
        + L", with items: " + std::to_wstring(raw.containersWithItems));
    Log(L"collected " + std::to_wstring(raw.count) + L" raw items");
    if (raw.truncated) Log(L"WARNING: raw scan truncated at 4096 items");

    std::unordered_map<std::wstring, ResourceEntry> res;
    res.reserve(raw.count);

    for (int32_t i = 0; i < raw.count; ++i) {
        RawFName rId { raw.items[i].idIndex,   raw.items[i].idNumber   };
        RawFName rTp { raw.items[i].typeIndex, raw.items[i].typeNumber };
        std::wstring id   = RawFNameToString(rId);
        std::wstring type = RawFNameToString(rTp);
        if (id.empty()) continue;

        if (cfg.VerboseLog) {
            Log(L"  item[" + std::to_wstring(i) + L"] id='" + id
                + L"' type='" + type + L"' count=" + std::to_wstring(raw.items[i].count));
        }

        auto& e = res[id];
        e.Count += raw.items[i].count;
        if (e.Id.empty())  e.Id = id;
        if (!type.empty()) e.Type = type;
    }

    Log(L"unique ids: " + std::to_wstring(res.size()));

    std::wstring report = BuildReport(res, cfg);
    Notification::Show(report, cfg.DurationSec);
}

// ------------------------------------------------------------
// Install
// ------------------------------------------------------------
void Install() {
    if (g_installed) return;
    g_installed = true;

    CSConfig cfg = LoadConfig();
    Log(std::wstring(L"Install() enabled=") + (cfg.Enabled ? L"true" : L"false"));

    auto key = MapKeyName(cfg.Hotkey);
    if (!key) { Log(L"Install() invalid hotkey: " + cfg.Hotkey); return; }

    UE4SSProgram::get_program().register_keydown_event(*key, [](){ OnShowResources(); });

    Log(L"Install() hotkey registered: " + cfg.Hotkey);
}

void Update() {}

} // namespace CraftScanner