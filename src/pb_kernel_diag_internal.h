/* Included after IsWatched in a fresh driver copy. All storage is resident .data. */
#include "pb_kernel_diag_shared.h"
static EX_SPIN_LOCK pbk_lock;
static PBK_EVENT pbk_events[PBK_CAPACITY];
static ULONG pbk_read, pbk_write, pbk_count;
static UINT64 pbk_written, pbk_overwritten;
static volatile LONG pbk_reader;

static void PbkFinish(PBK_EVENT *record, const FWPS_CLASSIFY_OUT0 *out)
{
    if (!record->frequency) return;
    record->end_qpc = KeQueryPerformanceCounter(NULL).QuadPart;
    record->rights_out = out->rights; record->action_out = out->actionType;
    KIRQL old = ExAcquireSpinLockExclusive(&pbk_lock);
    record->seq = ++pbk_written;
    if (pbk_count == PBK_CAPACITY) {
        pbk_read = (pbk_read + 1) % PBK_CAPACITY; --pbk_count; ++pbk_overwritten;
    }
    pbk_events[pbk_write] = *record;
    pbk_write = (pbk_write + 1) % PBK_CAPACITY; ++pbk_count;
    ExReleaseSpinLockExclusive(&pbk_lock, old);
}

static void PbkStart(PBK_EVENT *record, ADDRESS_FAMILY family,
    const FWPS_INCOMING_VALUES0 *values, const FWPS_INCOMING_METADATA_VALUES0 *meta,
    const FWPS_CLASSIFY_OUT0 *out, UINT32 protoIndex, UINT32 appIndex)
{
    RtlZeroMemory(record, sizeof(*record));
    if (family != AF_INET || values->incomingValue[protoIndex].value.type != FWP_UINT8 ||
        values->incomingValue[protoIndex].value.uint8 != IPPROTO_TCP ||
        values->incomingValue[appIndex].value.type != FWP_BYTE_BLOB_TYPE) return;
    const FWP_BYTE_BLOB *blob = values->incomingValue[appIndex].value.byteBlob;
    if (!blob || !blob->data || blob->size < sizeof(WCHAR)) return;
    ULONG chars = blob->size / sizeof(WCHAR);
    const WCHAR *path = (const WCHAR *)blob->data;
    while (chars && path[chars-1] == 0) --chars;
    if (!EndsWithI(path, chars, L"ctsTraffic.exe")) return;
    LARGE_INTEGER freq;
    record->start_qpc = KeQueryPerformanceCounter(&freq).QuadPart;
    record->frequency = freq.QuadPart;
    record->pid = FWPS_IS_METADATA_FIELD_PRESENT(meta, FWPS_METADATA_FIELD_PROCESS_ID) ? (UINT32)meta->processId : 0;
    record->enabled = (ULONG)gEnabled;
    record->rights_in = out->rights; record->action_in = out->actionType;
    record->redirect_state = 0xffffffff;
    record->redirect_present = FWPS_IS_METADATA_FIELD_PRESENT(meta, FWPS_METADATA_FIELD_REDIRECT_RECORD_HANDLE) ? 1 : 0;
    const FWP_VALUE0 *v;
    v = &values->incomingValue[FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_LOCAL_ADDRESS].value;
    if (v->type == FWP_UINT32) record->local_v4 = RtlUlongByteSwap(v->uint32);
    v = &values->incomingValue[FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_REMOTE_ADDRESS].value;
    if (v->type == FWP_UINT32) record->remote_v4 = RtlUlongByteSwap(v->uint32);
    v = &values->incomingValue[FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_LOCAL_PORT].value;
    if (v->type == FWP_UINT16) record->local_port = v->uint16;
    v = &values->incomingValue[FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_REMOTE_PORT].value;
    if (v->type == FWP_UINT16) record->remote_port = v->uint16;
}

static NTSTATUS PbkDrain(PVOID buffer, ULONG length, ULONG_PTR *information)
{
    *information = 0;
    if (!buffer || length < sizeof(PBK_HEADER) + sizeof(PBK_EVENT)) return STATUS_BUFFER_TOO_SMALL;
    LONG pid = (LONG)(ULONG_PTR)PsGetCurrentProcessId();
    LONG previous = InterlockedCompareExchange(&pbk_reader, pid, 0);
    if (previous && previous != pid) return STATUS_ACCESS_DENIED;
    ULONG maximum = (length - sizeof(PBK_HEADER)) / sizeof(PBK_EVENT);
    if (maximum > 64) maximum = 64;
    PBK_HEADER *header = (PBK_HEADER *)buffer;
    PBK_EVENT *events = (PBK_EVENT *)((UCHAR *)buffer + sizeof(*header));
    LARGE_INTEGER freq; (void)KeQueryPerformanceCounter(&freq);
    KIRQL old = ExAcquireSpinLockExclusive(&pbk_lock);
    RtlZeroMemory(header, sizeof(*header));
    header->magic = PBK_MAGIC; header->version = PBK_VERSION;
    header->record_size = sizeof(PBK_EVENT); header->capacity = PBK_CAPACITY;
    header->frequency = freq.QuadPart;
    while (header->count < maximum && pbk_count) {
        events[header->count++] = pbk_events[pbk_read];
        pbk_read = (pbk_read + 1) % PBK_CAPACITY; --pbk_count;
    }
    header->written = pbk_written; header->overwritten = pbk_overwritten; header->remaining = pbk_count;
    ExReleaseSpinLockExclusive(&pbk_lock, old);
    *information = sizeof(*header) + header->count * sizeof(PBK_EVENT);
    return STATUS_SUCCESS;
}
