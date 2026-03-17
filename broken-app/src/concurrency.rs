use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;

/// Потокобезопасный инкремент через несколько потоков.
/// Возвращает `Arc<AtomicU64>` — вызовы из разных тестов не мешают друг другу.
pub fn race_increment(iterations: usize, threads: usize) -> Arc<AtomicU64> {
    let counter = Arc::new(AtomicU64::new(0));
    let mut handles = Vec::with_capacity(threads);
    for _ in 0..threads {
        let counter = Arc::clone(&counter);
        handles.push(thread::spawn(move || {
            for _ in 0..iterations {
                counter.fetch_add(1, Ordering::SeqCst);
            }
        }));
    }
    for h in handles {
        let _ = h.join();
    }
    counter
}

/// Чтение текущего значения счётчика (атомарно).
pub fn read_counter(counter: &AtomicU64) -> u64 {
    counter.load(Ordering::SeqCst)
}
