/* Isolated diagnostic ABI; no packet data or raw kernel pointers. */
#ifndef PB_KERNEL_DIAG_SHARED_H
#define PB_KERNEL_DIAG_SHARED_H
#define PBK_MAGIC 0x50424b34u
#define PBK_VERSION 4u
#define PBK_CAPACITY 8192u
#define PBK_IOCTL 0x002263c0u
#pragma pack(push,8)
typedef struct PBK_EVENT {
    unsigned __int64 seq, start_qpc, end_qpc, frequency;
    unsigned long pid, reason, enabled, rights_in, rights_out, action_in, action_out;
    unsigned long redirect_present, redirect_state, acquire_called, acquire_status, writable_called, writable_status;
    unsigned long req_present, allocation_attempted, allocation_present;
    unsigned long context_size, context_pid, context_family, context_protocol, target_pid, handle_present;
    unsigned long apply_called, apply_returned;
    unsigned long local_v4, remote_v4, local_port, remote_port, new_v4, new_port;
} PBK_EVENT;
typedef struct PBK_HEADER {
    unsigned long magic, version, record_size, count, capacity, reserved;
    unsigned __int64 written, overwritten, remaining, frequency;
} PBK_HEADER;
#pragma pack(pop)
#endif
