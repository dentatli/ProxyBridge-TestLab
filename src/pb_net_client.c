#define WIN32_LEAN_AND_MEAN
#define _CRT_SECURE_NO_WARNINGS
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <bcrypt.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TEXT 256
#define MAX_PATH_TEXT 32768
#define MAX_PAYLOAD 1024
#define SHA256_HEX 65

typedef enum { MODE_NONE, MODE_SINGLE, MODE_ISSUE209, MODE_ISSUE206 } TEST_MODE;
typedef enum { PROTO_NONE, PROTO_TCP, PROTO_UDP } NET_PROTOCOL;
typedef enum { UDP_CONNECTED, UDP_UNCONNECTED } UDP_MODE;
typedef enum { CLOSE_NONE, CLOSE_GRACEFUL, CLOSE_ABORTIVE } CLOSE_MODE;
typedef enum { TCP_PEER_EXACT, TCP_PEER_RECORD_ONLY } TCP_PEER_POLICY;
typedef enum { ACTION_DIRECT, ACTION_PROXY, ACTION_BLOCK } EXPECTED_ACTION;
typedef enum { EXPECT_ECHO, EXPECT_NO_ECHO } EXPECT_OUTCOME;

typedef struct CONFIG {
    TEST_MODE mode;
    NET_PROTOCOL protocol;
    NET_PROTOCOL first_protocol;
    UDP_MODE udp_mode;
    CLOSE_MODE close_mode;
    TCP_PEER_POLICY tcp_peer_policy;
    EXPECTED_ACTION expected_action;
    EXPECT_OUTCOME expect;
    TCP_PEER_POLICY first_tcp_peer_policy;
    TCP_PEER_POLICY second_tcp_peer_policy;
    EXPECTED_ACTION first_expected_action;
    EXPECTED_ACTION second_expected_action;
    EXPECT_OUTCOME first_expect;
    EXPECT_OUTCOME second_expect;
    int family;
    char local_ip[INET6_ADDRSTRLEN];
    unsigned short local_port;
    char remote_ip[INET6_ADDRSTRLEN];
    unsigned short tcp_remote_port;
    unsigned short udp_remote_port;
    char first_remote_ip[INET6_ADDRSTRLEN];
    unsigned short first_remote_port;
    char second_remote_ip[INET6_ADDRSTRLEN];
    unsigned short second_remote_port;
    DWORD inter_flow_wait_ms;
    DWORD timeout_ms;
    unsigned int bind_retry_count;
    DWORD bind_retry_delay_ms;
    char test_id[MAX_TEXT];
    char run_id[MAX_TEXT];
    char jsonl_log[MAX_PATH_TEXT];
} CONFIG;

typedef struct FLOW_RECORD {
    const CONFIG *config;
    int sequence;
    NET_PROTOCOL protocol;
    TCP_PEER_POLICY tcp_peer_policy;
    EXPECTED_ACTION expected_action;
    EXPECT_OUTCOME expect;
    const char *phase;
    const char *udp_mode;
    const char *close_mode;
    char requested_local_ip[INET6_ADDRSTRLEN];
    unsigned short requested_local_port;
    char actual_local_ip[INET6_ADDRSTRLEN];
    unsigned short actual_local_port;
    char requested_remote_ip[INET6_ADDRSTRLEN];
    unsigned short requested_remote_port;
    char actual_remote_ip[INET6_ADDRSTRLEN];
    unsigned short actual_remote_port;
    int wsa_error;
    int bytes_sent;
    int bytes_received;
    char payload_sha256[SHA256_HEX];
    char response_sha256[SHA256_HEX];
    ULONGLONG timing_ms;
    const char *expected_result;
    char actual_result[MAX_TEXT];
} FLOW_RECORD;

static const char *mode_name(TEST_MODE value)
{
    if (value == MODE_SINGLE) return "single";
    if (value == MODE_ISSUE209) return "issue209";
    if (value == MODE_ISSUE206) return "issue206";
    return "unknown";
}

static const char *protocol_name(NET_PROTOCOL value)
{
    if (value == PROTO_TCP) return "TCP";
    if (value == PROTO_UDP) return "UDP";
    return "NONE";
}

static const char *close_name(CLOSE_MODE value)
{
    if (value == CLOSE_GRACEFUL) return "graceful";
    if (value == CLOSE_ABORTIVE) return "abortive";
    return "none";
}

static const char *tcp_peer_policy_name(TCP_PEER_POLICY value)
{
    return value == TCP_PEER_RECORD_ONLY ? "record-only" : "exact";
}

static const char *expected_action_name(EXPECTED_ACTION value)
{
    if (value == ACTION_PROXY) return "PROXY";
    if (value == ACTION_BLOCK) return "BLOCK";
    return "DIRECT";
}

static const char *expect_name(EXPECT_OUTCOME value)
{
    return value == EXPECT_NO_ECHO ? "no-echo" : "echo";
}

static void usage(const char *program)
{
    fprintf(stderr,
        "Usage: %s --mode single|issue209|issue206 --family 4|6 "
        "--local-ip IP --local-port PORT --remote-ip IP "
        "--test-id ID --run-id ID --jsonl-log PATH [options]\n"
        "  single:   --protocol tcp|udp [--udp-mode connected|unconnected]\n"
        "  issue209: --first-protocol udp|tcp\n"
        "  issue206: --close-mode graceful|abortive [distinct remote options]\n"
        "Options: --tcp-remote-port 41002 --udp-remote-port 41001 "
        "--tcp-peer-policy exact|record-only --expected-action DIRECT|PROXY|BLOCK "
        "--expect echo|no-echo --timeout-ms 3000 --bind-retry-count 10 "
        "--bind-retry-delay-ms 50 --first-remote-ip IP --first-remote-port PORT "
        "--second-remote-ip IP --second-remote-port PORT --inter-flow-wait-ms MS\n"
        "Per-flow overrides: --first-expected-action DIRECT|PROXY|BLOCK "
        "--second-expected-action DIRECT|PROXY|BLOCK "
        "--first-expect echo|no-echo --second-expect echo|no-echo "
        "--first-tcp-peer-policy exact|record-only "
        "--second-tcp-peer-policy exact|record-only\n",
        program);
}

static int copy_text(char *destination, size_t capacity, const char *source)
{
    size_t length;
    if (!destination || !source || capacity == 0) return 0;
    length = strlen(source);
    if (length == 0 || length >= capacity) return 0;
    memcpy(destination, source, length + 1);
    return 1;
}

static int parse_ulong(const char *text, unsigned long minimum,
    unsigned long maximum, unsigned long *value)
{
    char *end = NULL;
    unsigned long parsed;
    const char *cursor;
    if (!text || !*text) return 0;
    for (cursor = text; *cursor; ++cursor)
        if (*cursor < '0' || *cursor > '9') return 0;
    errno = 0;
    parsed = strtoul(text, &end, 10);
    if (errno || end == text || *end || parsed < minimum || parsed > maximum)
        return 0;
    *value = parsed;
    return 1;
}

static int parse_protocol(const char *text, NET_PROTOCOL *value)
{
    if (_stricmp(text, "tcp") == 0) *value = PROTO_TCP;
    else if (_stricmp(text, "udp") == 0) *value = PROTO_UDP;
    else return 0;
    return 1;
}

static int parse_tcp_peer_policy(const char *text, TCP_PEER_POLICY *value)
{
    if (_stricmp(text, "exact") == 0) *value = TCP_PEER_EXACT;
    else if (_stricmp(text, "record-only") == 0) *value = TCP_PEER_RECORD_ONLY;
    else return 0;
    return 1;
}

static int parse_expected_action(const char *text, EXPECTED_ACTION *value)
{
    if (_stricmp(text, "DIRECT") == 0) *value = ACTION_DIRECT;
    else if (_stricmp(text, "PROXY") == 0) *value = ACTION_PROXY;
    else if (_stricmp(text, "BLOCK") == 0) *value = ACTION_BLOCK;
    else return 0;
    return 1;
}

static int parse_expect(const char *text, EXPECT_OUTCOME *value)
{
    if (_stricmp(text, "echo") == 0) *value = EXPECT_ECHO;
    else if (_stricmp(text, "no-echo") == 0) *value = EXPECT_NO_ECHO;
    else return 0;
    return 1;
}

static int parse_arguments(int argc, char **argv, CONFIG *config)
{
    int index;
    int have_local_port = 0;
    int have_first_remote_port = 0;
    int have_second_remote_port = 0;
    int have_first_tcp_peer_policy = 0;
    int have_second_tcp_peer_policy = 0;
    int have_first_expected_action = 0;
    int have_second_expected_action = 0;
    int have_first_expect = 0;
    int have_second_expect = 0;
    memset(config, 0, sizeof(*config));
    config->family = AF_UNSPEC;
    config->udp_mode = UDP_CONNECTED;
    config->tcp_peer_policy = TCP_PEER_EXACT;
    config->expected_action = ACTION_DIRECT;
    config->expect = EXPECT_ECHO;
    config->tcp_remote_port = 41002;
    config->udp_remote_port = 41001;
    config->timeout_ms = 3000;
    config->bind_retry_count = 10;
    config->bind_retry_delay_ms = 50;

    for (index = 1; index < argc; index += 2) {
        const char *name = argv[index];
        const char *value;
        unsigned long number;
        if (index + 1 >= argc) return 0;
        value = argv[index + 1];
        if (strcmp(name, "--mode") == 0) {
            if (_stricmp(value, "single") == 0) config->mode = MODE_SINGLE;
            else if (_stricmp(value, "issue209") == 0) config->mode = MODE_ISSUE209;
            else if (_stricmp(value, "issue206") == 0) config->mode = MODE_ISSUE206;
            else return 0;
        } else if (strcmp(name, "--family") == 0) {
            if (strcmp(value, "4") == 0) config->family = AF_INET;
            else if (strcmp(value, "6") == 0) config->family = AF_INET6;
            else return 0;
        } else if (strcmp(name, "--protocol") == 0) {
            if (!parse_protocol(value, &config->protocol)) return 0;
        } else if (strcmp(name, "--first-protocol") == 0) {
            if (!parse_protocol(value, &config->first_protocol)) return 0;
        } else if (strcmp(name, "--udp-mode") == 0) {
            if (_stricmp(value, "connected") == 0) config->udp_mode = UDP_CONNECTED;
            else if (_stricmp(value, "unconnected") == 0) config->udp_mode = UDP_UNCONNECTED;
            else return 0;
        } else if (strcmp(name, "--close-mode") == 0) {
            if (_stricmp(value, "graceful") == 0) config->close_mode = CLOSE_GRACEFUL;
            else if (_stricmp(value, "abortive") == 0) config->close_mode = CLOSE_ABORTIVE;
            else return 0;
        } else if (strcmp(name, "--tcp-peer-policy") == 0) {
            if (!parse_tcp_peer_policy(value, &config->tcp_peer_policy)) return 0;
        } else if (strcmp(name, "--first-tcp-peer-policy") == 0) {
            if (!parse_tcp_peer_policy(value, &config->first_tcp_peer_policy)) return 0;
            have_first_tcp_peer_policy = 1;
        } else if (strcmp(name, "--second-tcp-peer-policy") == 0) {
            if (!parse_tcp_peer_policy(value, &config->second_tcp_peer_policy)) return 0;
            have_second_tcp_peer_policy = 1;
        } else if (strcmp(name, "--expected-action") == 0) {
            if (!parse_expected_action(value, &config->expected_action)) return 0;
        } else if (strcmp(name, "--first-expected-action") == 0) {
            if (!parse_expected_action(value, &config->first_expected_action)) return 0;
            have_first_expected_action = 1;
        } else if (strcmp(name, "--second-expected-action") == 0) {
            if (!parse_expected_action(value, &config->second_expected_action)) return 0;
            have_second_expected_action = 1;
        } else if (strcmp(name, "--expect") == 0) {
            if (!parse_expect(value, &config->expect)) return 0;
        } else if (strcmp(name, "--first-expect") == 0) {
            if (!parse_expect(value, &config->first_expect)) return 0;
            have_first_expect = 1;
        } else if (strcmp(name, "--second-expect") == 0) {
            if (!parse_expect(value, &config->second_expect)) return 0;
            have_second_expect = 1;
        } else if (strcmp(name, "--local-ip") == 0) {
            if (!copy_text(config->local_ip, sizeof(config->local_ip), value)) return 0;
        } else if (strcmp(name, "--remote-ip") == 0) {
            if (!copy_text(config->remote_ip, sizeof(config->remote_ip), value)) return 0;
        } else if (strcmp(name, "--local-port") == 0) {
            if (!parse_ulong(value, 0, 65535, &number)) return 0;
            config->local_port = (unsigned short)number;
            have_local_port = 1;
        } else if (strcmp(name, "--tcp-remote-port") == 0) {
            if (!parse_ulong(value, 1, 65535, &number)) return 0;
            config->tcp_remote_port = (unsigned short)number;
        } else if (strcmp(name, "--udp-remote-port") == 0) {
            if (!parse_ulong(value, 1, 65535, &number)) return 0;
            config->udp_remote_port = (unsigned short)number;
        } else if (strcmp(name, "--first-remote-ip") == 0) {
            if (!copy_text(config->first_remote_ip, sizeof(config->first_remote_ip), value)) return 0;
        } else if (strcmp(name, "--first-remote-port") == 0) {
            if (!parse_ulong(value, 1, 65535, &number)) return 0;
            config->first_remote_port = (unsigned short)number;
            have_first_remote_port = 1;
        } else if (strcmp(name, "--second-remote-ip") == 0) {
            if (!copy_text(config->second_remote_ip, sizeof(config->second_remote_ip), value)) return 0;
        } else if (strcmp(name, "--second-remote-port") == 0) {
            if (!parse_ulong(value, 1, 65535, &number)) return 0;
            config->second_remote_port = (unsigned short)number;
            have_second_remote_port = 1;
        } else if (strcmp(name, "--inter-flow-wait-ms") == 0) {
            if (!parse_ulong(value, 0, 60000, &number)) return 0;
            config->inter_flow_wait_ms = (DWORD)number;
        } else if (strcmp(name, "--timeout-ms") == 0) {
            if (!parse_ulong(value, 1, 60000, &number)) return 0;
            config->timeout_ms = (DWORD)number;
        } else if (strcmp(name, "--bind-retry-count") == 0) {
            if (!parse_ulong(value, 0, 1000, &number)) return 0;
            config->bind_retry_count = (unsigned int)number;
        } else if (strcmp(name, "--bind-retry-delay-ms") == 0) {
            if (!parse_ulong(value, 0, 60000, &number)) return 0;
            config->bind_retry_delay_ms = (DWORD)number;
        } else if (strcmp(name, "--test-id") == 0) {
            if (!copy_text(config->test_id, sizeof(config->test_id), value)) return 0;
        } else if (strcmp(name, "--run-id") == 0) {
            if (!copy_text(config->run_id, sizeof(config->run_id), value)) return 0;
        } else if (strcmp(name, "--jsonl-log") == 0) {
            if (!copy_text(config->jsonl_log, sizeof(config->jsonl_log), value)) return 0;
        } else return 0;
    }

    if (config->mode == MODE_NONE || config->family == AF_UNSPEC ||
        !config->local_ip[0] || !config->remote_ip[0] || !have_local_port ||
        !config->test_id[0] || !config->run_id[0] || !config->jsonl_log[0]) return 0;
    if (config->mode == MODE_SINGLE && config->protocol == PROTO_NONE) return 0;
    if (config->mode == MODE_ISSUE209 && config->first_protocol == PROTO_NONE) return 0;
    if (config->mode == MODE_ISSUE206 && config->close_mode == CLOSE_NONE) return 0;
    if (!have_first_tcp_peer_policy) config->first_tcp_peer_policy = config->tcp_peer_policy;
    if (!have_second_tcp_peer_policy) config->second_tcp_peer_policy = config->tcp_peer_policy;
    if (!have_first_expected_action) config->first_expected_action = config->expected_action;
    if (!have_second_expected_action) config->second_expected_action = config->expected_action;
    if (!have_first_expect) config->first_expect = config->expect;
    if (!have_second_expect) config->second_expect = config->expect;
    if (config->mode == MODE_ISSUE209 && config->first_expect != EXPECT_ECHO) return 0;
    if (!config->first_remote_ip[0] &&
        !copy_text(config->first_remote_ip, sizeof(config->first_remote_ip), config->remote_ip)) return 0;
    if (!config->second_remote_ip[0] &&
        !copy_text(config->second_remote_ip, sizeof(config->second_remote_ip), config->remote_ip)) return 0;
    if (!have_first_remote_port) config->first_remote_port = config->tcp_remote_port;
    if (!have_second_remote_port) config->second_remote_port = config->tcp_remote_port;
    return 1;
}

static int make_endpoint(int family, const char *ip, unsigned short port,
    SOCKADDR_STORAGE *storage, int *length)
{
    memset(storage, 0, sizeof(*storage));
    if (family == AF_INET) {
        struct sockaddr_in *address = (struct sockaddr_in *)storage;
        address->sin_family = AF_INET;
        address->sin_port = htons(port);
        if (InetPtonA(AF_INET, ip, &address->sin_addr) != 1) return 0;
        *length = (int)sizeof(*address);
        return 1;
    }
    if (family == AF_INET6) {
        struct sockaddr_in6 *address = (struct sockaddr_in6 *)storage;
        address->sin6_family = AF_INET6;
        address->sin6_port = htons(port);
        if (InetPtonA(AF_INET6, ip, &address->sin6_addr) != 1) return 0;
        *length = (int)sizeof(*address);
        return 1;
    }
    return 0;
}

static int endpoint_parts(const SOCKADDR_STORAGE *storage, char *ip,
    size_t ip_capacity, unsigned short *port)
{
    if (storage->ss_family == AF_INET) {
        const struct sockaddr_in *address = (const struct sockaddr_in *)storage;
        if (!InetNtopA(AF_INET, &address->sin_addr, ip, (DWORD)ip_capacity)) return 0;
        *port = ntohs(address->sin_port);
        return 1;
    }
    if (storage->ss_family == AF_INET6) {
        const struct sockaddr_in6 *address = (const struct sockaddr_in6 *)storage;
        if (!InetNtopA(AF_INET6, &address->sin6_addr, ip, (DWORD)ip_capacity)) return 0;
        *port = ntohs(address->sin6_port);
        return 1;
    }
    return 0;
}

static int endpoints_equal(const SOCKADDR_STORAGE *left, const SOCKADDR_STORAGE *right)
{
    if (left->ss_family != right->ss_family) return 0;
    if (left->ss_family == AF_INET) {
        const struct sockaddr_in *a = (const struct sockaddr_in *)left;
        const struct sockaddr_in *b = (const struct sockaddr_in *)right;
        return a->sin_port == b->sin_port &&
            memcmp(&a->sin_addr, &b->sin_addr, sizeof(a->sin_addr)) == 0;
    }
    if (left->ss_family == AF_INET6) {
        const struct sockaddr_in6 *a = (const struct sockaddr_in6 *)left;
        const struct sockaddr_in6 *b = (const struct sockaddr_in6 *)right;
        return a->sin6_port == b->sin6_port &&
            memcmp(&a->sin6_addr, &b->sin6_addr, sizeof(a->sin6_addr)) == 0;
    }
    return 0;
}

static int sha256_bytes(const unsigned char *data, ULONG length, char output[SHA256_HEX])
{
    BCRYPT_ALG_HANDLE algorithm = NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    PUCHAR object = NULL;
    DWORD object_length = 0, result_length = 0;
    UCHAR digest[32];
    NTSTATUS status;
    unsigned int index;
    status = BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, NULL, 0);
    if (status < 0) goto cleanup;
    status = BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
        (PUCHAR)&object_length, sizeof(object_length), &result_length, 0);
    if (status < 0) goto cleanup;
    object = (PUCHAR)HeapAlloc(GetProcessHeap(), 0, object_length);
    if (!object) { status = (NTSTATUS)-1; goto cleanup; }
    status = BCryptCreateHash(algorithm, &hash, object, object_length, NULL, 0, 0);
    if (status < 0) goto cleanup;
    status = BCryptHashData(hash, (PUCHAR)data, length, 0);
    if (status < 0) goto cleanup;
    status = BCryptFinishHash(hash, digest, sizeof(digest), 0);
    if (status < 0) goto cleanup;
    for (index = 0; index < sizeof(digest); ++index)
        sprintf(output + index * 2, "%02x", (unsigned int)digest[index]);
    output[64] = '\0';
cleanup:
    if (hash) BCryptDestroyHash(hash);
    if (object) HeapFree(GetProcessHeap(), 0, object);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    return status >= 0;
}

static void json_string(FILE *file, const char *text)
{
    const unsigned char *cursor = (const unsigned char *)(text ? text : "");
    fputc('"', file);
    while (*cursor) {
        switch (*cursor) {
        case '"': fputs("\\\"", file); break;
        case '\\': fputs("\\\\", file); break;
        case '\b': fputs("\\b", file); break;
        case '\f': fputs("\\f", file); break;
        case '\n': fputs("\\n", file); break;
        case '\r': fputs("\\r", file); break;
        case '\t': fputs("\\t", file); break;
        default:
            if (*cursor < 0x20) fprintf(file, "\\u%04x", (unsigned int)*cursor);
            else fputc(*cursor, file);
        }
        ++cursor;
    }
    fputc('"', file);
}

static void json_pair(FILE *file, const char *name, const char *value)
{
    json_string(file, name); fputc(':', file); json_string(file, value);
}

static int write_record(FILE *file, const FLOW_RECORD *record)
{
    SYSTEMTIME now;
    GetSystemTime(&now);
    fputc('{', file);
    fprintf(file, "\"timestamp_utc\":\"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ\",",
        (unsigned int)now.wYear, (unsigned int)now.wMonth,
        (unsigned int)now.wDay, (unsigned int)now.wHour,
        (unsigned int)now.wMinute, (unsigned int)now.wSecond,
        (unsigned int)now.wMilliseconds);
    json_pair(file, "test_id", record->config->test_id); fputc(',', file);
    json_pair(file, "run_id", record->config->run_id); fputc(',', file);
    json_pair(file, "mode", mode_name(record->config->mode));
    fprintf(file, ",\"sequence\":%d,", record->sequence);
    json_pair(file, "phase", record->phase); fputc(',', file);
    json_pair(file, "expected_action", expected_action_name(record->expected_action)); fputc(',', file);
    json_pair(file, "expect", expect_name(record->expect)); fputc(',', file);
    json_pair(file, "family", record->config->family == AF_INET ? "IPv4" : "IPv6"); fputc(',', file);
    json_pair(file, "protocol", protocol_name(record->protocol)); fputc(',', file);
    json_pair(file, "tcp_peer_policy", record->protocol == PROTO_TCP ?
        tcp_peer_policy_name(record->tcp_peer_policy) : "n/a"); fputc(',', file);
    json_pair(file, "udp_mode", record->udp_mode); fputc(',', file);
    json_pair(file, "close_mode", record->close_mode); fputc(',', file);
    json_pair(file, "requested_local_ip", record->requested_local_ip);
    fprintf(file, ",\"requested_local_port\":%u,", (unsigned int)record->requested_local_port);
    json_pair(file, "actual_local_ip", record->actual_local_ip);
    fprintf(file, ",\"actual_local_port\":%u,", (unsigned int)record->actual_local_port);
    json_pair(file, "requested_remote_ip", record->requested_remote_ip);
    fprintf(file, ",\"requested_remote_port\":%u,", (unsigned int)record->requested_remote_port);
    json_pair(file, "actual_remote_ip", record->actual_remote_ip);
    fprintf(file, ",\"actual_remote_port\":%u,\"wsa_error\":%d,",
        (unsigned int)record->actual_remote_port, record->wsa_error);
    fprintf(file, "\"bytes_sent\":%d,\"bytes_received\":%d,",
        record->bytes_sent, record->bytes_received);
    json_pair(file, "payload_sha256", record->payload_sha256); fputc(',', file);
    json_pair(file, "response_sha256", record->response_sha256);
    fprintf(file, ",\"timing_ms\":%llu,", (unsigned long long)record->timing_ms);
    json_pair(file, "expected_result", record->expected_result); fputc(',', file);
    json_pair(file, "actual_result", record->actual_result);
    fputs("}\n", file);
    return fflush(file) == 0 && !ferror(file);
}

static int connect_with_timeout(SOCKET socket_handle,
    const SOCKADDR_STORAGE *remote, int remote_length, DWORD timeout_ms,
    int *wsa_error)
{
    u_long nonblocking = 1;
    int result;
    if (ioctlsocket(socket_handle, FIONBIO, &nonblocking) == SOCKET_ERROR) {
        *wsa_error = WSAGetLastError(); return 0;
    }
    result = connect(socket_handle, (const struct sockaddr *)remote, remote_length);
    if (result == SOCKET_ERROR) {
        int error = WSAGetLastError();
        if (error != WSAEWOULDBLOCK && error != WSAEINPROGRESS && error != WSAEALREADY) {
            *wsa_error = error; return 0;
        }
        {
            fd_set write_set, error_set;
            struct timeval timeout;
            int selected, socket_error = 0, option_length = sizeof(socket_error);
            FD_ZERO(&write_set); FD_ZERO(&error_set);
            FD_SET(socket_handle, &write_set); FD_SET(socket_handle, &error_set);
            timeout.tv_sec = (long)(timeout_ms / 1000);
            timeout.tv_usec = (long)((timeout_ms % 1000) * 1000);
            selected = select(0, NULL, &write_set, &error_set, &timeout);
            if (selected == SOCKET_ERROR) { *wsa_error = WSAGetLastError(); return 0; }
            if (selected == 0) { *wsa_error = WSAETIMEDOUT; return 0; }
            if (getsockopt(socket_handle, SOL_SOCKET, SO_ERROR,
                (char *)&socket_error, &option_length) == SOCKET_ERROR) {
                *wsa_error = WSAGetLastError(); return 0;
            }
            if (socket_error) { *wsa_error = socket_error; return 0; }
        }
    }
    nonblocking = 0;
    if (ioctlsocket(socket_handle, FIONBIO, &nonblocking) == SOCKET_ERROR) {
        *wsa_error = WSAGetLastError(); return 0;
    }
    *wsa_error = 0;
    return 1;
}

static SOCKET create_bound_socket(const CONFIG *config, NET_PROTOCOL protocol,
    unsigned short local_port, unsigned int retry_count, FLOW_RECORD *record)
{
    unsigned int attempt;
    int type = protocol == PROTO_TCP ? SOCK_STREAM : SOCK_DGRAM;
    int ip_protocol = protocol == PROTO_TCP ? IPPROTO_TCP : IPPROTO_UDP;
    SOCKADDR_STORAGE local, actual;
    int local_length, actual_length;
    for (attempt = 0; attempt <= retry_count; ++attempt) {
        SOCKET socket_handle = socket(config->family, type, ip_protocol);
        if (socket_handle == INVALID_SOCKET) {
            record->wsa_error = WSAGetLastError(); return INVALID_SOCKET;
        }
        if (config->family == AF_INET6) {
            DWORD v6_only = 1;
            if (setsockopt(socket_handle, IPPROTO_IPV6, IPV6_V6ONLY,
                (const char *)&v6_only, sizeof(v6_only)) == SOCKET_ERROR) {
                record->wsa_error = WSAGetLastError(); closesocket(socket_handle);
                return INVALID_SOCKET;
            }
        }
        if (!make_endpoint(config->family, config->local_ip, local_port,
            &local, &local_length)) {
            record->wsa_error = WSAEINVAL; closesocket(socket_handle);
            return INVALID_SOCKET;
        }
        if (bind(socket_handle, (const struct sockaddr *)&local, local_length) == 0) {
            actual_length = sizeof(actual);
            memset(&actual, 0, sizeof(actual));
            if (getsockname(socket_handle, (struct sockaddr *)&actual, &actual_length) == SOCKET_ERROR ||
                !endpoint_parts(&actual, record->actual_local_ip,
                    sizeof(record->actual_local_ip), &record->actual_local_port)) {
                record->wsa_error = WSAGetLastError(); closesocket(socket_handle);
                return INVALID_SOCKET;
            }
            return socket_handle;
        }
        record->wsa_error = WSAGetLastError();
        closesocket(socket_handle);
        if (record->wsa_error != WSAEADDRINUSE || attempt == retry_count)
            return INVALID_SOCKET;
        Sleep(config->bind_retry_delay_ms);
    }
    return INVALID_SOCKET;
}

static int send_all(SOCKET socket_handle, const char *payload, int length, int *wsa_error)
{
    int total = 0;
    while (total < length) {
        int sent = send(socket_handle, payload + total, length - total, 0);
        if (sent == SOCKET_ERROR) { *wsa_error = WSAGetLastError(); return SOCKET_ERROR; }
        if (sent == 0) { *wsa_error = WSAECONNRESET; return SOCKET_ERROR; }
        total += sent;
    }
    return total;
}

static int recv_exact(SOCKET socket_handle, char *buffer, int length, int *wsa_error)
{
    int total = 0;
    while (total < length) {
        int received = recv(socket_handle, buffer + total, length - total, 0);
        if (received == SOCKET_ERROR) {
            *wsa_error = WSAGetLastError();
            return total > 0 ? total : SOCKET_ERROR;
        }
        if (received == 0) {
            *wsa_error = WSAECONNRESET;
            return total > 0 ? total : SOCKET_ERROR;
        }
        total += received;
    }
    return total;
}

static void initialize_record(FLOW_RECORD *record, const CONFIG *config,
    int sequence, const char *phase, NET_PROTOCOL protocol,
    unsigned short local_port, const char *remote_ip,
    unsigned short remote_port, EXPECTED_ACTION expected_action,
    EXPECT_OUTCOME expect, TCP_PEER_POLICY tcp_peer_policy)
{
    memset(record, 0, sizeof(*record));
    record->config = config;
    record->sequence = sequence;
    record->protocol = protocol;
    record->tcp_peer_policy = tcp_peer_policy;
    record->expected_action = expected_action;
    record->expect = expect;
    record->phase = phase;
    record->udp_mode = protocol == PROTO_UDP ?
        (config->udp_mode == UDP_CONNECTED ? "connected" : "unconnected") : "n/a";
    record->close_mode = "none";
    copy_text(record->requested_local_ip, sizeof(record->requested_local_ip), config->local_ip);
    record->requested_local_port = local_port;
    copy_text(record->requested_remote_ip, sizeof(record->requested_remote_ip), remote_ip);
    record->requested_remote_port = remote_port;
    record->expected_result = expect_name(expect);
    copy_text(record->actual_result, sizeof(record->actual_result), "fail:not_started");
}

static int perform_flow(const CONFIG *config, int sequence, const char *phase,
    NET_PROTOCOL protocol, unsigned short local_port, const char *remote_ip,
    unsigned short remote_port, unsigned int bind_retries,
    EXPECTED_ACTION expected_action, EXPECT_OUTCOME expect,
    TCP_PEER_POLICY tcp_peer_policy, SOCKET *kept_socket, FLOW_RECORD *record)
{
    SOCKET socket_handle = INVALID_SOCKET;
    SOCKADDR_STORAGE remote, actual_remote, response_source;
    int remote_length, actual_remote_length, response_source_length;
    int timeout_value = (int)config->timeout_ms;
    char payload[MAX_PAYLOAD], response[MAX_PAYLOAD];
    int payload_length, result;
    ULONGLONG started = GetTickCount64();
    int success = 0;

    initialize_record(record, config, sequence, phase, protocol, local_port,
        remote_ip, remote_port, expected_action, expect, tcp_peer_policy);
    payload_length = snprintf(payload, sizeof(payload),
        "PB_NET|test_id=%s|run_id=%s|sequence=%d|phase=%s|protocol=%s\n",
        config->test_id, config->run_id, sequence, phase, protocol_name(protocol));
    if (payload_length <= 0 || payload_length >= (int)sizeof(payload)) {
        record->wsa_error = WSAEMSGSIZE;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:payload_size");
        goto done;
    }
    if (!sha256_bytes((const unsigned char *)payload, (ULONG)payload_length,
        record->payload_sha256)) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:BCrypt_SHA256");
        goto done;
    }
    if (!make_endpoint(config->family, remote_ip,
        record->requested_remote_port, &remote, &remote_length)) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:remote_ip");
        goto done;
    }
    socket_handle = create_bound_socket(config, protocol, local_port,
        bind_retries, record);
    if (socket_handle == INVALID_SOCKET) {
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:bind");
        goto done;
    }
    if (setsockopt(socket_handle, SOL_SOCKET, SO_RCVTIMEO,
            (const char *)&timeout_value, sizeof(timeout_value)) == SOCKET_ERROR ||
        setsockopt(socket_handle, SOL_SOCKET, SO_SNDTIMEO,
            (const char *)&timeout_value, sizeof(timeout_value)) == SOCKET_ERROR) {
        record->wsa_error = WSAGetLastError();
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:timeout_option");
        goto done;
    }

    if (protocol == PROTO_TCP) {
        if (!connect_with_timeout(socket_handle, &remote, remote_length,
            config->timeout_ms, &record->wsa_error)) {
            if (expect == EXPECT_NO_ECHO) {
                copy_text(record->actual_result, sizeof(record->actual_result), "pass:no_echo_connect_failure");
                success = 1;
            } else {
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:connect");
            }
            goto done;
        }
        actual_remote_length = sizeof(actual_remote);
        memset(&actual_remote, 0, sizeof(actual_remote));
        if (getpeername(socket_handle, (struct sockaddr *)&actual_remote,
                &actual_remote_length) == SOCKET_ERROR) {
            record->wsa_error = WSAGetLastError();
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:getpeername");
            goto done;
        }
        if (!endpoint_parts(&actual_remote, record->actual_remote_ip,
                sizeof(record->actual_remote_ip), &record->actual_remote_port)) {
            record->wsa_error = WSAGetLastError();
            if (!record->wsa_error) record->wsa_error = WSAEINVAL;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:record_tcp_peer");
            goto done;
        }
        if (tcp_peer_policy == TCP_PEER_EXACT &&
            !endpoints_equal(&remote, &actual_remote)) {
            record->wsa_error = WSAEINVAL;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:tcp_peer_mismatch");
            goto done;
        }
        result = send_all(socket_handle, payload, payload_length, &record->wsa_error);
        if (result == SOCKET_ERROR) {
            if (expect == EXPECT_NO_ECHO) {
                copy_text(record->actual_result, sizeof(record->actual_result), "pass:no_echo_send_failure");
                success = 1;
            } else {
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:send");
            }
            goto done;
        }
        record->bytes_sent = result;
        result = recv_exact(socket_handle, response, payload_length, &record->wsa_error);
        if (result == SOCKET_ERROR) {
            if (expect == EXPECT_NO_ECHO) {
                copy_text(record->actual_result, sizeof(record->actual_result), "pass:no_echo_observed");
                success = 1;
            } else {
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:recv");
            }
            goto done;
        }
        record->bytes_received = result;
    } else {
        if (config->udp_mode == UDP_CONNECTED) {
            if (connect(socket_handle, (const struct sockaddr *)&remote, remote_length) == SOCKET_ERROR) {
                record->wsa_error = WSAGetLastError();
                if (expect == EXPECT_NO_ECHO) {
                    copy_text(record->actual_result, sizeof(record->actual_result), "pass:no_echo_udp_connect_failure");
                    success = 1;
                } else {
                    copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_connect");
                }
                goto done;
            }
        }
        result = config->udp_mode == UDP_CONNECTED ?
            send(socket_handle, payload, payload_length, 0) :
            sendto(socket_handle, payload, payload_length, 0,
                (const struct sockaddr *)&remote, remote_length);
        if (result == SOCKET_ERROR || result != payload_length) {
            record->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEMSGSIZE;
            if (expect == EXPECT_NO_ECHO) {
                copy_text(record->actual_result, sizeof(record->actual_result), "pass:no_echo_send_failure");
                success = 1;
            } else {
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:send");
            }
            goto done;
        }
        record->bytes_sent = result;
        response_source_length = sizeof(response_source);
        memset(&response_source, 0, sizeof(response_source));
        result = recvfrom(socket_handle, response, sizeof(response), 0,
            (struct sockaddr *)&response_source, &response_source_length);
        if (result == SOCKET_ERROR) {
            record->wsa_error = WSAGetLastError();
            if (expect == EXPECT_NO_ECHO) {
                copy_text(record->actual_result, sizeof(record->actual_result), "pass:no_echo_observed");
                success = 1;
            } else {
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:recvfrom");
            }
            goto done;
        }
        record->bytes_received = result;
        if (!endpoint_parts(&response_source, record->actual_remote_ip,
                sizeof(record->actual_remote_ip), &record->actual_remote_port) ||
            !endpoints_equal(&remote, &response_source)) {
            record->wsa_error = WSAEINVAL;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_response_source"); goto done;
        }
    }
    if (!sha256_bytes((const unsigned char *)response,
        (ULONG)record->bytes_received, record->response_sha256)) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:BCrypt_response_SHA256");
        goto done;
    }
    if (expect == EXPECT_NO_ECHO) {
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:unexpected_response");
        goto done;
    }
    if (record->bytes_received != payload_length ||
        memcmp(response, payload, (size_t)payload_length) != 0 ||
        strcmp(record->payload_sha256, record->response_sha256) != 0) {
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:payload_mismatch");
        goto done;
    }
    record->wsa_error = 0;
    copy_text(record->actual_result, sizeof(record->actual_result), "pass");
    success = 1;
done:
    record->timing_ms = GetTickCount64() - started;
    if (kept_socket && success) {
        *kept_socket = socket_handle;
        socket_handle = INVALID_SOCKET;
    }
    if (socket_handle != INVALID_SOCKET) closesocket(socket_handle);
    return success;
}

static int perform_held_recheck(const CONFIG *config, SOCKET socket_handle,
    NET_PROTOCOL protocol, unsigned short local_port, const char *remote_ip,
    unsigned short remote_port, EXPECTED_ACTION expected_action,
    EXPECT_OUTCOME expect, TCP_PEER_POLICY tcp_peer_policy, FLOW_RECORD *record)
{
    SOCKADDR_STORAGE remote, actual_remote, actual_local, response_source;
    int remote_length, actual_remote_length, actual_local_length;
    int response_source_length;
    char payload[MAX_PAYLOAD], response[MAX_PAYLOAD];
    int payload_length, result;
    ULONGLONG started = GetTickCount64();
    int success = 0;

    initialize_record(record, config, 3, "held_recheck", protocol,
        local_port, remote_ip, remote_port, expected_action, expect, tcp_peer_policy);
    record->close_mode = "held_active";
    payload_length = snprintf(payload, sizeof(payload),
        "PB_NET|test_id=%s|run_id=%s|sequence=3|phase=held_recheck|protocol=%s\n",
        config->test_id, config->run_id, protocol_name(protocol));
    if (payload_length <= 0 || payload_length >= (int)sizeof(payload)) {
        record->wsa_error = WSAEMSGSIZE;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:payload_size");
        goto done;
    }
    if (!sha256_bytes((const unsigned char *)payload, (ULONG)payload_length,
        record->payload_sha256)) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:BCrypt_SHA256");
        goto done;
    }
    if (!make_endpoint(config->family, remote_ip, remote_port,
        &remote, &remote_length)) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:remote_ip");
        goto done;
    }
    actual_local_length = sizeof(actual_local);
    memset(&actual_local, 0, sizeof(actual_local));
    if (getsockname(socket_handle, (struct sockaddr *)&actual_local,
            &actual_local_length) == SOCKET_ERROR ||
        !endpoint_parts(&actual_local, record->actual_local_ip,
            sizeof(record->actual_local_ip), &record->actual_local_port)) {
        record->wsa_error = WSAGetLastError();
        if (!record->wsa_error) record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:getsockname");
        goto done;
    }

    if (protocol == PROTO_TCP) {
        actual_remote_length = sizeof(actual_remote);
        memset(&actual_remote, 0, sizeof(actual_remote));
        if (getpeername(socket_handle, (struct sockaddr *)&actual_remote,
                &actual_remote_length) == SOCKET_ERROR) {
            record->wsa_error = WSAGetLastError();
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:getpeername");
            goto done;
        }
        if (!endpoint_parts(&actual_remote, record->actual_remote_ip,
                sizeof(record->actual_remote_ip), &record->actual_remote_port)) {
            record->wsa_error = WSAGetLastError();
            if (!record->wsa_error) record->wsa_error = WSAEINVAL;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:record_tcp_peer");
            goto done;
        }
        if (tcp_peer_policy == TCP_PEER_EXACT &&
            !endpoints_equal(&remote, &actual_remote)) {
            record->wsa_error = WSAEINVAL;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:tcp_peer_mismatch");
            goto done;
        }
        result = send_all(socket_handle, payload, payload_length, &record->wsa_error);
        if (result == SOCKET_ERROR) {
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:send");
            goto done;
        }
        record->bytes_sent = result;
        result = recv_exact(socket_handle, response, payload_length, &record->wsa_error);
        if (result == SOCKET_ERROR) {
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:recv");
            goto done;
        }
        record->bytes_received = result;
    } else {
        result = config->udp_mode == UDP_CONNECTED ?
            send(socket_handle, payload, payload_length, 0) :
            sendto(socket_handle, payload, payload_length, 0,
                (const struct sockaddr *)&remote, remote_length);
        if (result == SOCKET_ERROR || result != payload_length) {
            record->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEMSGSIZE;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:send");
            goto done;
        }
        record->bytes_sent = result;
        response_source_length = sizeof(response_source);
        memset(&response_source, 0, sizeof(response_source));
        result = recvfrom(socket_handle, response, sizeof(response), 0,
            (struct sockaddr *)&response_source, &response_source_length);
        if (result == SOCKET_ERROR) {
            record->wsa_error = WSAGetLastError();
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:recvfrom");
            goto done;
        }
        record->bytes_received = result;
        if (!endpoint_parts(&response_source, record->actual_remote_ip,
                sizeof(record->actual_remote_ip), &record->actual_remote_port) ||
            !endpoints_equal(&remote, &response_source)) {
            record->wsa_error = WSAEINVAL;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_response_source");
            goto done;
        }
    }
    if (!sha256_bytes((const unsigned char *)response,
        (ULONG)record->bytes_received, record->response_sha256)) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:BCrypt_response_SHA256");
        goto done;
    }
    if (record->bytes_received != payload_length ||
        memcmp(response, payload, (size_t)payload_length) != 0 ||
        strcmp(record->payload_sha256, record->response_sha256) != 0) {
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:payload_mismatch");
        goto done;
    }
    record->wsa_error = 0;
    copy_text(record->actual_result, sizeof(record->actual_result), "pass");
    success = 1;
done:
    record->timing_ms = GetTickCount64() - started;
    return success;
}

static int close_first_issue206(SOCKET socket_handle, CLOSE_MODE mode, int *wsa_error)
{
    if (mode == CLOSE_ABORTIVE) {
        struct linger linger_option;
        linger_option.l_onoff = 1;
        linger_option.l_linger = 0;
        if (setsockopt(socket_handle, SOL_SOCKET, SO_LINGER,
            (const char *)&linger_option, sizeof(linger_option)) == SOCKET_ERROR) {
            *wsa_error = WSAGetLastError(); closesocket(socket_handle); return 0;
        }
    } else {
        char drain[32];
        int result;
        if (shutdown(socket_handle, SD_SEND) == SOCKET_ERROR) {
            *wsa_error = WSAGetLastError(); closesocket(socket_handle); return 0;
        }
        do { result = recv(socket_handle, drain, sizeof(drain), 0); }
        while (result > 0);
        if (result == SOCKET_ERROR) {
            *wsa_error = WSAGetLastError(); closesocket(socket_handle); return 0;
        }
    }
    if (closesocket(socket_handle) == SOCKET_ERROR) {
        *wsa_error = WSAGetLastError(); return 0;
    }
    *wsa_error = 0;
    return 1;
}

int main(int argc, char **argv)
{
    CONFIG config;
    WSADATA wsa_data;
    FILE *log_file = NULL;
    FLOW_RECORD first, second, recheck;
    SOCKET held = INVALID_SOCKET;
    int exit_code = 1;
    int ok = 0;
    if (!parse_arguments(argc, argv, &config)) { usage(argv[0]); return 2; }
    if (WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) return 3;
    {
        SOCKADDR_STORAGE check;
        int check_length;
        if (!make_endpoint(config.family, config.local_ip, config.local_port,
                &check, &check_length) ||
            !make_endpoint(config.family, config.remote_ip, 1, &check, &check_length) ||
            !make_endpoint(config.family, config.first_remote_ip, 1, &check, &check_length) ||
            !make_endpoint(config.family, config.second_remote_ip, 1, &check, &check_length)) {
            fprintf(stderr, "Address does not match --family.\n"); exit_code = 4; goto cleanup;
        }
    }
    log_file = fopen(config.jsonl_log, "ab");
    if (!log_file) { fprintf(stderr, "Cannot open JSONL log: %s\n", config.jsonl_log); exit_code = 5; goto cleanup; }

    if (config.mode == MODE_SINGLE) {
        unsigned short remote_port = config.protocol == PROTO_TCP ?
            config.tcp_remote_port : config.udp_remote_port;
        ok = perform_flow(&config, 1, "single", config.protocol,
            config.local_port, config.remote_ip, remote_port, 0,
            config.expected_action, config.expect, config.tcp_peer_policy, NULL, &first);
        if (!write_record(log_file, &first)) { exit_code = 6; goto cleanup; }
    } else if (config.mode == MODE_ISSUE209) {
        NET_PROTOCOL second_protocol = config.first_protocol == PROTO_UDP ? PROTO_TCP : PROTO_UDP;
        unsigned short first_remote_port = config.first_protocol == PROTO_TCP ?
            config.tcp_remote_port : config.udp_remote_port;
        unsigned short second_remote_port = second_protocol == PROTO_TCP ?
            config.tcp_remote_port : config.udp_remote_port;
        ok = perform_flow(&config, 1, "first_flow", config.first_protocol,
            config.local_port, config.remote_ip, first_remote_port, 0,
            config.first_expected_action, config.first_expect,
            config.first_tcp_peer_policy, &held, &first);
        first.close_mode = "held_active";
        if (!write_record(log_file, &first)) { exit_code = 6; goto cleanup; }
        if (ok) {
            ok = perform_flow(&config, 2, "second_flow", second_protocol,
                first.actual_local_port, config.remote_ip, second_remote_port,
                0, config.second_expected_action, config.second_expect,
                config.second_tcp_peer_policy, NULL, &second);
            if (!write_record(log_file, &second)) { exit_code = 6; goto cleanup; }
        }
        if (ok) {
            ok = perform_held_recheck(&config, held, config.first_protocol,
                first.actual_local_port, config.remote_ip, first_remote_port,
                config.first_expected_action, config.first_expect,
                config.first_tcp_peer_policy, &recheck);
            if (!write_record(log_file, &recheck)) { exit_code = 6; goto cleanup; }
        }
    } else {
        int close_error = 0;
        ok = perform_flow(&config, 1, "first_flow", PROTO_TCP,
            config.local_port, config.first_remote_ip, config.first_remote_port,
            0, config.first_expected_action, config.first_expect,
            config.first_tcp_peer_policy, &held, &first);
        first.close_mode = close_name(config.close_mode);
        if (ok) {
            ok = close_first_issue206(held, config.close_mode, &close_error);
            held = INVALID_SOCKET;
            if (!ok) {
                first.wsa_error = close_error;
                copy_text(first.actual_result, sizeof(first.actual_result), "fail:first_close");
            }
        }
        if (!write_record(log_file, &first)) { exit_code = 6; goto cleanup; }
        if (ok) {
            if (config.inter_flow_wait_ms > 0) Sleep(config.inter_flow_wait_ms);
            ok = perform_flow(&config, 2, "second_flow", PROTO_TCP,
                first.actual_local_port, config.second_remote_ip,
                config.second_remote_port, config.bind_retry_count,
                config.second_expected_action, config.second_expect,
                config.second_tcp_peer_policy, NULL, &second);
            second.close_mode = "normal";
            if (!write_record(log_file, &second)) { exit_code = 6; goto cleanup; }
        }
    }
    exit_code = ok ? 0 : 10;
    printf("%s %s test_id=%s run_id=%s\n", ok ? "PASS" : "FAIL",
        mode_name(config.mode), config.test_id, config.run_id);
cleanup:
    if (held != INVALID_SOCKET) closesocket(held);
    if (log_file) fclose(log_file);
    WSACleanup();
    return exit_code;
}
