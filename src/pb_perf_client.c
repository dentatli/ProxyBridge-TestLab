#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PERF_SCHEMA_VERSION 1
#define PERF_ID_MAX 64
#define PERF_WARMUP_MAX_MS 60000U
#define PERF_SAMPLE_MAX_MS 60000U
#define PERF_SAMPLES_MAX 1000U

typedef struct PerfOptions {
    int self_test;
    int offline;
    const char *protocol;
    char workload_id[PERF_ID_MAX + 1];
    char window_id[PERF_ID_MAX + 1];
    unsigned long warmup_ms;
    unsigned long sample_ms;
    unsigned long samples;
} PerfOptions;

static int fail_argument(const char *detail) {
    fprintf(stderr, "PERF_ARGUMENT_INVALID: %s\n", detail);
    return 2;
}

static int is_valid_id(const char *value) {
    size_t index;
    size_t length = value == NULL ? 0U : strlen(value);
    if (length == 0U || length > PERF_ID_MAX) {
        return 0;
    }
    for (index = 0U; index < length; ++index) {
        const unsigned char character = (unsigned char)value[index];
        if (!(isalnum(character) || character == '-' || character == '_' || character == '.')) {
            return 0;
        }
    }
    return 1;
}

static int copy_id(char *destination, const char *value) {
    size_t length;
    if (!is_valid_id(value)) {
        return 0;
    }
    length = strlen(value);
    memcpy(destination, value, length + 1U);
    return 1;
}

static int parse_bounded_unsigned(const char *value, unsigned long maximum, unsigned long *parsed) {
    char *end = NULL;
    unsigned long candidate;
    if (value == NULL || value[0] == '\0') {
        return 0;
    }
    errno = 0;
    candidate = strtoul(value, &end, 10);
    if (errno != 0 || end == value || *end != '\0' || candidate > maximum) {
        return 0;
    }
    *parsed = candidate;
    return 1;
}

static void print_usage(void) {
    fputs("Usage: pb_perf_client.exe --self-test | --offline --protocol tcp|udp --workload-id ID --window-id ID --warmup-ms 0..60000 --sample-ms 1..60000 --samples 1..1000\n", stderr);
}

static int parse_options(int argc, char **argv, PerfOptions *options) {
    int index;
    memset(options, 0, sizeof(*options));
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        options->self_test = 1;
        options->protocol = "tcp";
        (void)copy_id(options->workload_id, "self-test-workload");
        (void)copy_id(options->window_id, "self-test-window");
        options->warmup_ms = 1U;
        options->sample_ms = 1U;
        options->samples = 2U;
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        print_usage();
        return 1;
    }

    for (index = 1; index < argc; ++index) {
        const char *argument = argv[index];
        if (strcmp(argument, "--offline") == 0) {
            if (options->offline) {
                return fail_argument("offline specified more than once");
            }
            options->offline = 1;
        } else if (strcmp(argument, "--protocol") == 0) {
            if (++index >= argc || options->protocol != NULL) {
                return fail_argument("protocol");
            }
            options->protocol = argv[index];
        } else if (strcmp(argument, "--workload-id") == 0) {
            if (++index >= argc || options->workload_id[0] != '\0' || !copy_id(options->workload_id, argv[index])) {
                return fail_argument("workload_id");
            }
        } else if (strcmp(argument, "--window-id") == 0) {
            if (++index >= argc || options->window_id[0] != '\0' || !copy_id(options->window_id, argv[index])) {
                return fail_argument("window_id");
            }
        } else if (strcmp(argument, "--warmup-ms") == 0) {
            if (++index >= argc || options->warmup_ms != 0U || !parse_bounded_unsigned(argv[index], PERF_WARMUP_MAX_MS, &options->warmup_ms)) {
                return fail_argument("warmup_ms");
            }
        } else if (strcmp(argument, "--sample-ms") == 0) {
            if (++index >= argc || options->sample_ms != 0U || !parse_bounded_unsigned(argv[index], PERF_SAMPLE_MAX_MS, &options->sample_ms) || options->sample_ms == 0U) {
                return fail_argument("sample_ms");
            }
        } else if (strcmp(argument, "--samples") == 0) {
            if (++index >= argc || options->samples != 0U || !parse_bounded_unsigned(argv[index], PERF_SAMPLES_MAX, &options->samples) || options->samples == 0U) {
                return fail_argument("samples");
            }
        } else {
            return fail_argument("unknown option");
        }
    }

    if (!options->offline) {
        return fail_argument("mode");
    }
    if (options->protocol == NULL || (strcmp(options->protocol, "tcp") != 0 && strcmp(options->protocol, "udp") != 0)) {
        return fail_argument("protocol");
    }
    if (options->workload_id[0] == '\0') {
        return fail_argument("workload_id");
    }
    if (options->window_id[0] == '\0') {
        return fail_argument("window_id");
    }
    if (options->sample_ms == 0U) {
        return fail_argument("sample_ms");
    }
    if (options->samples == 0U) {
        return fail_argument("samples");
    }
    return 0;
}

static void emit_header(const PerfOptions *options, const char *mode, unsigned long long frequency) {
    printf("{\"record_type\":\"header\",\"schema_version\":%d,\"mode\":\"%s\",\"non_product_acceptance\":true,\"workload_id\":\"%s\",\"window_id\":\"%s\",\"protocol\":\"%s\",\"warmup_ms\":%lu,\"sample_ms\":%lu,\"sample_count\":%lu,\"monotonic_frequency\":%llu}\n",
        PERF_SCHEMA_VERSION, mode, options->workload_id, options->window_id, options->protocol, options->warmup_ms, options->sample_ms, options->samples, frequency);
}

static void emit_sample(const PerfOptions *options, const char *mode, unsigned long index, unsigned long long start_ticks, unsigned long long end_ticks,
    unsigned long long bytes, unsigned long long datagrams, unsigned long long lost, unsigned long long failures, double rate, double latency_us) {
    printf("{\"record_type\":\"sample\",\"schema_version\":%d,\"mode\":\"%s\",\"non_product_acceptance\":true,\"workload_id\":\"%s\",\"window_id\":\"%s\",\"protocol\":\"%s\",\"sample_index\":%lu,\"warmup_ms\":%lu,\"sample_ms\":%lu,\"monotonic_start_ticks\":%llu,\"monotonic_end_ticks\":%llu,\"bytes\":%llu,\"datagrams\":%llu,\"lost\":%llu,\"failures\":%llu,\"rate_bytes_per_second\":%.3f,\"latency_us\":%.3f}\n",
        PERF_SCHEMA_VERSION, mode, options->workload_id, options->window_id, options->protocol, index, options->warmup_ms, options->sample_ms,
        start_ticks, end_ticks, bytes, datagrams, lost, failures, rate, latency_us);
}

static void emit_summary(const PerfOptions *options, const char *mode, unsigned long long bytes, unsigned long long datagrams,
    unsigned long long lost, unsigned long long failures, double rate, double p50, double p95, double p99) {
    printf("{\"record_type\":\"summary\",\"schema_version\":%d,\"mode\":\"%s\",\"non_product_acceptance\":true,\"workload_id\":\"%s\",\"window_id\":\"%s\",\"protocol\":\"%s\",\"sample_count\":%lu,\"bytes\":%llu,\"datagrams\":%llu,\"lost\":%llu,\"failures\":%llu,\"rate_bytes_per_second\":%.3f,\"latency_p50_us\":%.3f,\"latency_p95_us\":%.3f,\"latency_p99_us\":%.3f}\n",
        PERF_SCHEMA_VERSION, mode, options->workload_id, options->window_id, options->protocol, options->samples,
        bytes, datagrams, lost, failures, rate, p50, p95, p99);
}

static int emit_offline_evidence(const PerfOptions *options) {
    LARGE_INTEGER frequency;
    unsigned long index;
    unsigned long long total_bytes = 0ULL;
    unsigned long long total_datagrams = 0ULL;
    unsigned long long total_lost = 0ULL;
    unsigned long long total_failures = 0ULL;
    double last_rate = 0.0;
    double last_latency = 0.0;
    const char *mode = options->self_test ? "self-test" : "offline";

    if (!QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0) {
        fputs("PERF_MONOTONIC_CLOCK_UNAVAILABLE\n", stderr);
        return 3;
    }
    emit_header(options, mode, (unsigned long long)frequency.QuadPart);
    for (index = 0U; index < options->samples; ++index) {
        LARGE_INTEGER start;
        LARGE_INTEGER end;
        unsigned long long bytes = strcmp(options->protocol, "tcp") == 0 ? 1024ULL * (unsigned long long)(index + 1U) : 0ULL;
        unsigned long long datagrams = strcmp(options->protocol, "udp") == 0 ? 16ULL + (unsigned long long)index : 0ULL;
        unsigned long long lost = 0ULL;
        unsigned long long failures = 0ULL;
        double rate;
        double latency = 100.0 + (double)(index * 10U);
        QueryPerformanceCounter(&start);
        QueryPerformanceCounter(&end);
        if (end.QuadPart <= start.QuadPart) {
            end.QuadPart = start.QuadPart + 1;
        }
        rate = (double)(bytes == 0ULL ? datagrams : bytes) * 1000.0 / (double)options->sample_ms;
        emit_sample(options, mode, index + 1U, (unsigned long long)start.QuadPart, (unsigned long long)end.QuadPart,
            bytes, datagrams, lost, failures, rate, latency);
        total_bytes += bytes;
        total_datagrams += datagrams;
        total_lost += lost;
        total_failures += failures;
        last_rate = rate;
        last_latency = latency;
    }
    emit_summary(options, mode, total_bytes, total_datagrams, total_lost, total_failures, last_rate,
        100.0, last_latency, last_latency);
    return 0;
}

int main(int argc, char **argv) {
    PerfOptions options;
    int parse_result = parse_options(argc, argv, &options);
    if (parse_result != 0) {
        return parse_result == 1 ? 0 : parse_result;
    }
    return emit_offline_evidence(&options);
}
