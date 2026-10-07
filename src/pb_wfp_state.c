// Read-only management observation for the upstream ProxyBridge Driver GUIDs.
// No device IOCTL, service control, filter deletion or driver load.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>
#include <stdio.h>
#include <string.h>

static const GUID provider = {0x7c1b6a10,0x2e44,0x4e8b,{0x9e,0x21,0x0f,0x9a,0x5d,0x3c,0x1a,0x01}};
static const GUID sublayer = {0x7c1b6a10,0x2e44,0x4e8b,{0x9e,0x21,0x0f,0x9a,0x5d,0x3c,0x1a,0x02}};

static BOOL equal_guid(const GUID *a, const GUID *b) {
    return a && memcmp(a, b, sizeof(GUID)) == 0;
}

static BOOL known_callout(const GUID *key) {
    GUID candidate = provider;
    unsigned char suffix;
    for (suffix = 3; suffix <= 6; suffix++) {
        candidate.Data4[7] = suffix;
        if (equal_guid(key, &candidate)) return TRUE;
    }
    return FALSE;
}

int main(void) {
    HANDLE engine = NULL, enumeration = NULL;
    FWPM_SESSION0 session = {0};
    FWPM_PROVIDER0 *provider_info = NULL;
    FWPM_SUBLAYER0 *sublayer_info = NULL;
    FWPM_CALLOUT0 *callout_info = NULL;
    FWPM_FILTER0 **entries = NULL;
    GUID key = provider;
    UINT32 count = 0, i, visible_filters = 0, matching_filters = 0, callouts = 0;
    BOOL provider_present = FALSE, sublayer_present = FALSE, transaction = FALSE;
    DWORD error, cleanup;
    unsigned char suffix;
    session.txnWaitTimeoutInMSec = 2000;
    error = FwpmEngineOpen0(NULL, RPC_C_AUTHN_WINNT, NULL, &session, &engine);
    if (error) goto done;
    error = FwpmTransactionBegin0(engine, FWPM_TXN_READ_ONLY);
    if (error) goto done;
    transaction = TRUE;
    error = FwpmProviderGetByKey0(engine, &provider, &provider_info);
    if (error != ERROR_SUCCESS && error != FWP_E_PROVIDER_NOT_FOUND) goto done;
    provider_present = error == ERROR_SUCCESS;
    error = FwpmSubLayerGetByKey0(engine, &sublayer, &sublayer_info);
    if (error != ERROR_SUCCESS && error != FWP_E_SUBLAYER_NOT_FOUND) goto done;
    sublayer_present = error == ERROR_SUCCESS;
    for (suffix = 3; suffix <= 6; suffix++) {
        key.Data4[7] = suffix;
        error = FwpmCalloutGetByKey0(engine, &key, &callout_info);
        if (error != ERROR_SUCCESS && error != FWP_E_CALLOUT_NOT_FOUND) goto done;
        if (error == ERROR_SUCCESS) callouts++;
        if (callout_info) FwpmFreeMemory0((void **)&callout_info);
    }
    // NULL enumerates all visible filters, not just currently enabled ones.
    // WFP applies READ ACLs: successful enumeration is NOT global visibility proof.
    error = FwpmFilterCreateEnumHandle0(engine, NULL, &enumeration);
    if (error) goto done;
    for (;;) {
        error = FwpmFilterEnum0(engine, enumeration, 256, &entries, &count);
        if (error) goto done;
        if (count == 0) break;
        for (i = 0; i < count; i++) {
            const FWPM_FILTER0 *filter = entries[i];
            if (equal_guid(filter->providerKey, &provider) || equal_guid(&filter->subLayerKey, &sublayer) ||
                ((filter->action.type & FWP_ACTION_FLAG_CALLOUT) && known_callout(&filter->action.calloutKey))) matching_filters++;
        }
        visible_filters += count;
        FwpmFreeMemory0((void **)&entries);
        if (visible_filters > 1000000) { error = ERROR_MORE_DATA; goto done; }
    }
done:
    if (entries) FwpmFreeMemory0((void **)&entries);
    if (provider_info) FwpmFreeMemory0((void **)&provider_info);
    if (sublayer_info) FwpmFreeMemory0((void **)&sublayer_info);
    if (callout_info) FwpmFreeMemory0((void **)&callout_info);
    if (enumeration) { cleanup = FwpmFilterDestroyEnumHandle0(engine, enumeration); if (!error) error = cleanup; }
    if (transaction) { cleanup = FwpmTransactionAbort0(engine); if (!error) error = cleanup; }
    if (engine) { cleanup = FwpmEngineClose0(engine); if (!error) error = cleanup; }
    if (error) {
        printf("{\"schema_version\":1,\"query_complete\":false,\"win32_error\":%lu}\n", error);
        return 1;
    }
    printf("{\"schema_version\":1,\"query_complete\":true,\"win32_error\":0,"
        "\"provider_present\":%s,\"sublayer_present\":%s,\"known_callout_count\":%u,"
        "\"visible_filter_count\":%u,\"matching_filter_count\":%u,\"visibility_complete\":false}\n",
        provider_present ? "true" : "false", sublayer_present ? "true" : "false",
        callouts, visible_filters, matching_filters);
    return 0;
}
