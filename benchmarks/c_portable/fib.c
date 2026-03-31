/*
 * fib.c - Recursive Fibonacci Benchmark
 *
 * Branch-intensive workload: naive recursive Fibonacci (no memoization).
 * Tests: branch prediction, function call overhead, stack management.
 * fib(40) = 102334155, requires ~2^40 function calls.
 *
 * Compile:
 *   clang -O0 -o fib_O0 fib.c    (no optimization — matches assembly behavior)
 *   clang -O2 -o fib_O2 fib.c    (may partially optimize recursion)
 *   gcc   -O0 -o fib_O0 fib.c
 *   gcc   -O2 -o fib_O2 fib.c
 *
 * Run:
 *   ./fib_O0              (default n=40)
 *   ./fib_O0 42           (custom n — WARNING: grows exponentially)
 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* Naive recursive Fibonacci — intentionally not optimized.
 * This is a microbenchmark for function call overhead and branch prediction,
 * NOT a demonstration of how to compute Fibonacci numbers efficiently. */
static long long fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(int argc, char *argv[]) {
    int n = 40;
    if (argc > 1) n = atoi(argv[1]);

    printf("Recursive Fibonacci Benchmark\n");
    printf("Computing fib(%d)\n", n);

    struct timespec start, end;

    clock_gettime(CLOCK_MONOTONIC, &start);
    long long result = fib(n);
    clock_gettime(CLOCK_MONOTONIC, &end);

    double elapsed = (end.tv_sec - start.tv_sec) +
                     (end.tv_nsec - start.tv_nsec) / 1e9;

    /* Approximate number of function calls: fib(n+1) total calls */
    /* For n=40, this is about 331 million calls */
    long long approx_calls = result * 2 - 1;

    printf("Result:          fib(%d) = %lld\n", n, result);
    printf("Elapsed time:    %.6f seconds\n", elapsed);
    printf("Approx calls:    %lld million\n", approx_calls / 1000000);
    printf("Calls per sec:   %.2f million\n", (double)approx_calls / elapsed / 1e6);

    return 0;
}
