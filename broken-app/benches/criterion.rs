use broken_app::{algo, sum_even};
use criterion::{BatchSize, Criterion, criterion_group, criterion_main};

fn bench_sum_even(c: &mut Criterion) {
    let data: Vec<i64> = (0..50_000).collect();
    let label = if cfg!(feature = "optimized") {
        "sum_even_optimized"
    } else {
        "sum_even_slow"
    };
    c.bench_function(label, |b| b.iter(|| sum_even(&data)));
}

fn bench_fib(c: &mut Criterion) {
    let label = if cfg!(feature = "optimized") {
        "fib_optimized"
    } else {
        "fib_slow"
    };
    c.bench_function(label, |b| b.iter(|| algo::slow_fib(32)));
}

fn bench_dedup(c: &mut Criterion) {
    let data: Vec<u64> = (0..5_000).flat_map(|n| [n, n]).collect();
    let label = if cfg!(feature = "optimized") {
        "dedup_optimized"
    } else {
        "dedup_slow"
    };
    c.bench_function(label, |b| {
        b.iter_batched(
            || data.clone(),
            |v| {
                let _ = algo::slow_dedup(&v);
            },
            BatchSize::SmallInput,
        )
    });
}

criterion_group!(benches, bench_sum_even, bench_fib, bench_dedup);
criterion_main!(benches);
