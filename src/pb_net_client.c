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
#define MAX_PAYLOAD 1048576
#define MAX_UDP_PAYLOAD 65507
#define SHA256_HEX 65
#define MAX_PARALLEL 32

typedef enum { MODE_NONE, MODE_SINGLE, MODE_ISSUE209, MODE_ISSUE206 } TEST_MODE;
typedef enum { PROTO_NONE, PROTO_TCP, PROTO_UDP } NET_PROTOCOL;
typedef enum { UDP_CONNECTED, UDP_UNCONNECTED } UDP_MODE;
typedef enum { CLOSE_NONE, CLOSE_GRACEFUL, CLOSE_ABORTIVE, CLOSE_HALF } CLOSE_MODE;
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
    char remote_host[MAX_TEXT];
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
    char endpoint_behavior[MAX_TEXT];
    DWORD behavior_delay_ms;
    unsigned long payload_size;
    int payload_size_explicit;
    unsigned int stream_count;
    unsigned int benchmark_streams;
    unsigned int benchmark_stream_index;
    unsigned int benchmark_warmup_count;
    unsigned short benchmark_alternate_port;
    unsigned int benchmark_message_size;
    int tcp_rtt;
    unsigned int parallel_count;
    unsigned int process_index;
    unsigned int reconnect_count;
    DWORD stream_interval_ms;
    char benchmark_relay_ip[INET6_ADDRSTRLEN];
    unsigned short benchmark_relay_port;
    int benchmark_exact_source;
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
    unsigned long socket_id;
    char requested_remote_ip[INET6_ADDRSTRLEN];
    char requested_remote_host[MAX_TEXT];
    unsigned short requested_remote_port;
    char actual_remote_ip[INET6_ADDRSTRLEN];
    unsigned short actual_remote_port;
    int wsa_error;
    int bytes_sent;
    int bytes_received;
    int response_count;
    int response_order;
    char payload_sha256[SHA256_HEX];
    char response_sha256[SHA256_HEX];
    ULONGLONG timing_ms;
    const char *response_source_class;
    int accepted_for_performance;
    double udp_send_qpc_ms;
    double udp_receive_qpc_ms;
    double tcp_send_qpc_ms;
    double tcp_receive_qpc_ms;
    int tcp_nodelay;
    const char *expected_result;
    char actual_result[MAX_TEXT];
} FLOW_RECORD;

typedef struct PARALLEL_FLOW_CONTEXT {
    const CONFIG *config;
    int sequence;
    char phase[32];
    FLOW_RECORD record;
    int success;
    HANDLE thread;
} PARALLEL_FLOW_CONTEXT;

static volatile LONG socket_id_counter = 0;

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
    if (value == CLOSE_HALF) return "half-close";
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
        "--local-ip IP --local-port PORT --remote-ip IP [--remote-host NAME] "
        "--test-id ID --run-id ID --jsonl-log PATH [options]\n"
        "  single:   --protocol tcp|udp [--udp-mode connected|unconnected]\n"
        "  issue209: --first-protocol udp|tcp\n"
        "  issue206: --close-mode graceful|abortive [distinct remote options]\n"
        "Options: --tcp-remote-port 41002 --udp-remote-port 41001 "
        "--tcp-peer-policy exact|record-only --expected-action DIRECT|PROXY|BLOCK "
        "--expect echo|no-echo --timeout-ms 3000 --payload-size BYTES "
        "--stream-count 1..64 --stream-interval-ms MS "
        "--benchmark-relay-ip IP --benchmark-relay-port PORT "
        "--benchmark-source-policy exact --benchmark-streams 1..4 "
        "--benchmark-warmup-count 0..1000 --benchmark-alternate-port PORT "
        "--parallel-count 1..32 "
        "--process-index 1..32 "
        "--reconnect-count 1..32 "
        "--endpoint-behavior normal|delay|server-close|reset|silent-timeout|drop|duplicate|out-of-order|late-response "
        "--behavior-delay-ms MS "
        "--bind-retry-count 10 "
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
    config->stream_count = 1;
    config->benchmark_streams = 1;
    config->benchmark_stream_index = 1;
    config->parallel_count = 1;
    config->reconnect_count = 1;

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
            else if (_stricmp(value, "half-close") == 0) config->close_mode = CLOSE_HALF;
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
        } else if (strcmp(name, "--remote-host") == 0) {
            if (!copy_text(config->remote_host, sizeof(config->remote_host), value)) return 0;
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
        } else if (strcmp(name, "--payload-size") == 0) {
            if (!parse_ulong(value, 0, MAX_PAYLOAD, &number)) return 0;
            config->payload_size = number;
            config->payload_size_explicit = 1;
        } else if (strcmp(name, "--stream-count") == 0) {
            if (!parse_ulong(value, 1, 20000, &number)) return 0;
            config->stream_count = (unsigned int)number;
        } else if (strcmp(name, "--benchmark-streams") == 0) {
            if (!parse_ulong(value, 1, 4, &number)) return 0;
            config->benchmark_streams = (unsigned int)number;
        } else if (strcmp(name, "--benchmark-alternate-port") == 0) {
            if (!parse_ulong(value, 1, 65535, &number)) return 0;
            config->benchmark_alternate_port = (unsigned short)number;
        } else if (strcmp(name, "--benchmark-warmup-count") == 0) {
            if (!parse_ulong(value, 0, 1000, &number)) return 0;
            config->benchmark_warmup_count = (unsigned int)number;
        } else if (strcmp(name, "--tcp-rtt") == 0) {
            if (strcmp(value, "1") != 0) return 0;
            config->tcp_rtt = 1;
        } else if (strcmp(name, "--benchmark-message-size") == 0) {
            if (!parse_ulong(value, 256, 1200, &number)) return 0;
            config->benchmark_message_size = (unsigned int)number;
        } else if (strcmp(name, "--benchmark-relay-ip") == 0) {
            if (!copy_text(config->benchmark_relay_ip, sizeof(config->benchmark_relay_ip), value)) return 0;
        } else if (strcmp(name, "--benchmark-relay-port") == 0) {
            if (!parse_ulong(value, 1, 65535, &number)) return 0;
            config->benchmark_relay_port = (unsigned short)number;
        } else if (strcmp(name, "--benchmark-source-policy") == 0) {
            if (strcmp(value, "exact") != 0) return 0;
            config->benchmark_exact_source = 1;
        } else if (strcmp(name, "--parallel-count") == 0) {
            if (!parse_ulong(value, 1, MAX_PARALLEL, &number)) return 0;
            config->parallel_count = (unsigned int)number;
        } else if (strcmp(name, "--process-index") == 0) {
            if (!parse_ulong(value, 1, MAX_PARALLEL, &number)) return 0;
            config->process_index = (unsigned int)number;
        } else if (strcmp(name, "--reconnect-count") == 0) {
            if (!parse_ulong(value, 1, MAX_PARALLEL, &number)) return 0;
            config->reconnect_count = (unsigned int)number;
        } else if (strcmp(name, "--stream-interval-ms") == 0) {
            if (!parse_ulong(value, 0, 60000, &number)) return 0;
            config->stream_interval_ms = (DWORD)number;
        } else if (strcmp(name, "--endpoint-behavior") == 0) {
            if (_stricmp(value, "normal") != 0 && _stricmp(value, "delay") != 0 &&
                _stricmp(value, "server-close") != 0 && _stricmp(value, "reset") != 0 &&
                _stricmp(value, "silent-timeout") != 0 && _stricmp(value, "drop") != 0 &&
                _stricmp(value, "duplicate") != 0 && _stricmp(value, "out-of-order") != 0 &&
                _stricmp(value, "late-response") != 0) return 0;
            if (!copy_text(config->endpoint_behavior, sizeof(config->endpoint_behavior), value)) return 0;
        } else if (strcmp(name, "--behavior-delay-ms") == 0) {
            if (!parse_ulong(value, 0, 60000, &number)) return 0;
            config->behavior_delay_ms = (DWORD)number;
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
    if (config->mode == MODE_SINGLE && config->protocol == PROTO_UDP &&
        config->payload_size_explicit && config->payload_size > MAX_UDP_PAYLOAD) return 0;
    if (config->benchmark_alternate_port &&
        (config->benchmark_streams != 2 || config->benchmark_alternate_port == config->udp_remote_port)) return 0;
    if (config->benchmark_streams > 1 &&
        (!(config->benchmark_exact_source || config->benchmark_relay_port) ||
         config->local_port != 0 || config->benchmark_warmup_count >= config->stream_count)) return 0;
    if (config->stream_count > 1 &&
        (config->mode != MODE_SINGLE ||
         (!config->payload_size_explicit && !config->benchmark_relay_port && !config->benchmark_exact_source && !config->tcp_rtt))) return 0;
    if ((config->benchmark_relay_ip[0] != 0) != (config->benchmark_relay_port != 0)) return 0;
    if (config->benchmark_exact_source && config->benchmark_relay_port) return 0;
    if ((config->stream_count > 64 || config->benchmark_message_size) &&
        !config->benchmark_exact_source && !config->benchmark_relay_port && !config->tcp_rtt) return 0;
    if (config->tcp_rtt &&
        (config->mode != MODE_SINGLE || config->protocol != PROTO_TCP ||
         config->family != AF_INET || config->stream_count < 2 ||
         config->benchmark_streams != 1 || config->parallel_count != 1 ||
         config->reconnect_count != 1 || config->process_index ||
         config->payload_size_explicit || !config->benchmark_message_size ||
         config->endpoint_behavior[0] || config->expect != EXPECT_ECHO ||
         config->expected_action == ACTION_BLOCK || config->benchmark_relay_port ||
         config->benchmark_exact_source || config->local_port != 0 || config->remote_host[0] ||
         strcmp(config->remote_ip, "127.0.0.1") != 0)) return 0;
    if ((config->benchmark_relay_port || config->benchmark_exact_source) &&
        (config->mode != MODE_SINGLE || config->protocol != PROTO_UDP ||
         config->family != AF_INET || config->udp_mode != UDP_CONNECTED ||
         config->stream_count < 2 || config->payload_size_explicit ||
         config->parallel_count != 1 || config->reconnect_count != 1 ||
         config->process_index || config->endpoint_behavior[0] ||
         config->expected_action != (config->benchmark_exact_source ? ACTION_DIRECT : ACTION_PROXY) || config->expect != EXPECT_ECHO ||
         (config->benchmark_relay_port && strcmp(config->benchmark_relay_ip, "127.0.0.1") != 0) ||
         strcmp(config->remote_ip, "127.0.0.1") != 0 ||
         config->remote_host[0] || config->second_remote_port != config->udp_remote_port ||
         (config->second_remote_ip[0] && strcmp(config->second_remote_ip, config->remote_ip) != 0))) return 0;
    if (config->parallel_count > 1 &&
        (config->mode != MODE_SINGLE || config->stream_count > 1 ||
         config->local_port != 0)) return 0;
    if (config->process_index > 0 &&
        (config->mode != MODE_SINGLE || config->stream_count > 1 ||
         config->parallel_count > 1 || config->local_port != 0)) return 0;
    if (config->reconnect_count > 1 &&
        (config->mode != MODE_SINGLE || config->protocol != PROTO_UDP ||
         config->stream_count > 1 || config->parallel_count > 1 ||
         config->process_index > 0 || config->local_port != 0)) return 0;
    if (config->stream_interval_ms > 0 && config->stream_count < 2) return 0;
    if (config->endpoint_behavior[0] &&
        (config->mode != MODE_SINGLE || !config->payload_size_explicit)) return 0;
    if (_stricmp(config->endpoint_behavior, "out-of-order") == 0 &&
        (config->protocol != PROTO_UDP || config->udp_mode != UDP_UNCONNECTED ||
         config->stream_count != 2 || config->expect != EXPECT_ECHO)) return 0;
    if (_stricmp(config->endpoint_behavior, "late-response") == 0 &&
        (config->protocol != PROTO_UDP || config->udp_mode != UDP_UNCONNECTED ||
         config->stream_count != 2 || config->expect != EXPECT_ECHO ||
         config->behavior_delay_ms < 100)) return 0;
    if (config->mode == MODE_SINGLE && config->protocol == PROTO_UDP &&
        config->endpoint_behavior[0] && config->payload_size > MAX_UDP_PAYLOAD - 16) return 0;
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

static int resolve_remote_endpoint(int family, NET_PROTOCOL protocol,
    const char *host, const char *expected_ip, unsigned short port,
    SOCKADDR_STORAGE *storage, int *length)
{
    ADDRINFOA hints, *results = NULL, *entry;
    SOCKADDR_STORAGE expected;
    int expected_length;
    char port_text[6];
    if (!host || !host[0]) return make_endpoint(family, expected_ip, port, storage, length);
    if (!make_endpoint(family, expected_ip, port, &expected, &expected_length)) return 0;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = family;
    hints.ai_socktype = protocol == PROTO_TCP ? SOCK_STREAM : SOCK_DGRAM;
    hints.ai_protocol = protocol == PROTO_TCP ? IPPROTO_TCP : IPPROTO_UDP;
    snprintf(port_text, sizeof(port_text), "%u", (unsigned int)port);
    {
        int resolver_error = getaddrinfo(host, port_text, &hints, &results);
        if (resolver_error != 0) { WSASetLastError(resolver_error); return 0; }
    }
    for (entry = results; entry; entry = entry->ai_next) {
        SOCKADDR_STORAGE candidate;
        if ((size_t)entry->ai_addrlen > sizeof(candidate)) continue;
        memset(&candidate, 0, sizeof(candidate));
        memcpy(&candidate, entry->ai_addr, (size_t)entry->ai_addrlen);
        if (endpoints_equal(&expected, &candidate)) {
            *storage = candidate;
            *length = (int)entry->ai_addrlen;
            freeaddrinfo(results);
            return 1;
        }
    }
    freeaddrinfo(results);
    WSASetLastError(WSAHOST_NOT_FOUND);
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
    fprintf(file, ",\"process_id\":%lu", (unsigned long)GetCurrentProcessId());
    fprintf(file, ",\"sequence\":%d,", record->sequence);
    fprintf(file, "\"benchmark_stream_index\":%u,", record->config->benchmark_stream_index);
    json_pair(file, "phase", record->phase); fputc(',', file);
    json_pair(file, "expected_action", expected_action_name(record->expected_action)); fputc(',', file);
    json_pair(file, "expect", expect_name(record->expect)); fputc(',', file);
    json_pair(file, "family", record->config->family == AF_INET ? "IPv4" : "IPv6"); fputc(',', file);
    json_pair(file, "protocol", protocol_name(record->protocol)); fputc(',', file);
    json_pair(file, "tcp_peer_policy", record->protocol == PROTO_TCP ?
        tcp_peer_policy_name(record->tcp_peer_policy) : "n/a"); fputc(',', file);
    json_pair(file, "udp_mode", record->udp_mode); fputc(',', file);
    json_pair(file, "close_mode", record->close_mode); fputc(',', file);
    json_pair(file, "endpoint_behavior", record->config->endpoint_behavior); fputc(',', file);
    fprintf(file, "\"behavior_delay_ms\":%lu,", (unsigned long)record->config->behavior_delay_ms);
    json_pair(file, "requested_local_ip", record->requested_local_ip);
    fprintf(file, ",\"requested_local_port\":%u,", (unsigned int)record->requested_local_port);
    json_pair(file, "actual_local_ip", record->actual_local_ip);
    fprintf(file, ",\"actual_local_port\":%u,", (unsigned int)record->actual_local_port);
    fprintf(file, "\"socket_id\":%lu,", record->socket_id);
    json_pair(file, "requested_remote_ip", record->requested_remote_ip);
    fputc(',', file);
    json_pair(file, "requested_remote_host", record->requested_remote_host);
    fprintf(file, ",\"requested_remote_port\":%u,", (unsigned int)record->requested_remote_port);
    json_pair(file, "actual_remote_ip", record->actual_remote_ip);
    fprintf(file, ",\"actual_remote_port\":%u,\"wsa_error\":%d,",
        (unsigned int)record->actual_remote_port, record->wsa_error);
    fprintf(file, "\"bytes_sent\":%d,\"bytes_received\":%d,\"response_count\":%d,",
        record->bytes_sent, record->bytes_received, record->response_count);
    fprintf(file, "\"response_order\":%d,", record->response_order);
    json_pair(file, "payload_sha256", record->payload_sha256); fputc(',', file);
    json_pair(file, "response_sha256", record->response_sha256);
    fputc(',', file);
    json_pair(file, "response_source_class", record->response_source_class);
    fprintf(file, ",\"accepted_for_performance\":%s,\"udp_send_qpc_ms\":%.6f,\"udp_receive_qpc_ms\":%.6f",
        record->accepted_for_performance ? "true" : "false",
        record->udp_send_qpc_ms, record->udp_receive_qpc_ms);
    fprintf(file, ",\"timing_ms\":%llu,", (unsigned long long)record->timing_ms);
    fprintf(file, "\"tcp_send_qpc_ms\":%.6f,\"tcp_receive_qpc_ms\":%.6f,\"tcp_nodelay\":%s,",
        record->tcp_send_qpc_ms, record->tcp_receive_qpc_ms,
        record->tcp_nodelay ? "true" : "false");
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
        if ((config->mode == MODE_ISSUE206 ||
            _stricmp(config->endpoint_behavior, "late-response") == 0) &&
            local_port != 0) {
            BOOL reuse_address = TRUE;
            if (setsockopt(socket_handle, SOL_SOCKET, SO_REUSEADDR,
                (const char *)&reuse_address, sizeof(reuse_address)) == SOCKET_ERROR) {
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
            record->socket_id = (unsigned long)InterlockedIncrement(&socket_id_counter);
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

static unsigned long endpoint_behavior_code(const char *behavior)
{
    if (!behavior || !behavior[0] || _stricmp(behavior, "normal") == 0) return 0;
    if (_stricmp(behavior, "delay") == 0) return 1;
    if (_stricmp(behavior, "server-close") == 0) return 2;
    if (_stricmp(behavior, "reset") == 0) return 3;
    if (_stricmp(behavior, "silent-timeout") == 0) return 4;
    if (_stricmp(behavior, "drop") == 0) return 5;
    if (_stricmp(behavior, "duplicate") == 0) return 6;
    if (_stricmp(behavior, "out-of-order") == 0) return 7;
    if (_stricmp(behavior, "late-response") == 0) return 8;
    return 0xffffffffUL;
}

static int send_tcp_frame_header(SOCKET socket_handle, const CONFIG *config,
    int payload_length, int *wsa_error)
{
    unsigned long behavior_code = endpoint_behavior_code(config->endpoint_behavior);
    if (behavior_code == 0xffffffffUL) { *wsa_error = WSAEINVAL; return SOCKET_ERROR; }
    if (behavior_code == 0) {
        unsigned long framed_length = htonl((unsigned long)payload_length);
        return send_all(socket_handle, (const char *)&framed_length,
            (int)sizeof(framed_length), wsa_error);
    }
    {
        unsigned long header[4];
        header[0] = htonl(0x50424354UL);
        header[1] = htonl(behavior_code);
        header[2] = htonl((unsigned long)config->behavior_delay_ms);
        header[3] = htonl((unsigned long)payload_length);
        return send_all(socket_handle, (const char *)header, (int)sizeof(header), wsa_error);
    }
}

static int build_udp_wire_payload(const CONFIG *config,
    const unsigned char *payload, int payload_length,
    unsigned char *wire_buffer,
    const unsigned char **wire_payload, int *wire_length)
{
    unsigned long behavior_code = endpoint_behavior_code(config->endpoint_behavior);
    if (behavior_code == 0xffffffffUL) return 0;
    if (behavior_code == 0) {
        *wire_payload = payload;
        *wire_length = payload_length;
        return 1;
    }
    if (payload_length > MAX_UDP_PAYLOAD - 16) return 0;
    {
        unsigned long header[4];
        header[0] = htonl(0x50425544UL);
        header[1] = htonl(behavior_code);
        header[2] = htonl((unsigned long)config->behavior_delay_ms);
        header[3] = htonl((unsigned long)payload_length);
        memcpy(wire_buffer, header, sizeof(header));
        memcpy(wire_buffer + sizeof(header), payload, (size_t)payload_length);
        *wire_payload = wire_buffer;
        *wire_length = payload_length + (int)sizeof(header);
        return 1;
    }
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
    record->response_source_class = "NOT_OBSERVED";
    copy_text(record->requested_local_ip, sizeof(record->requested_local_ip), config->local_ip);
    record->requested_local_port = local_port;
    copy_text(record->requested_remote_ip, sizeof(record->requested_remote_ip), remote_ip);
    if (config->remote_host[0]) {
        copy_text(record->requested_remote_host,
            sizeof(record->requested_remote_host), config->remote_host);
    }
    record->requested_remote_port = remote_port;
    record->expected_result = expect_name(expect);
    copy_text(record->actual_result, sizeof(record->actual_result), "fail:not_started");
}

static double qpc_ms(void)
{
    LARGE_INTEGER ticks, frequency;
    if (!QueryPerformanceCounter(&ticks) || !QueryPerformanceFrequency(&frequency)) return 0.0;
    return (double)ticks.QuadPart * 1000.0 / (double)frequency.QuadPart;
}

/* A controller must independently verify ownership of the supplied relay.
 * This only permits collection to continue; the strict source error remains. */
static int check_udp_source(FLOW_RECORD *record, const SOCKADDR_STORAGE *remote,
    const SOCKADDR_STORAGE *source, const unsigned char *response)
{
    int parsed = endpoint_parts(source, record->actual_remote_ip,
        sizeof(record->actual_remote_ip), &record->actual_remote_port);
    if (parsed && endpoints_equal(remote, source)) {
        record->response_source_class = "ORIGINAL_ENDPOINT";
        return 1;
    }
    if (parsed && record->config->benchmark_relay_port &&
        record->actual_remote_port == record->config->benchmark_relay_port &&
        strcmp(record->actual_remote_ip, record->config->benchmark_relay_ip) == 0) {
        record->response_source_class = "OWNED_RELAY";
        return 1;
    }
    record->response_source_class = "UNEXPECTED";
    if (!sha256_bytes(response, (ULONG)record->bytes_received, record->response_sha256))
        record->response_sha256[0] = '\0';
    record->wsa_error = WSAEINVAL;
    copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_response_source");
    return 0;
}

static int start_tcp_rtt(SOCKET socket_handle, FLOW_RECORD *record)
{
    int value = 1;
    int length = sizeof(value);
    if (!record->config->tcp_rtt) return 1;
    if (setsockopt(socket_handle, IPPROTO_TCP, TCP_NODELAY,
            (const char *)&value, sizeof(value)) == SOCKET_ERROR ||
        getsockopt(socket_handle, IPPROTO_TCP, TCP_NODELAY,
            (char *)&value, &length) == SOCKET_ERROR || value != 1) {
        record->wsa_error = WSAGetLastError();
        if (!record->wsa_error) record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:tcp_nodelay");
        return 0;
    }
    record->tcp_nodelay = 1;
    record->tcp_send_qpc_ms = qpc_ms();
    return record->tcp_send_qpc_ms > 0;
}

static void mark_valid_response(FLOW_RECORD *record)
{
    record->accepted_for_performance = record->config->benchmark_relay_port != 0 || record->config->benchmark_exact_source;
    record->wsa_error = 0;
    if (strcmp(record->response_source_class, "OWNED_RELAY") == 0) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_response_source");
    } else copy_text(record->actual_result, sizeof(record->actual_result), "pass");
}

static int build_payload(const CONFIG *config, int sequence, const char *phase,
    NET_PROTOCOL protocol, unsigned char *payload, int *payload_length)
{
    if (config->payload_size_explicit) {
        unsigned long payload_index;
        *payload_length = (int)config->payload_size;
        for (payload_index = 0; payload_index < config->payload_size; payload_index++) {
            payload[payload_index] = (unsigned char)((payload_index * 131UL +
                (unsigned long)sequence * 17UL +
                (unsigned char)config->test_id[0]) & 0xffUL);
        }
        return 1;
    }
    *payload_length = snprintf((char *)payload, MAX_PAYLOAD,
        "PB_NET|test_id=%s|run_id=%s|sequence=%d|phase=%s|protocol=%s\n",
        config->test_id, config->run_id, sequence, phase, protocol_name(protocol));
    if (config->benchmark_message_size) {
        if (*payload_length <= 0 || (unsigned int)*payload_length > config->benchmark_message_size) return 0;
        memset(payload + *payload_length, 'X', config->benchmark_message_size - (unsigned int)*payload_length);
        *payload_length = (int)config->benchmark_message_size;
    }
    return *payload_length > 0 && *payload_length < MAX_PAYLOAD;
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
    unsigned char *payload = NULL;
    unsigned char *response = NULL;
    unsigned char *udp_wire = NULL;
    int payload_length, result;
    ULONGLONG started = GetTickCount64();
    int success = 0;

    initialize_record(record, config, sequence, phase, protocol, local_port,
        remote_ip, remote_port, expected_action, expect, tcp_peer_policy);
    payload = (unsigned char *)malloc(MAX_PAYLOAD);
    response = (unsigned char *)malloc(MAX_PAYLOAD);
    if (protocol == PROTO_UDP) {
        udp_wire = (unsigned char *)malloc(MAX_UDP_PAYLOAD + 16);
    }
    if (!payload || !response || (protocol == PROTO_UDP && !udp_wire)) {
        record->wsa_error = WSA_NOT_ENOUGH_MEMORY;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:memory_allocation");
        goto done;
    }
    if (!build_payload(config, sequence, phase, protocol, payload, &payload_length)) {
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
    if (!resolve_remote_endpoint(config->family, protocol,
        config->mode == MODE_SINGLE ? config->remote_host : "", remote_ip,
        record->requested_remote_port, &remote, &remote_length)) {
        record->wsa_error = WSAGetLastError();
        if (!record->wsa_error) record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:remote_resolution");
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
        if (!start_tcp_rtt(socket_handle, record)) goto done;
        if (config->payload_size_explicit || config->tcp_rtt) {
            result = send_tcp_frame_header(socket_handle, config, payload_length,
                &record->wsa_error);
            if (result == SOCKET_ERROR) {
                if (expect == EXPECT_NO_ECHO) {
                    copy_text(record->actual_result, sizeof(record->actual_result), "pass:no_echo_send_failure");
                    success = 1;
                } else {
                    copy_text(record->actual_result, sizeof(record->actual_result), "fail:send_frame");
                }
                goto done;
            }
        }
        result = send_all(socket_handle, (const char *)payload, payload_length, &record->wsa_error);
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
        result = recv_exact(socket_handle, (char *)response, payload_length, &record->wsa_error);
        if (config->tcp_rtt) record->tcp_receive_qpc_ms = qpc_ms();
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
        record->response_count = 1;
    } else {
        const unsigned char *wire_payload;
        int wire_length;
        if (!build_udp_wire_payload(config, payload, payload_length, udp_wire,
            &wire_payload, &wire_length)) {
            record->wsa_error = WSAEMSGSIZE;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_control_payload");
            goto done;
        }
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
        record->udp_send_qpc_ms = qpc_ms();
        result = config->udp_mode == UDP_CONNECTED ?
            send(socket_handle, (const char *)wire_payload, wire_length, 0) :
            sendto(socket_handle, (const char *)wire_payload, wire_length, 0,
                (const struct sockaddr *)&remote, remote_length);
        if (result == SOCKET_ERROR || result != wire_length) {
            record->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEMSGSIZE;
            if (expect == EXPECT_NO_ECHO) {
                copy_text(record->actual_result, sizeof(record->actual_result), "pass:no_echo_send_failure");
                success = 1;
            } else {
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:send");
            }
            goto done;
        }
        record->bytes_sent = payload_length;
        response_source_length = sizeof(response_source);
        memset(&response_source, 0, sizeof(response_source));
        result = recvfrom(socket_handle, (char *)response, MAX_PAYLOAD, 0,
            (struct sockaddr *)&response_source, &response_source_length);
        record->udp_receive_qpc_ms = qpc_ms();
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
        record->response_count = 1;
        if (!check_udp_source(record, &remote, &response_source, response)) goto done;
        if (_stricmp(config->endpoint_behavior, "duplicate") == 0) {
            int duplicate_result;
            response_source_length = sizeof(response_source);
            memset(&response_source, 0, sizeof(response_source));
            duplicate_result = recvfrom(socket_handle, (char *)response,
                MAX_PAYLOAD, 0, (struct sockaddr *)&response_source,
                &response_source_length);
            if (duplicate_result != payload_length ||
                memcmp(response, payload, (size_t)payload_length) != 0 ||
                !endpoints_equal(&remote, &response_source)) {
                record->wsa_error = duplicate_result == SOCKET_ERROR ? WSAGetLastError() : WSAEINVAL;
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_duplicate_response");
                goto done;
            }
            record->response_count = 2;
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
    if (protocol == PROTO_TCP &&
        _stricmp(config->endpoint_behavior, "server-close") == 0) {
        char close_probe;
        result = recv(socket_handle, &close_probe, 1, 0);
        if (result != 0) {
            record->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEINVAL;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:server_close_not_observed");
            goto done;
        }
    }
    if (protocol == PROTO_TCP && config->mode == MODE_SINGLE &&
        config->stream_count == 1 && config->close_mode != CLOSE_NONE) {
        record->close_mode = close_name(config->close_mode);
        if (config->close_mode == CLOSE_ABORTIVE) {
            struct linger linger_option;
            linger_option.l_onoff = 1;
            linger_option.l_linger = 0;
            if (setsockopt(socket_handle, SOL_SOCKET, SO_LINGER,
                (const char *)&linger_option, sizeof(linger_option)) == SOCKET_ERROR) {
                record->wsa_error = WSAGetLastError();
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:abortive_close_option");
                goto done;
            }
        } else if (config->close_mode == CLOSE_HALF) {
            char drain[32];
            if (shutdown(socket_handle, SD_SEND) == SOCKET_ERROR) {
                record->wsa_error = WSAGetLastError();
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:half_close_shutdown");
                goto done;
            }
            do { result = recv(socket_handle, drain, sizeof(drain), 0); }
            while (result > 0);
            if (result == SOCKET_ERROR) {
                record->wsa_error = WSAGetLastError();
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:half_close_drain");
                goto done;
            }
        }
    }
    mark_valid_response(record);
    success = 1;
done:
    record->timing_ms = GetTickCount64() - started;
    if (kept_socket && success) {
        *kept_socket = socket_handle;
        socket_handle = INVALID_SOCKET;
    }
    if (socket_handle != INVALID_SOCKET) closesocket(socket_handle);
    free(udp_wire);
    free(response);
    free(payload);
    return success;
}

static int receive_reordered_udp_response(SOCKET socket_handle,
    const SOCKADDR_STORAGE *remote, const unsigned char *expected_payload,
    int payload_length, unsigned char *response, int response_order,
    FLOW_RECORD *record)
{
    SOCKADDR_STORAGE response_source;
    int response_source_length = sizeof(response_source);
    int result;
    memset(&response_source, 0, sizeof(response_source));
    result = recvfrom(socket_handle, (char *)response, MAX_PAYLOAD, 0,
        (struct sockaddr *)&response_source, &response_source_length);
    if (result == SOCKET_ERROR) {
        record->wsa_error = WSAGetLastError();
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:recvfrom");
        return 0;
    }
    record->bytes_received = result;
    record->response_count = 1;
    record->response_order = response_order;
    if (!endpoint_parts(&response_source, record->actual_remote_ip,
            sizeof(record->actual_remote_ip), &record->actual_remote_port) ||
        !endpoints_equal(remote, &response_source)) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_response_source");
        return 0;
    }
    if (result != payload_length ||
        memcmp(response, expected_payload, (size_t)payload_length) != 0) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_response_order");
        return 0;
    }
    if (!sha256_bytes(response, (ULONG)result, record->response_sha256)) {
        record->wsa_error = WSAEINVAL;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:BCrypt_response_SHA256");
        return 0;
    }
    record->wsa_error = 0;
    copy_text(record->actual_result, sizeof(record->actual_result), "pass");
    return 1;
}

static int perform_udp_out_of_order(const CONFIG *config,
    unsigned short remote_port, FLOW_RECORD *first, FLOW_RECORD *second)
{
    SOCKET socket_handle = INVALID_SOCKET;
    SOCKADDR_STORAGE remote;
    int remote_length;
    int timeout_value = (int)config->timeout_ms;
    unsigned char *first_payload = NULL;
    unsigned char *second_payload = NULL;
    unsigned char *first_wire = NULL;
    unsigned char *second_wire = NULL;
    unsigned char *response = NULL;
    const unsigned char *wire_payload;
    int first_length = 0, second_length = 0, wire_length = 0, result;
    ULONGLONG started = GetTickCount64();
    int success = 0;

    initialize_record(first, config, 1, "stream_1", PROTO_UDP, 0,
        config->remote_ip, remote_port, config->expected_action,
        config->expect, config->tcp_peer_policy);
    initialize_record(second, config, 2, "stream_2", PROTO_UDP, 0,
        config->remote_ip, remote_port, config->expected_action,
        config->expect, config->tcp_peer_policy);
    first_payload = (unsigned char *)malloc(MAX_PAYLOAD);
    second_payload = (unsigned char *)malloc(MAX_PAYLOAD);
    first_wire = (unsigned char *)malloc(MAX_UDP_PAYLOAD + 16);
    second_wire = (unsigned char *)malloc(MAX_UDP_PAYLOAD + 16);
    response = (unsigned char *)malloc(MAX_PAYLOAD);
    if (!first_payload || !second_payload || !first_wire || !second_wire || !response) {
        first->wsa_error = second->wsa_error = WSA_NOT_ENOUGH_MEMORY;
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:memory_allocation");
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:memory_allocation");
        goto done;
    }
    if (!build_payload(config, 1, "stream_1", PROTO_UDP,
            first_payload, &first_length) ||
        !build_payload(config, 2, "stream_2", PROTO_UDP,
            second_payload, &second_length) ||
        !sha256_bytes(first_payload, (ULONG)first_length, first->payload_sha256) ||
        !sha256_bytes(second_payload, (ULONG)second_length, second->payload_sha256)) {
        first->wsa_error = second->wsa_error = WSAEINVAL;
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:payload_identity");
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:payload_identity");
        goto done;
    }
    if (!resolve_remote_endpoint(config->family, PROTO_UDP,
        config->remote_host, config->remote_ip, remote_port,
        &remote, &remote_length)) {
        first->wsa_error = second->wsa_error = WSAGetLastError();
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:remote_resolution");
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:remote_resolution");
        goto done;
    }
    socket_handle = create_bound_socket(config, PROTO_UDP, 0, 0, first);
    if (socket_handle == INVALID_SOCKET) {
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:bind");
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:bind");
        goto done;
    }
    copy_text(second->actual_local_ip, sizeof(second->actual_local_ip),
        first->actual_local_ip);
    second->actual_local_port = first->actual_local_port;
    second->socket_id = first->socket_id;
    if (setsockopt(socket_handle, SOL_SOCKET, SO_RCVTIMEO,
            (const char *)&timeout_value, sizeof(timeout_value)) == SOCKET_ERROR ||
        setsockopt(socket_handle, SOL_SOCKET, SO_SNDTIMEO,
            (const char *)&timeout_value, sizeof(timeout_value)) == SOCKET_ERROR) {
        first->wsa_error = second->wsa_error = WSAGetLastError();
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:timeout_option");
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:timeout_option");
        goto done;
    }
    if (!build_udp_wire_payload(config, first_payload, first_length,
        first_wire, &wire_payload, &wire_length)) goto control_failure;
    result = sendto(socket_handle, (const char *)wire_payload, wire_length, 0,
        (const struct sockaddr *)&remote, remote_length);
    if (result != wire_length) {
        first->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEMSGSIZE;
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:send");
        goto done;
    }
    first->bytes_sent = first_length;
    if (!build_udp_wire_payload(config, second_payload, second_length,
        second_wire, &wire_payload, &wire_length)) goto control_failure;
    result = sendto(socket_handle, (const char *)wire_payload, wire_length, 0,
        (const struct sockaddr *)&remote, remote_length);
    if (result != wire_length) {
        second->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEMSGSIZE;
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:send");
        goto done;
    }
    second->bytes_sent = second_length;
    if (!receive_reordered_udp_response(socket_handle, &remote,
        second_payload, second_length, response, 1, second)) goto done;
    if (!receive_reordered_udp_response(socket_handle, &remote,
        first_payload, first_length, response, 2, first)) goto done;
    success = 1;
    goto done;
control_failure:
    first->wsa_error = second->wsa_error = WSAEMSGSIZE;
    copy_text(first->actual_result, sizeof(first->actual_result), "fail:udp_control_payload");
    copy_text(second->actual_result, sizeof(second->actual_result), "fail:udp_control_payload");
done:
    first->timing_ms = second->timing_ms = GetTickCount64() - started;
    if (socket_handle != INVALID_SOCKET) closesocket(socket_handle);
    free(response); free(second_wire); free(first_wire);
    free(second_payload); free(first_payload);
    return success;
}

static int perform_udp_late_response_reuse(const CONFIG *config,
    unsigned short remote_port, FLOW_RECORD *first, FLOW_RECORD *second)
{
    CONFIG normal_config = *config;
    SOCKET socket_handle = INVALID_SOCKET;
    SOCKADDR_STORAGE remote, response_source;
    int remote_length, response_source_length;
    int timeout_value = (int)config->timeout_ms;
    int late_probe_timeout = (int)config->behavior_delay_ms + 250;
    unsigned char *first_payload = NULL;
    unsigned char *second_payload = NULL;
    unsigned char *wire_buffer = NULL;
    unsigned char *response = NULL;
    const unsigned char *wire_payload;
    int first_length = 0, second_length = 0, wire_length = 0, result;
    ULONGLONG started = GetTickCount64();
    int success = 0;

    copy_text(normal_config.endpoint_behavior,
        sizeof(normal_config.endpoint_behavior), "normal");
    initialize_record(first, config, 1, "stream_1", PROTO_UDP, 0,
        config->remote_ip, remote_port, config->expected_action,
        EXPECT_NO_ECHO, config->tcp_peer_policy);
    initialize_record(second, config, 2, "stream_2", PROTO_UDP, 0,
        config->remote_ip, remote_port, config->expected_action,
        EXPECT_ECHO, config->tcp_peer_policy);
    first->close_mode = "closed_before_response";
    second->close_mode = "normal";
    first_payload = (unsigned char *)malloc(MAX_PAYLOAD);
    second_payload = (unsigned char *)malloc(MAX_PAYLOAD);
    wire_buffer = (unsigned char *)malloc(MAX_UDP_PAYLOAD + 16);
    response = (unsigned char *)malloc(MAX_PAYLOAD);
    if (!first_payload || !second_payload || !wire_buffer || !response) {
        first->wsa_error = second->wsa_error = WSA_NOT_ENOUGH_MEMORY;
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:memory_allocation");
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:memory_allocation");
        goto done;
    }
    if (!build_payload(config, 1, "stream_1", PROTO_UDP,
            first_payload, &first_length) ||
        !build_payload(config, 2, "stream_2", PROTO_UDP,
            second_payload, &second_length) ||
        !sha256_bytes(first_payload, (ULONG)first_length, first->payload_sha256) ||
        !sha256_bytes(second_payload, (ULONG)second_length, second->payload_sha256)) {
        first->wsa_error = second->wsa_error = WSAEINVAL;
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:payload_identity");
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:payload_identity");
        goto done;
    }
    if (!resolve_remote_endpoint(config->family, PROTO_UDP,
        config->remote_host, config->remote_ip, remote_port,
        &remote, &remote_length)) {
        first->wsa_error = second->wsa_error = WSAGetLastError();
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:remote_resolution");
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:remote_resolution");
        goto done;
    }
    socket_handle = create_bound_socket(config, PROTO_UDP, 0, 0, first);
    if (socket_handle == INVALID_SOCKET) {
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:first_bind");
        goto done;
    }
    if (!build_udp_wire_payload(config, first_payload, first_length,
        wire_buffer, &wire_payload, &wire_length)) {
        first->wsa_error = WSAEMSGSIZE;
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:udp_control_payload");
        goto done;
    }
    result = sendto(socket_handle, (const char *)wire_payload, wire_length, 0,
        (const struct sockaddr *)&remote, remote_length);
    if (result != wire_length) {
        first->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEMSGSIZE;
        copy_text(first->actual_result, sizeof(first->actual_result), "fail:first_send");
        goto done;
    }
    first->bytes_sent = first_length;
    first->wsa_error = 0;
    copy_text(first->actual_result, sizeof(first->actual_result),
        "pass:no_echo_socket_closed");
    first->timing_ms = GetTickCount64() - started;
    closesocket(socket_handle);
    socket_handle = INVALID_SOCKET;
    Sleep(25);

    second->requested_local_port = first->actual_local_port;
    socket_handle = create_bound_socket(config, PROTO_UDP,
        first->actual_local_port, config->bind_retry_count, second);
    if (socket_handle == INVALID_SOCKET) {
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:second_bind");
        goto done;
    }
    if (setsockopt(socket_handle, SOL_SOCKET, SO_RCVTIMEO,
            (const char *)&timeout_value, sizeof(timeout_value)) == SOCKET_ERROR ||
        setsockopt(socket_handle, SOL_SOCKET, SO_SNDTIMEO,
            (const char *)&timeout_value, sizeof(timeout_value)) == SOCKET_ERROR) {
        second->wsa_error = WSAGetLastError();
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:timeout_option");
        goto done;
    }
    if (!build_udp_wire_payload(&normal_config, second_payload, second_length,
        wire_buffer, &wire_payload, &wire_length)) {
        second->wsa_error = WSAEMSGSIZE;
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:udp_control_payload");
        goto done;
    }
    result = sendto(socket_handle, (const char *)wire_payload, wire_length, 0,
        (const struct sockaddr *)&remote, remote_length);
    if (result != wire_length) {
        second->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEMSGSIZE;
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:second_send");
        goto done;
    }
    second->bytes_sent = second_length;
    if (!receive_reordered_udp_response(socket_handle, &remote,
        second_payload, second_length, response, 1, second)) goto done;
    if (setsockopt(socket_handle, SOL_SOCKET, SO_RCVTIMEO,
        (const char *)&late_probe_timeout, sizeof(late_probe_timeout)) == SOCKET_ERROR) {
        second->wsa_error = WSAGetLastError();
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:late_probe_timeout_option");
        goto done;
    }
    response_source_length = sizeof(response_source);
    memset(&response_source, 0, sizeof(response_source));
    result = recvfrom(socket_handle, (char *)response, MAX_PAYLOAD, 0,
        (struct sockaddr *)&response_source, &response_source_length);
    if (result != SOCKET_ERROR) {
        second->wsa_error = WSAEINVAL;
        copy_text(second->actual_result, sizeof(second->actual_result),
            result == first_length &&
            memcmp(response, first_payload, (size_t)first_length) == 0 ?
            "fail:udp_late_response_delivered" : "fail:udp_unexpected_extra_response");
        goto done;
    }
    if (WSAGetLastError() != WSAETIMEDOUT) {
        second->wsa_error = WSAGetLastError();
        copy_text(second->actual_result, sizeof(second->actual_result), "fail:late_probe_recvfrom");
        goto done;
    }
    second->wsa_error = 0;
    success = 1;
done:
    if (first->timing_ms == 0) first->timing_ms = GetTickCount64() - started;
    second->timing_ms = GetTickCount64() - started;
    if (socket_handle != INVALID_SOCKET) closesocket(socket_handle);
    free(response); free(wire_buffer); free(second_payload); free(first_payload);
    return success;
}

static DWORD WINAPI parallel_flow_thread(LPVOID parameter)
{
    PARALLEL_FLOW_CONTEXT *context = (PARALLEL_FLOW_CONTEXT *)parameter;
    const CONFIG *config = context->config;
    unsigned short remote_port = config->protocol == PROTO_TCP ?
        config->tcp_remote_port : config->udp_remote_port;
    context->success = perform_flow(config, context->sequence, context->phase,
        config->protocol, 0, config->remote_ip, remote_port, 0,
        config->expected_action, config->expect, config->tcp_peer_policy,
        NULL, &context->record);
    return 0;
}

static int perform_existing_socket_flow(const CONFIG *config, SOCKET socket_handle,
    int sequence, const char *phase, NET_PROTOCOL protocol,
    unsigned long socket_id,
    unsigned short local_port, const char *remote_ip,
    unsigned short remote_port, EXPECTED_ACTION expected_action,
    EXPECT_OUTCOME expect, TCP_PEER_POLICY tcp_peer_policy, FLOW_RECORD *record)
{
    SOCKADDR_STORAGE remote, actual_remote, actual_local, response_source;
    int remote_length, actual_remote_length, actual_local_length;
    int response_source_length;
    unsigned char *payload = NULL;
    unsigned char *response = NULL;
    unsigned char *udp_wire = NULL;
    int payload_length, result;
    ULONGLONG started = GetTickCount64();
    int success = 0;

    initialize_record(record, config, sequence, phase, protocol,
        local_port, remote_ip, remote_port, expected_action, expect, tcp_peer_policy);
    record->socket_id = socket_id;
    record->close_mode = "held_active";
    payload = (unsigned char *)malloc(MAX_PAYLOAD);
    response = (unsigned char *)malloc(MAX_PAYLOAD);
    if (protocol == PROTO_UDP) {
        udp_wire = (unsigned char *)malloc(MAX_UDP_PAYLOAD + 16);
    }
    if (!payload || !response || (protocol == PROTO_UDP && !udp_wire)) {
        record->wsa_error = WSA_NOT_ENOUGH_MEMORY;
        copy_text(record->actual_result, sizeof(record->actual_result), "fail:memory_allocation");
        goto done;
    }
    if (!build_payload(config, sequence, phase, protocol, payload, &payload_length)) {
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
        if (!start_tcp_rtt(socket_handle, record)) goto done;
        if (config->payload_size_explicit || config->tcp_rtt) {
            result = send_tcp_frame_header(socket_handle, config, payload_length,
                &record->wsa_error);
            if (result == SOCKET_ERROR) {
                copy_text(record->actual_result, sizeof(record->actual_result), "fail:send_frame");
                goto done;
            }
        }
        result = send_all(socket_handle, (const char *)payload, payload_length,
            &record->wsa_error);
        if (result == SOCKET_ERROR) {
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:send");
            goto done;
        }
        record->bytes_sent = result;
        result = recv_exact(socket_handle, (char *)response, payload_length,
            &record->wsa_error);
        if (config->tcp_rtt) record->tcp_receive_qpc_ms = qpc_ms();
        if (result == SOCKET_ERROR) {
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:recv");
            goto done;
        }
        record->bytes_received = result;
        record->response_count = 1;
    } else {
        const unsigned char *wire_payload;
        int wire_length;
        if (!build_udp_wire_payload(config, payload, payload_length, udp_wire,
            &wire_payload, &wire_length)) {
            record->wsa_error = WSAEMSGSIZE;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:udp_control_payload");
            goto done;
        }
        record->udp_send_qpc_ms = qpc_ms();
        result = config->udp_mode == UDP_CONNECTED ?
            send(socket_handle, (const char *)wire_payload, wire_length, 0) :
            sendto(socket_handle, (const char *)wire_payload, wire_length, 0,
                (const struct sockaddr *)&remote, remote_length);
        if (result == SOCKET_ERROR || result != wire_length) {
            record->wsa_error = result == SOCKET_ERROR ? WSAGetLastError() : WSAEMSGSIZE;
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:send");
            goto done;
        }
        record->bytes_sent = payload_length;
        response_source_length = sizeof(response_source);
        memset(&response_source, 0, sizeof(response_source));
        result = recvfrom(socket_handle, (char *)response, MAX_PAYLOAD, 0,
            (struct sockaddr *)&response_source, &response_source_length);
        record->udp_receive_qpc_ms = qpc_ms();
        if (result == SOCKET_ERROR) {
            record->wsa_error = WSAGetLastError();
            copy_text(record->actual_result, sizeof(record->actual_result), "fail:recvfrom");
            goto done;
        }
        record->bytes_received = result;
        record->response_count = 1;
        if (!check_udp_source(record, &remote, &response_source, response)) goto done;
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
    mark_valid_response(record);
    success = 1;
done:
    record->timing_ms = GetTickCount64() - started;
    free(udp_wire);
    free(response);
    free(payload);
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

typedef struct {
    FILE *log_file;
    CRITICAL_SECTION log_lock;
    HANDLE start_gate;
    HANDLE measurement_gate;
    volatile LONG ready;
    volatile LONG aborted;
    unsigned int streams;
} BENCHMARK_SHARED;

typedef struct {
    CONFIG config;
    BENCHMARK_SHARED *shared;
    HANDLE thread;
    int success;
} BENCHMARK_STREAM;

static DWORD WINAPI benchmark_stream_thread(LPVOID parameter)
{
    BENCHMARK_STREAM *context = (BENCHMARK_STREAM *)parameter;
    CONFIG *config = &context->config;
    BENCHMARK_SHARED *shared = context->shared;
    SOCKET held = INVALID_SOCKET;
    FLOW_RECORD first, record;
    unsigned int local_sequence;
    int ok = 1;
    memset(&first, 0, sizeof(first));
    WaitForSingleObject(shared->start_gate, INFINITE);
    for (local_sequence = 1; local_sequence <= config->stream_count; local_sequence++) {
        unsigned int sequence = (config->benchmark_stream_index - 1) * config->stream_count + local_sequence;
        char phase[32];
        if (local_sequence == config->benchmark_warmup_count + 1) {
            if ((unsigned int)InterlockedIncrement(&shared->ready) == shared->streams)
                SetEvent(shared->measurement_gate);
            WaitForSingleObject(shared->measurement_gate, INFINITE);
        }
        if (InterlockedCompareExchange(&shared->aborted, 0, 0)) { ok = 0; break; }
        if (local_sequence > 1 && config->stream_interval_ms) Sleep(config->stream_interval_ms);
        snprintf(phase, sizeof(phase), "stream_%u", sequence);
        if (local_sequence == 1) {
            ok = perform_flow(config, (int)sequence, phase, config->protocol, 0,
                config->remote_ip, config->udp_remote_port, 0, config->expected_action,
                config->expect, config->tcp_peer_policy, &held, &first);
            first.close_mode = "held_active";
            record = first;
        } else {
            ok = perform_existing_socket_flow(config, held, (int)sequence, phase,
                config->protocol, first.socket_id, first.actual_local_port,
                config->remote_ip, config->udp_remote_port, config->expected_action,
                config->expect, config->tcp_peer_policy, &record);
        }
        EnterCriticalSection(&shared->log_lock);
        if (!write_record(shared->log_file, &record)) ok = 0;
        LeaveCriticalSection(&shared->log_lock);
        if (!ok) {
            InterlockedExchange(&shared->aborted, 1);
            SetEvent(shared->measurement_gate);
            break;
        }
    }
    if (held != INVALID_SOCKET) closesocket(held);
    context->success = ok;
    return 0;
}

static int perform_benchmark_streams(const CONFIG *config, FILE *log_file)
{
    BENCHMARK_SHARED shared;
    BENCHMARK_STREAM *contexts;
    unsigned int index, started = 0;
    int ok = 1;
    memset(&shared, 0, sizeof(shared));
    shared.log_file = log_file;
    shared.streams = config->benchmark_streams;
    shared.start_gate = CreateEvent(NULL, TRUE, FALSE, NULL);
    shared.measurement_gate = CreateEvent(NULL, TRUE, FALSE, NULL);
    contexts = (BENCHMARK_STREAM *)calloc(shared.streams, sizeof(*contexts));
    if (!shared.start_gate || !shared.measurement_gate || !contexts) {
        if (shared.start_gate) CloseHandle(shared.start_gate);
        if (shared.measurement_gate) CloseHandle(shared.measurement_gate);
        free(contexts);
        return 0;
    }
    InitializeCriticalSection(&shared.log_lock);
    for (index = 0; index < shared.streams; index++) {
        contexts[index].config = *config;
        contexts[index].config.benchmark_stream_index = index + 1;
        if (index == 1 && config->benchmark_alternate_port) {
            contexts[index].config.udp_remote_port = config->benchmark_alternate_port;
            contexts[index].config.second_remote_port = config->benchmark_alternate_port;
        }
        contexts[index].shared = &shared;
        contexts[index].thread = CreateThread(NULL, 0, benchmark_stream_thread, &contexts[index], 0, NULL);
        if (!contexts[index].thread) { ok = 0; break; }
        started++;
    }
    if (!ok) {
        InterlockedExchange(&shared.aborted, 1);
        SetEvent(shared.measurement_gate);
    }
    SetEvent(shared.start_gate);
    for (index = 0; index < started; index++) {
        WaitForSingleObject(contexts[index].thread, INFINITE);
        if (!contexts[index].success) ok = 0;
        CloseHandle(contexts[index].thread);
    }
    CloseHandle(shared.start_gate);
    CloseHandle(shared.measurement_gate);
    DeleteCriticalSection(&shared.log_lock);
    free(contexts);
    return ok;
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
        if (config.benchmark_streams > 1) {
            ok = perform_benchmark_streams(&config, log_file);
        } else if (config.reconnect_count > 1) {
            unsigned int sequence;
            ok = 1;
            for (sequence = 1; sequence <= config.reconnect_count; sequence++) {
                FLOW_RECORD reconnect_record;
                char phase[32];
                if (sequence > 1 && config.inter_flow_wait_ms > 0) {
                    Sleep(config.inter_flow_wait_ms);
                }
                snprintf(phase, sizeof(phase), "reconnect_%u", sequence);
                if (!perform_flow(&config, (int)sequence, phase,
                    config.protocol, 0, config.remote_ip, remote_port, 0,
                    config.expected_action, config.expect,
                    config.tcp_peer_policy, NULL, &reconnect_record)) {
                    ok = 0;
                }
                if (!write_record(log_file, &reconnect_record)) {
                    exit_code = 6; goto cleanup;
                }
            }
        } else if (config.parallel_count > 1) {
            PARALLEL_FLOW_CONTEXT contexts[MAX_PARALLEL];
            unsigned int index;
            ok = 1;
            memset(contexts, 0, sizeof(contexts));
            for (index = 0; index < config.parallel_count; index++) {
                PARALLEL_FLOW_CONTEXT *context = &contexts[index];
                context->config = &config;
                context->sequence = (int)index + 1;
                snprintf(context->phase, sizeof(context->phase),
                    "parallel_%u", index + 1);
                context->thread = CreateThread(NULL, 0, parallel_flow_thread,
                    context, 0, NULL);
                if (!context->thread) {
                    initialize_record(&context->record, &config,
                        context->sequence, context->phase, config.protocol, 0,
                        config.remote_ip, remote_port, config.expected_action,
                        config.expect, config.tcp_peer_policy);
                    context->record.wsa_error = (int)GetLastError();
                    copy_text(context->record.actual_result,
                        sizeof(context->record.actual_result), "fail:thread_create");
                    ok = 0;
                }
            }
            for (index = 0; index < config.parallel_count; index++) {
                PARALLEL_FLOW_CONTEXT *context = &contexts[index];
                if (context->thread) {
                    DWORD wait_result = WaitForSingleObject(context->thread, INFINITE);
                    if (wait_result != WAIT_OBJECT_0) {
                        context->success = 0;
                        context->record.wsa_error = (int)GetLastError();
                        copy_text(context->record.actual_result,
                            sizeof(context->record.actual_result), "fail:thread_wait");
                    }
                    CloseHandle(context->thread);
                }
                if (!context->success) ok = 0;
                if (!write_record(log_file, &context->record)) {
                    exit_code = 6; goto cleanup;
                }
            }
        } else if (config.stream_count > 1) {
            if (config.protocol == PROTO_UDP &&
                _stricmp(config.endpoint_behavior, "late-response") == 0) {
                ok = perform_udp_late_response_reuse(&config, remote_port,
                    &first, &second);
                if (!write_record(log_file, &first) ||
                    !write_record(log_file, &second)) { exit_code = 6; goto cleanup; }
            } else if (config.protocol == PROTO_UDP &&
                _stricmp(config.endpoint_behavior, "out-of-order") == 0) {
                ok = perform_udp_out_of_order(&config, remote_port, &first, &second);
                if (!write_record(log_file, &first) ||
                    !write_record(log_file, &second)) { exit_code = 6; goto cleanup; }
            } else {
                unsigned int sequence;
                char phase[32];
                snprintf(phase, sizeof(phase), "stream_1");
                ok = perform_flow(&config, 1, phase, config.protocol,
                    config.local_port, config.remote_ip, remote_port, 0,
                    config.expected_action, config.expect, config.tcp_peer_policy,
                    &held, &first);
                first.close_mode = "held_active";
                if (!write_record(log_file, &first)) { exit_code = 6; goto cleanup; }
                for (sequence = 2; ok && sequence <= config.stream_count; sequence++) {
                    unsigned short stream_remote_port = config.protocol == PROTO_UDP ?
                        config.second_remote_port : remote_port;
                    if (config.stream_interval_ms > 0) Sleep(config.stream_interval_ms);
                    snprintf(phase, sizeof(phase), "stream_%u", sequence);
                ok = perform_existing_socket_flow(&config, held, (int)sequence,
                    phase, config.protocol, first.socket_id, first.actual_local_port,
                        config.remote_ip, stream_remote_port, config.expected_action,
                        config.expect, config.tcp_peer_policy, &recheck);
                    if (!write_record(log_file, &recheck)) { exit_code = 6; goto cleanup; }
                }
            }
        } else {
            char process_phase[32];
            int sequence = 1;
            const char *phase = "single";
            if (config.process_index > 0) {
                sequence = (int)config.process_index;
                snprintf(process_phase, sizeof(process_phase),
                    "process_%u", config.process_index);
                phase = process_phase;
            }
            ok = perform_flow(&config, sequence, phase, config.protocol,
                config.local_port, config.remote_ip, remote_port, 0,
                config.expected_action, config.expect, config.tcp_peer_policy,
                NULL, &first);
            if (!write_record(log_file, &first)) { exit_code = 6; goto cleanup; }
        }
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
            ok = perform_existing_socket_flow(&config, held, 3, "held_recheck",
                config.first_protocol, first.socket_id, first.actual_local_port,
                config.remote_ip, first_remote_port,
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
            if (config.first_expected_action == ACTION_BLOCK) {
                ok = closesocket(held) == 0;
                if (!ok) close_error = WSAGetLastError();
                first.close_mode = "unconnected";
            } else {
                ok = close_first_issue206(held, config.close_mode, &close_error);
            }
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
