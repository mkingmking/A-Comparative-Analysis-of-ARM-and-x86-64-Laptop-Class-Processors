/*
 * memwalk.c - Memory Bandwidth / Cache Hierarchy Benchmark
 *
 * Memory-intensive workload: sequential and strided walks over a large array.
 * Tests: memory bandwidth, cache hit/miss behavior, prefetching effectiveness.
 *
 * Compile:
 *   clang -O2 -o memwalk memwalk.c
 *   gcc   -O2 -o memwalk memwalk.c
 *
 * Run:
 *   ./memwalk              (default 64 MB)
 *   ./memwalk 128          (128 MB array)
 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

#define DEFAULT_SIZE_MB 64
#define ITERATIONS 10

static volatile long long sink;

/* Sequential sum — tests raw memory bandwidth */
static long long sequential_sum(int *arr, size_t count) {
    long long sum = 0;
    for (size_t i = 0; i < count; i++) {
        sum += arr[i];
    }
    return sum;
}

/* Strided access — tests cache line utilization */
static long long strided_sum(int *arr, size_t count, int stride) {
    long long sum = 0;
    for (size_t i = 0; i < count; i += stride) {
        sum += arr[i];
    }
    return sum;
}

/* Random access — tests TLB and cache associativity */
static long long random_chase(int *arr, size_t count, size_t num_accesses) {
    long long sum = 0;
    size_t idx = 0;
    for (size_t i = 0; i < num_accesses; i++) {
        sum += arr[idx];
        idx = (size_t)((unsigned int)arr[idx]) % count;
    }
    return sum;
}

static double time_diff(struct timespec *start, struct timespec *end) {
    return (end->tv_sec - start->tv_sec) + (end->tv_nsec - start->tv_nsec) / 1e9;
}

int main(int argc, char *argv[]) {
    size_t size_mb = DEFAULT_SIZE_MB;
    if (argc > 1) size_mb = (size_t)atoi(argv[1]);

    size_t count = size_mb * 1024 * 1024 / sizeof(int);
    size_t bytes = count * sizeof(int);

    printf("Memory Walk Benchmark\n");
    printf("Array size: %zu MB (%zu elements)\n", size_mb, count);
    printf("Iterations: %d\n\n", ITERATIONS);

    int *arr = (int *)malloc(bytes);
    if (!arr) {
        fprintf(stderr, "Memory allocation failed\n");
        return 1;
    }

    /* Initialize with pseudorandom data */
    srand(42);
    for (size_t i = 0; i < count; i++) {
        arr[i] = rand();
    }

    struct timespec start, end;

    /* --- Test 1: Sequential access --- */
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (int iter = 0; iter < ITERATIONS; iter++) {
        sink = sequential_sum(arr, count);
    }
    clock_gettime(CLOCK_MONOTONIC, &end);

    double seq_time = time_diff(&start, &end);
    double seq_bw = (double)(bytes * ITERATIONS) / seq_time / (1024.0 * 1024.0 * 1024.0);
    printf("Sequential access:\n");
    printf("  Time: %.4f s, Bandwidth: %.2f GB/s\n\n", seq_time, seq_bw);

    /* --- Test 2: Strided access (stride=16 = 64 bytes = 1 cache line) --- */
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (int iter = 0; iter < ITERATIONS; iter++) {
        sink = strided_sum(arr, count, 16);
    }
    clock_gettime(CLOCK_MONOTONIC, &end);

    double str_time = time_diff(&start, &end);
    double str_bw = (double)(bytes * ITERATIONS) / str_time / (1024.0 * 1024.0 * 1024.0);
    printf("Strided access (stride=16, 64B):\n");
    printf("  Time: %.4f s, Effective BW: %.2f GB/s\n\n", str_time, str_bw);

    /* --- Test 3: Random pointer chase --- */
    size_t num_accesses = count; /* same number of accesses as sequential */
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (int iter = 0; iter < ITERATIONS; iter++) {
        sink = random_chase(arr, count, num_accesses);
    }
    clock_gettime(CLOCK_MONOTONIC, &end);

    double rand_time = time_diff(&start, &end);
    double rand_access_rate = (double)(num_accesses * ITERATIONS) / rand_time / 1e6;
    printf("Random access (pointer chase):\n");
    printf("  Time: %.4f s, Access rate: %.2f M accesses/s\n\n", rand_time, rand_access_rate);

    /* Summary */
    printf("--- Summary ---\n");
    printf("Sequential BW: %.2f GB/s\n", seq_bw);
    printf("Random/Sequential ratio: %.2fx slower\n", rand_time / seq_time);

    free(arr);
    return 0;
}
