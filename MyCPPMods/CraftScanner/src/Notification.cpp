#include "Notification.hpp"
#include "CS_Common.hpp"

#include <cstring>
#include <Unreal/UFunction.hpp>

namespace CraftScanner {
namespace Notification {

struct FTextParams {
    uint8_t buf[0x20];
};

static UObject* GetKismetTextLibrary() {
    return UObjectGlobals::StaticFindObject(
        nullptr, nullptr,
        STR("/Script/Engine.Default__KismetTextLibrary"));
}

// Build FText via KismetTextLibrary::Conv_StringToText
static bool MakeFText(const std::wstring& text, uint8_t out[16]) {
    UObject* ktl = GetKismetTextLibrary();
    if (!ktl) { Log(L"Notify: KismetTextLibrary not found"); return false; }

    UFunction* fn = ktl->GetFunctionByNameInChain(STR("Conv_StringToText"));
    if (!fn) { Log(L"Notify: Conv_StringToText not found"); return false; }

    FTextParams p{};

    // FString layout inside params: [wchar_t* Data][int32 Num][int32 Max]
    // Use the static-wide-buffer trick: write directly into a thread-local
    // buffer and point FString at it. This avoids relying on StringType's
    // internal layout matching FString.
    static thread_local wchar_t s_buf[4096];
    size_t n = text.size();
    if (n > 4094) n = 4094;
    std::wmemcpy(s_buf, text.c_str(), n);
    s_buf[n] = 0;

    *reinterpret_cast<wchar_t**>(p.buf + 0x00) = s_buf;
    *reinterpret_cast<int32_t*>(p.buf + 0x08) = static_cast<int32_t>(n);
    *reinterpret_cast<int32_t*>(p.buf + 0x0C) = static_cast<int32_t>(n) + 1;

    if (!SafeProcessEvent(ktl, fn, p.buf)) return false;

    std::memcpy(out, p.buf + 0x10, 16);
    return true;
}

bool Show(const std::wstring& message, double durationSec) {
    if (g_bTeardownDetected) return false;

    UObject* pawn = ResolveCurrentPawn();
    if (!pawn) { Log(L"Notify: no pawn"); return false; }

    UFunction* fn = pawn->GetFunctionByNameInChain(STR("CreateNotificationUI"));
    if (!fn) { Log(L"Notify: CreateNotificationUI not found"); return false; }

    uint8_t ftext[16] = {};
    if (!MakeFText(message, ftext)) return false;

    // Params: FText(16) | UTexture2D*(8) | FLinearColor(16) | double(8)
    uint8_t buf[0x40] = {};
    std::memcpy(buf + 0x00, ftext, 16);
    *reinterpret_cast<void**>(buf + 0x10)   = nullptr;
    *reinterpret_cast<float*>(buf + 0x18)   = 1.0f;
    *reinterpret_cast<float*>(buf + 0x1C)   = 1.0f;
    *reinterpret_cast<float*>(buf + 0x20)   = 1.0f;
    *reinterpret_cast<float*>(buf + 0x24)   = 1.0f;
    *reinterpret_cast<double*>(buf + 0x28)  = durationSec;

    if (!SafeProcessEvent(pawn, fn, buf)) {
        Log(L"Notify: ProcessEvent raised");
        return false;
    }

    Log(L"Notify: shown");
    return true;
}

} // namespace Notification
} // namespace CraftScanner