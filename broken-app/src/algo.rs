/// # Performance
///
/// **CPU:** 2.59% of total samples in flamegraph (`flamegraph_before.svg`).
/// Hotspots inside:
/// - `sort_unstable` called on every insertion — O(n log n) per element,
///   making the overall complexity O(n² log n) instead of O(n log n).
/// - Linear scan of `out` for duplicate check — O(n) per element.
///
/// **Heap (massif_before.out):** output `Vec` starts with zero capacity and
/// grows via repeated `grow_amortized` reallocations.
/// At peak, `slow_dedup` holds 65,536 bytes due to amortized doubling.
/// Fix: `Vec::with_capacity(values.len())`.
#[cfg(not(feature = "optimized"))]
pub fn slow_dedup(values: &[u64]) -> Vec<u64> {
    let mut out = Vec::new();
    for v in values {
        let mut seen = false;
        for existing in &out {
            if existing == v {
                seen = true;
                break;
            }
        }
        if !seen {
            out.push(*v);
            out.sort_unstable(); // бесполезная сортировка на каждой вставке
        }
    }
    out
}

/// Optimized dedup: O(n log n) via sort + dedup, pre-allocated output.
#[cfg(feature = "optimized")]
pub fn slow_dedup(values: &[u64]) -> Vec<u64> {
    let mut out = Vec::with_capacity(values.len());
    out.extend_from_slice(values);
    out.sort_unstable();
    out.dedup();
    out
}

/// Классическая экспоненциальная реализация без мемоизации — будет медленной на больших n.
///
/// # Performance
///
/// **CPU:** dominant hotspot — 97.41% of total samples in flamegraph
/// (`flamegraph_before.svg`). Complexity is O(2ⁿ), so `slow_fib(40)`
/// makes ~2.8 billion recursive calls. The deep call stack is clearly
/// visible as a tall tower of `slow_fib` frames in the flamegraph.
///
/// **Heap:** zero heap allocations — pure stack recursion.
/// Fix: memoization (HashMap) or iterative DP reduces to O(n).
///
/// # Panics
///
/// Wraps around silently in release mode for `n > 93` (exceeds `u64::MAX`).
/// In debug mode panics on overflow.
#[cfg(not(feature = "optimized"))]
pub fn slow_fib(n: u64) -> u64 {
    match n {
        0 => 0,
        1 => 1,
        _ => slow_fib(n - 1) + slow_fib(n - 2),
    }
}

/// Optimized fib: iterative DP, O(n) time, O(1) space.
///
/// # Panics
///
/// Wraps around silently in release mode for `n > 93` (exceeds `u64::MAX`).
/// In debug mode panics on overflow.
#[cfg(feature = "optimized")]
pub fn slow_fib(n: u64) -> u64 {
    let (mut a, mut b) = (0u64, 1u64);
    for _ in 0..n {
        (a, b) = (b, a + b);
    }
    a
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- slow_fib ---

    #[test]
    fn fib_base_cases() {
        assert_eq!(slow_fib(0), 0);
        assert_eq!(slow_fib(1), 1);
    }

    #[test]
    fn fib_known_values() {
        assert_eq!(slow_fib(2), 1);
        assert_eq!(slow_fib(6), 8);
        assert_eq!(slow_fib(10), 55);
        assert_eq!(slow_fib(20), 6765);
    }

    #[test]
    fn fib_sequence_is_additive() {
        // F(n) == F(n-1) + F(n-2) for any n >= 2
        for n in 2..=15 {
            assert_eq!(slow_fib(n), slow_fib(n - 1) + slow_fib(n - 2));
        }
    }

    // --- slow_dedup ---

    #[test]
    fn dedup_empty() {
        assert_eq!(slow_dedup(&[]), vec![]);
    }

    #[test]
    fn dedup_single_element() {
        assert_eq!(slow_dedup(&[7]), vec![7]);
    }

    #[test]
    fn dedup_all_same() {
        assert_eq!(slow_dedup(&[3, 3, 3]), vec![3]);
    }

    #[test]
    fn dedup_already_unique() {
        assert_eq!(slow_dedup(&[1, 2, 3]), vec![1, 2, 3]);
    }

    #[test]
    fn dedup_mixed_duplicates() {
        assert_eq!(slow_dedup(&[5, 5, 1, 2, 2, 3]), vec![1, 2, 3, 5]);
    }

    #[test]
    fn dedup_output_is_sorted() {
        let result = slow_dedup(&[9, 1, 5, 1, 3, 9]);
        let mut sorted = result.clone();
        sorted.sort_unstable();
        assert_eq!(result, sorted);
    }

    #[test]
    fn dedup_preserves_all_unique_values() {
        let input: Vec<u64> = (0..100).flat_map(|n| [n, n]).collect();
        let result = slow_dedup(&input);
        assert_eq!(result.len(), 100);
        assert_eq!(result, (0..100).collect::<Vec<u64>>());
    }
}
