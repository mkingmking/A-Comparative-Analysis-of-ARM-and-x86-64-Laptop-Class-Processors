/*
 * matmul_profile.c - Long-running matrix multiplication profiling target.
 *
 * This is a single-process profiling version of matmul.c for Instruments CPU
 * Counters. It repeats the same NxN integer matrix multiplication internally,
 * so hardware-counter totals are captured under one process instead of many
 * short shell-launched processes.
 *
 * Defaults are chosen for Apple M3 profiling:
 *   N = 256, repetitions = 1000
 *
 * Run:
 *   ./matmul_profile
 *   ./matmul_profile 256 1000
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define DEFAULT_N 256

static volatile int sink;

static void matmul(int n, int *a, int *b, int *c) {
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            int sum = 0;
            for (int k = 0; k < n; k++) {
                sum += a[i * n + k] * b[k * n + j];
            }
            c[i * n + j] = sum;
        }
    }
}

static void fill_matrix(int *m, int n) {
    for (int i = 0; i < n * n; i++) {
        m[i] = rand() % 100;
    }
}

int main(int argc, char *argv[]) {
    int n = DEFAULT_N;
    int repetitions = 1000;

    if (argc > 1) n = atoi(argv[1]);
    if (argc > 2) repetitions = atoi(argv[2]);

    if (n < 1 || repetitions < 1) {
        fprintf(stderr, "Usage: %s [matrix_size>=1] [repetitions>=1]\n", argv[0]);
        return 1;
    }

    int *a = (int *)malloc((size_t)n * n * sizeof(int));
    int *b = (int *)malloc((size_t)n * n * sizeof(int));
    int *c = (int *)malloc((size_t)n * n * sizeof(int));

    if (!a || !b || !c) {
        fprintf(stderr, "Memory allocation failed\n");
        free(a);
        free(b);
        free(c);
        return 1;
    }

    srand(42);
    fill_matrix(a, n);
    fill_matrix(b, n);
    memset(c, 0, (size_t)n * n * sizeof(int));

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    long long checksum = 0;
    for (int rep = 0; rep < repetitions; rep++) {
        matmul(n, a, b, c);
        checksum += c[0] + c[n * n - 1];
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    sink = (int)checksum;

    double elapsed = (end.tv_sec - start.tv_sec) +
                     (end.tv_nsec - start.tv_nsec) / 1e9;

    printf("Matrix multiplication profiling target\n");
    printf("matrix size:    %d x %d\n", n, n);
    printf("repetitions:    %d\n", repetitions);
    printf("checksum:       %lld\n", checksum);
    printf("elapsed:        %.6f seconds\n", elapsed);
    printf("seconds/run:    %.6f\n", elapsed / repetitions);

    free(a);
    free(b);
    free(c);

    return 0;
}
