/*
 * fib_profile.c - Long-running recursive Fibonacci profiling target.
 *
 * This is a single-process profiling version of fib.c for Instruments CPU
 * Counters. It repeats the same naive recursive fib(n) workload internally, so
 * hardware-counter totals are captured under one process instead of many short
 * shell-launched processes.
 *
 * Defaults are chosen for Apple M3 profiling:
 *   n = 40, repetitions = 50
 *
 * Run:
 *   ./fib_profile
 *   ./fib_profile 40 50
 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static volatile long long sink;

static long long fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(int argc, char *argv[]) {
    int n = 40;
    int repetitions = 50;

    if (argc > 1) n = atoi(argv[1]);
    if (argc > 2) repetitions = atoi(argv[2]);

    if (n < 0 || repetitions < 1) {
        fprintf(stderr, "Usage: %s [n>=0] [repetitions>=1]\n", argv[0]);
        return 1;
    }

    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    long long checksum = 0;
    for (int i = 0; i < repetitions; i++) {
        checksum += fib(n);
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    sink = checksum;

    double elapsed = (end.tv_sec - start.tv_sec) +
                     (end.tv_nsec - start.tv_nsec) / 1e9;

    printf("Recursive Fibonacci profiling target\n");
    printf("n:              %d\n", n);
    printf("repetitions:    %d\n", repetitions);
    printf("checksum:       %lld\n", checksum);
    printf("elapsed:        %.6f seconds\n", elapsed);
    printf("seconds/run:    %.6f\n", elapsed / repetitions);

    return 0;
}
