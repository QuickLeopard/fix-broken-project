pub mod algo;
pub mod concurrency;

/// Сумма чётных значений.
/// Здесь намеренно используется `get_unchecked` с off-by-one,
/// из-за чего возникает UB при доступе за пределы среза.
pub fn sum_even(values: &[i64]) -> i64 {
    values.iter().filter(|&&v| v % 2 == 0).sum()
    /*let mut acc = 0;
    unsafe {
        for idx in 0..values.len() {
            let v = *values.get_unchecked(idx);
            if v % 2 == 0 {
                acc += v;
            }
        }
    }
    acc*/
}

/// Подсчёт ненулевых байтов. Буфер намеренно не освобождается,
/// что приведёт к утечке памяти (Valgrind это покажет).
pub fn leak_buffer(input: &[u8]) -> usize {
    input.iter().filter(|&&b| b != 0).count()
    /*let boxed = input.to_vec().into_boxed_slice();
    let len = input.len();
    let raw = Box::into_raw(boxed) as *mut u8;

    let mut count = 0;
    unsafe {
        for i in 0..len {
            if *raw.add(i) != 0_u8 {
                count += 1;
            }
        }
        // утечка: не вызываем Box::from_raw(raw);
    }
    count*/
}

/// Небрежная нормализация строки: удаляем пробелы и приводим к нижнему регистру,
/// но игнорируем повторяющиеся пробелы/табуляции внутри текста.
pub fn normalize(input: &str) -> String {
    //input.replace(' ', "").to_lowercase()
    input
        .split_whitespace()
        .collect::<String>()
        .to_lowercase()
}

/// Логическая ошибка: усредняет по всем элементам, хотя требуется учитывать
/// только положительные. Деление на длину среза даёт неверный результат.
pub fn average_positive(values: &[i64]) -> f64 {
    let only_positive: Vec<i64> = values.iter().filter(|&&x| x > 0).copied().collect();
    if only_positive.is_empty() {
        return 0.0;
    }
    let sum: i64 = only_positive.iter().sum();
    sum as f64 / only_positive.len() as f64
}

/// Демонстрация исправленного use-after-free.
/// Ранее содержал UB (`val + *raw` после освобождения бокса).
///
/// # Safety
///
/// Caller must ensure no other references to the allocated value exist.
pub unsafe fn use_after_free() -> i32 {
    let b = Box::new(42_i32);
    let raw = Box::into_raw(b);
    unsafe {
        let val = *raw;
        drop(Box::from_raw(raw));
        val + val
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- sum_even ---

    #[test]
    fn sum_even_basic() {
        assert_eq!(sum_even(&[1, 2, 3, 4]), 6);
    }

    #[test]
    fn sum_even_empty() {
        assert_eq!(sum_even(&[]), 0);
    }

    #[test]
    fn sum_even_no_evens() {
        assert_eq!(sum_even(&[1, 3, 5]), 0);
    }

    #[test]
    fn sum_even_all_evens() {
        assert_eq!(sum_even(&[2, 4, 6]), 12);
    }

    #[test]
    fn sum_even_negatives() {
        assert_eq!(sum_even(&[-2, -3, 4]), 2);
    }

    // --- leak_buffer ---

    #[test]
    fn leak_buffer_basic() {
        assert_eq!(leak_buffer(&[0_u8, 1, 0, 2, 3]), 3);
    }

    #[test]
    fn leak_buffer_empty() {
        assert_eq!(leak_buffer(&[]), 0);
    }

    #[test]
    fn leak_buffer_all_zeros() {
        assert_eq!(leak_buffer(&[0, 0, 0]), 0);
    }

    #[test]
    fn leak_buffer_all_nonzero() {
        assert_eq!(leak_buffer(&[1, 2, 3]), 3);
    }

    // --- normalize ---

    #[test]
    fn normalize_basic() {
        assert_eq!(normalize(" Hello World "), "helloworld");
    }

    #[test]
    fn normalize_empty() {
        assert_eq!(normalize(""), "");
    }

    #[test]
    fn normalize_tabs_and_spaces() {
        assert_eq!(normalize("\t Foo \t Bar \t"), "foobar");
    }

    #[test]
    fn normalize_already_clean() {
        assert_eq!(normalize("hello"), "hello");
    }

    // --- average_positive ---

    #[test]
    fn average_positive_basic() {
        assert!((average_positive(&[-5, 5, 15]) - 10.0).abs() < f64::EPSILON);
    }

    #[test]
    fn average_positive_empty() {
        assert_eq!(average_positive(&[]), 0.0);
    }

    #[test]
    fn average_positive_all_negative() {
        assert_eq!(average_positive(&[-1, -2, -3]), 0.0);
    }

    #[test]
    fn average_positive_single() {
        assert!((average_positive(&[7]) - 7.0).abs() < f64::EPSILON);
    }

    #[test]
    fn average_positive_ignores_negatives() {
        assert!((average_positive(&[-100, 10, 20]) - 15.0).abs() < f64::EPSILON);
    }

    // --- use_after_free ---

    #[test]
    fn use_after_free_returns_double() {
        // 42 + 42 = 84, no UB after fix
        assert_eq!(unsafe { use_after_free() }, 84);
    }
}

