use broken_app::{algo, concurrency, leak_buffer, normalize, sum_even};

fn main() {
    let nums: Vec<i64> = (0..100_000).collect();
    println!("sum_even: {}", sum_even(&nums));

    let data = [1_u8, 0, 2, 3];
    println!("non-zero bytes: {}", leak_buffer(&data));

    let text = " Hello World ";
    println!("normalize: {}", normalize(text));

    let fib = algo::slow_fib(40);
    println!("fib(40): {fib}");

    let dedup_data: Vec<u64> = (0..5_000).flat_map(|n| [n, n]).collect();
    let uniq = algo::slow_dedup(&dedup_data);
    println!("dedup len: {}", uniq.len());

    let counter = concurrency::race_increment(1_000, 4);
    println!(
        "race_increment(1000, 4): {}",
        concurrency::read_counter(&counter)
    );
}
