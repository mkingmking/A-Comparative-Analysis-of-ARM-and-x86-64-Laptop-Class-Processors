/*
 * matmul.c - Matrix Multiplication Benchmark
 * 
 * Compute-intensive workload: C = A × B for NxN integer matrices.
 * Tests: ALU throughput, register allocation, loop optimization, ILP.
 * 
 * Compile:
 *   clang -O0 -o matmul_O0 matmul.c   (no optimization — closer to assembly)
 *   clang -O2 -o matmul_O2 matmul.c   (optimized — shows compiler advantage)
 *   gcc   -O0 -o matmul_O0 matmul.c
 *   gcc   -O2 -o matmul_O2 matmul.c
 *
 * Run:
 *   ./matmul_O0          (default N=256)
 *   ./matmul_O0 512      (custom size)
 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

#define DEFAULT_N 256

/* Use volatile to prevent compiler from optimizing away the computation */
static volatile int sink;

static void matmul(int N, int *A, int *B, int *C) {
    int i, j, k;
    for (i = 0; i < N; i++) {
        for (j = 0; j < N; j++) {
            int sum = 0;
            for (k = 0; k < N; k++) {
                sum += A[i * N + k] * B[k * N + j];
            }
            C[i * N + j] = sum;
        }
    }
}

static void fill_matrix(int *M, int N) {
    for (int i = 0; i < N * N; i++) {
        M[i] = rand() % 100;
    }
}

int main(int argc, char *argv[]) {
    int N = DEFAULT_N;
    if (argc > 1) N = atoi(argv[1]);

    printf("Matrix Multiplication Benchmark\n");
    printf("Matrix size: %d x %d\n", N, N);
    printf("Total operations: %lld multiply-accumulate\n", (long long)N * N * N);

    /* Allocate matrices */
    int *A = (int *)malloc(N * N * sizeof(int));
    int *B = (int *)malloc(N * N * sizeof(int));
    int *C = (int *)malloc(N * N * sizeof(int));

    if (!A || !B || !C) {
        fprintf(stderr, "Memory allocation failed\n");
        return 1;
    }

    srand(42); /* Fixed seed for reproducibility */
    fill_matrix(A, N);
    fill_matrix(B, N);
    memset(C, 0, N * N * sizeof(int));

    /* Timing */
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    matmul(N, A, B, C);

    clock_gettime(CLOCK_MONOTONIC, &end);

    double elapsed = (end.tv_sec - start.tv_sec) + 
                     (end.tv_nsec - start.tv_nsec) / 1e9;

    /* Prevent dead-code elimination */
    sink = C[0] + C[N * N - 1];

    /* Results */
    long long ops = (long long)N * N * N * 2; /* multiply + add */
    double mops = ops / elapsed / 1e6;

    printf("Elapsed time:    %.6f seconds\n", elapsed);
    printf("Throughput:      %.2f MOPS\n", mops);
    printf("Checksum:        C[0]=%d, C[last]=%d\n", C[0], C[N*N-1]);

    free(A);
    free(B);
    free(C);

    return 0;
}
