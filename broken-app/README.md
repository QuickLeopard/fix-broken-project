# broken-app

Учебный проект по отладке, профилированию и анализу памяти на Rust.  
Содержит намеренно сломанные функции, исправленные версии и инфраструктуру для
сравнительного бенчмаркинга, поиска утечек памяти и CI/CD.

---

## Содержание

1. [Структура проекта](#структура-проекта)
2. [Функции библиотеки](#функции-библиотеки)
3. [Feature-флаги](#feature-флаги)
4. [Тестирование](#тестирование)
5. [Бенчмаркинг](#бенчмаркинг)
6. [Профилирование](#профилирование)
7. [Поиск утечек памяти](#поиск-утечек-памяти)
8. [Docker](#docker)
9. [Скрипты](#скрипты)
10. [GitHub Actions](#github-actions)
11. [Артефакты](#артефакты)

---

## Структура проекта

```
broken-app/
├── src/
│   ├── lib.rs          # Основные функции (sum_even, leak_buffer, normalize, …)
│   ├── algo.rs         # Алгоритмы (slow_dedup, slow_fib) — slow/optimized варианты
│   ├── concurrency.rs  # Многопоточность (race_increment, read_counter)
│   └── bin/
│       └── demo.rs     # Бинарник для профилирования и Valgrind
├── benches/
│   ├── baseline.rs     # Простой таймер через std::time
│   └── criterion.rs    # Статистические бенчмарки через Criterion
├── tests/
│   └── integration.rs  # Интеграционные тесты
├── scripts/
│   ├── profile.ps1     # Flamegraph + Massif через Docker (Windows PowerShell)
│   ├── profile.sh      # Flamegraph + Massif через Docker (Bash)
│   ├── compare.ps1     # Сравнение baseline-бенчмарков (Windows PowerShell)
│   └── compare.sh      # Сравнение baseline-бенчмарков (Bash)
├── artifacts/          # Сохранённые результаты профилирования и логи
├── .dockerignore
├── Dockerfile
└── Cargo.toml
```

---

## Функции библиотеки

| Функция | Файл | Исправленная ошибка |
|---|---|---|
| `sum_even` | `lib.rs` | off-by-one: `0..=` → `0..` |
| `leak_buffer` | `lib.rs` | утечка Box: заменена на безопасный итератор |
| `normalize` | `lib.rs` | `replace(' ', "")` → `split_whitespace()` (не обрабатывал табы и множественные пробелы) |
| `average_positive` | `lib.rs` | деление на все элементы вместо только положительных |
| `use_after_free` | `lib.rs` | UB: `val + *raw` после `drop` → `val + val` |
| `slow_dedup` | `algo.rs` | O(n² log n): сортировка на каждой вставке |
| `slow_fib` | `algo.rs` | O(2ⁿ): рекурсия без мемоизации |

### Производительность алгоритмов (baseline: sum_even n=50000, dedup n=5000×2, fib n=32)

| Функция | slow | optimized | ускорение |
|---|---|---|---|
| `slow_fib(32)` | ~19–32 мс | ~100 нс | **~200 000×** |
| `slow_dedup` | ~41–50 мс | ~12–100 мкс | **~400–4000×** |
| `sum_even` | ~25–88 мкс | ~15–52 мкс | без изменений |

> Бенчмарки обёрнуты в `std::hint::black_box()` для предотвращения
> устранения мёртвого кода компилятором (LLVM).

---

## Feature-флаги

Проект поддерживает два варианта реализации алгоритмов через Cargo feature:

```toml
[features]
optimized = []   # по умолчанию отключён
```

| Вариант | `slow_fib` | `slow_dedup` |
|---|---|---|
| `default` (slow) | рекурсия O(2ⁿ) | линейный поиск + сортировка на каждой вставке |
| `optimized` | итеративный DP O(n) | sort + dedup с предварительным выделением памяти |

Оба варианта возвращают **одинаковый результат** — контракт функций не меняется.

Сборка с нужным вариантом:

```powershell
cargo build                          # slow (по умолчанию)
cargo build --features optimized     # optimized
```

---

## Тестирование

### Юнит-тесты (`src/lib.rs`)

19 тестов покрывают все функции библиотеки, включая граничные случаи:
пустые срезы, отрицательные числа, строки с табуляцией.

```powershell
cargo test
```

### Интеграционные тесты (`tests/integration.rs`)

Тесты запускаются против публичного API крейта:

```powershell
cargo test --test integration
```

### Miri — обнаружение UB и некорректной работы с памятью

Miri выполняет код в интерпретаторе и обнаруживает:
- обращения к освобождённой памяти (use-after-free)
- выход за границы массива
- нарушения инвариантов типов

```powershell
# Установка (требуется nightly)
rustup toolchain install nightly --component miri
rustup override set nightly
cargo miri setup

# Запуск
cargo miri test --package broken-app --lib
cargo miri test --package broken-app --test integration
```

> Miri работает только на nightly и не поддерживает Windows-таргет напрямую.
> В CI запускается на `ubuntu-latest`.

---

## Бенчмаркинг

### Baseline (`benches/baseline.rs`)

Простой замер через `std::time::Instant`. Запускает каждую функцию 3 раза
и выводит время в консоль. Удобен для быстрой проверки.

```powershell
cargo bench --bench baseline                      # slow
cargo bench --bench baseline --features optimized # optimized
```

Пример вывода:
```
sum_even_slow: 25.1µs
slow_fib_slow: 19.0624ms
slow_dedup_slow: 46.2186ms
```

### Criterion (`benches/criterion.rs`)

Статистические бенчмарки с прогревом, несколькими итерациями и HTML-отчётом.

```powershell
cargo bench --bench criterion                      # slow
cargo bench --bench criterion --features optimized # optimized
```

HTML-отчёт сохраняется в `target/criterion/`. Открыть:
```powershell
start target\criterion\report\index.html
```

### Сравнение вариантов

Скрипт `compare.ps1` запускает оба варианта и выводит таблицу рядом:

```powershell
.\scripts\compare.ps1           # оба варианта + сравнение
.\scripts\compare.ps1 -Variant slow
.\scripts\compare.ps1 -Variant optimized
```

Результаты сохраняются в `artifacts\baseline_slow.txt` и
`artifacts\baseline_optimized.txt`.

---

## Профилирование

Профилирование требует Linux-инструментов (`perf`, `valgrind`) и выполняется
**внутри Docker**. На Windows используйте скрипт `profile.ps1`.

### Flamegraph — профиль CPU

Показывает, где программа тратит процессорное время.  
Инструмент: [`cargo-flamegraph`](https://github.com/flamegraph-rs/flamegraph) + `perf`.

Результат: `artifacts/flamegraph_<variant>.svg` — интерактивный SVG,
открывается в браузере.

**Выводы по проекту** (`flamegraph_before.svg`):
- `slow_fib` — **97.41%** всех сэмплов CPU
- `slow_dedup` — **2.59%**, горячая точка внутри `sort_unstable`

### Massif — профиль кучи

Показывает пиковое потребление памяти и места выделений.  
Инструмент: `valgrind --tool=massif` + `ms_print`.

Результат:
- `artifacts/massif_<variant>.out` — бинарный файл Valgrind
- `artifacts/massif_<variant>.txt` — текстовый отчёт `ms_print`

**Выводы по проекту** (`massif_before.out`):
- Пик кучи: **947 КБ**
- 800 КБ — `Vec` в `sum_even` (100 000 элементов × 8 байт)
- 80 КБ — входной `Vec` для `slow_dedup`
- 64 КБ — амортизированные перевыделения в `slow_dedup` (нет `with_capacity`)

---

## Поиск утечек памяти

### Valgrind (`--leak-check=full`)

Обнаруживает утечки памяти, обращения к неинициализированной памяти,
двойное освобождение. Запускается против бинарника `demo`.

```bash
# Внутри Docker или на Linux:
valgrind --leak-check=full --error-exitcode=1 ./target/debug/demo
```

Через Docker на Windows:
```powershell
docker build -t broken-app-profile .
docker run --rm broken-app-profile
# CMD в Dockerfile уже запускает valgrind на demo
```

### AddressSanitizer (ASan)

Обнаруживает use-after-free, heap-buffer-overflow, stack-buffer-overflow.  
Требует nightly и `-Zbuild-std` (иначе ABI mismatch со стандартной библиотекой).

```bash
RUSTFLAGS="-Zsanitizer=address" cargo +nightly test \
  -Zbuild-std \
  --target x86_64-unknown-linux-gnu \
  --test integration
```

### ThreadSanitizer (TSan)

Обнаруживает гонки данных в многопоточном коде.  
Также требует `-Zbuild-std`.

```bash
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly test \
  -Zbuild-std \
  --target x86_64-unknown-linux-gnu \
  --test integration
```

> ASan и TSan не поддерживаются на `x86_64-pc-windows-msvc`.
> Запускайте через Docker или в CI (см. раздел [GitHub Actions](#github-actions)).

---

## Docker

Образ содержит всё необходимое для Linux-инструментов:

| Инструмент | Назначение |
|---|---|
| `valgrind` | утечки памяти, Massif |
| `linux-perf` | сэмплирование CPU для flamegraph |
| `cargo-flamegraph` | генерация SVG flamegraph |
| `nightly` + `rust-src` | ASan / TSan через `-Zbuild-std` |

### Сборка образа

```powershell
docker build -t broken-app-profile .
```

### Запуск Valgrind вручную

```powershell
docker run --rm broken-app-profile
```

### Запуск с привилегиями (для perf)

```powershell
docker run --rm --privileged broken-app-profile bash -c `
  "echo -1 > /proc/sys/kernel/perf_event_paranoid && cargo flamegraph --bin demo"
```

### Именованный том для артефактов

Файлы, созданные внутри `--rm`-контейнера, теряются после остановки.
Скрипты используют именованный том `broken-app-profile-vol` и паттерн
`docker create` + `docker cp` для извлечения файлов:

```powershell
$ctr = docker create -v broken-app-profile-vol:/app/target broken-app-profile true
docker cp "${ctr}:/app/target/flamegraph_slow.svg" .\artifacts\
docker rm $ctr
```

---

## Скрипты

Все скрипты запускаются из директории `broken-app/`.

### `scripts\profile.ps1` — профилирование (Windows PowerShell)

Запускает flamegraph и massif для одного или обоих вариантов внутри Docker.

```powershell
.\scripts\profile.ps1                    # оба варианта (по умолчанию)
.\scripts\profile.ps1 -Variant slow
.\scripts\profile.ps1 -Variant optimized
```

Шаги для каждого варианта:
1. `docker build` — сборка образа (один раз)
2. `cargo build --release [--features optimized]` — компиляция в именованный том
3. `cargo flamegraph` — CPU-профиль → `flamegraph_<variant>.svg`
4. `valgrind --tool=massif` + `ms_print` → `massif_<variant>.out` + `.txt`
5. `docker create` + `docker cp` — извлечение артефактов в `artifacts\`

### `scripts\compare.ps1` — сравнение бенчмарков (Windows PowerShell)

```powershell
.\scripts\compare.ps1                    # оба варианта + таблица сравнения
.\scripts\compare.ps1 -Variant slow
.\scripts\compare.ps1 -Variant optimized
```

Сохраняет `artifacts\baseline_slow.txt` и `artifacts\baseline_optimized.txt`,
затем выводит их рядом для визуального сравнения.

### `scripts/profile.sh` — профилирование (Bash / WSL)

```bash
bash scripts/profile.sh          # оба варианта
bash scripts/profile.sh slow
bash scripts/profile.sh optimized
```

### `scripts/compare.sh` — сравнение бенчмарков (Bash / WSL)

```bash
bash scripts/compare.sh               # оба варианта (по умолчанию)
bash scripts/compare.sh slow
bash scripts/compare.sh optimized
```

### Политика выполнения PowerShell

Если скрипты блокируются:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## GitHub Actions

Файл: `.github/workflows/rust.yml`  
Триггер: push и pull request в ветку `master`.

### Общая схема CI/CD

```
push / PR → master
  │
  ├─ fmt              ── cargo fmt --check
  │
  ├─ build (slow)     ── build → clippy → test → Step Summary
  ├─ build (optimized)── build → clippy → test → Step Summary
  │
  ├─ miri (slow)      ── unit tests + integration tests (интерпретатор)
  ├─ miri (optimized) ── unit tests + integration tests (интерпретатор)
  │
  ├─ valgrind (slow)      ── demo под Valgrind (утечки)
  ├─ valgrind (optimized) ── demo под Valgrind (утечки)
  │
  ├─ sanitizer-address (slow)      ── ASan: тесты + demo
  ├─ sanitizer-address (optimized) ── ASan: тесты + demo
  ├─ sanitizer-thread  (slow)      ── TSan: тесты + demo
  ├─ sanitizer-thread  (optimized) ── TSan: тесты + demo
  │
  └─ profiling ── flamegraph + massif + baseline bench
                   для slow и optimized → отчёт + артефакты
```

Все задания выполняются **параллельно** друг другу. Внутри заданий с матрицей
используется `fail-fast: false` — провал одного варианта не отменяет остальные.

### Кэширование

Все задания кроме `fmt` используют [`Swatinem/rust-cache@v2`](https://github.com/Swatinem/rust-cache)
для кэширования `~/.cargo` и `target/`, что значительно ускоряет повторные прогоны.
`fmt` не нуждается в кэше, так как проверка форматирования не требует компиляции.

### Задания (jobs)

#### `fmt` — проверка форматирования

```bash
cargo fmt --all -- --check
```

Проверяет, что весь код отформатирован согласно `rustfmt`. Не модифицирует файлы —
только проверяет и завершается с ошибкой, если есть отклонения.

#### `build` — сборка, Clippy, тесты

Матрица: `["", "optimized"]` — запускается дважды (slow / optimized).

```bash
cargo build --verbose --workspace [--features optimized]
cargo clippy --workspace --all-targets -- -D warnings
cargo test --verbose --workspace
```

- Clippy настроен с `-D warnings` — любое предупреждение считается ошибкой.
- Step Summary содержит отчёт: статус сборки, количество предупреждений Clippy,
  результаты тестов.

#### `miri` — интерпретатор с проверкой UB

Матрица: `["", "optimized"]`.

```bash
cargo miri test --package broken-app --lib [--features optimized]
cargo miri test --package broken-app --test integration [--features optimized]
```

Выполняет юнит-тесты и интеграционные тесты под интерпретатором Miri.
Обнаруживает use-after-free, выход за границы, нарушения инвариантов типов.

#### `valgrind` — утечки памяти

Матрица: `["", "optimized"]`.

```bash
cargo build --package broken-app --bin demo
valgrind --leak-check=full --error-exitcode=1 ./target/debug/demo
```

Запускает debug-бинарник `demo` под Valgrind. Код возврата 1 при обнаружении утечек.

#### `sanitizers` — матрица ASan / TSan

Двойная матрица: `sanitizer × features` (4 конфигурации).

```yaml
strategy:
  fail-fast: false
  matrix:
    sanitizer: [address, thread]
    features: ["", "optimized"]
```

Каждая конфигурация запускает интеграционные тесты и бинарник `demo`
с соответствующим санитайзером через `-Zbuild-std`:

```bash
RUSTFLAGS="-Zsanitizer=address" cargo +nightly test \
  -Zbuild-std --target x86_64-unknown-linux-gnu \
  --package broken-app --test integration
```

| Санитайзер | Что обнаруживает |
|---|---|
| AddressSanitizer | heap/stack buffer overflow, use-after-free, double-free |
| ThreadSanitizer | гонки данных в многопоточном коде |

#### `profiling` — flamegraph + massif + baseline bench

Отдельное задание **без матрицы** — обе конфигурации выполняются последовательно
в одном задании, чтобы в конце сформировать сравнительный отчёт.

**Подготовка:**

```bash
sudo apt-get install -y valgrind linux-perf
sudo sysctl kernel.perf_event_paranoid=-1
sudo sysctl kernel.kptr_restrict=0
cargo install flamegraph
```

**Для каждого варианта (slow, optimized):**

1. `cargo build --release --package broken-app --bin demo [--features optimized]`
2. `cargo flamegraph --release --bin demo -o flamegraph_<variant>.svg` — CPU-профиль
3. `valgrind --tool=massif` + `ms_print` — профиль кучи
4. `cargo bench --bench baseline` — замер времени

**Отчёт в Step Summary** содержит:

- Таблицу baseline-бенчмарков: `sum_even`, `slow_fib`, `slow_dedup` (slow vs optimized)
- Пиковое потребление кучи (Massif) по вариантам
- Топ-5 мест аллокаций для каждого варианта
- Ссылку на скачивание SVG-flamegraph из вкладки Artifacts

**Артефакты** (хранятся 30 дней):

| Файл | Описание |
|---|---|
| `flamegraph_slow.svg` | CPU flamegraph, slow-вариант |
| `flamegraph_optimized.svg` | CPU flamegraph, optimized-вариант |
| `massif_slow.txt` / `.out` | Massif-отчёт, slow-вариант |
| `massif_optimized.txt` / `.out` | Massif-отчёт, optimized-вариант |
| `baseline_slow.txt` | baseline-бенчмарк, slow-вариант |
| `baseline_optimized.txt` | baseline-бенчмарк, optimized-вариант |

### Сводная таблица заданий

| Job | Что проверяет | Матрица |
|---|---|---|
| `fmt` | форматирование кода (`rustfmt`) | — |
| `build` | компиляция, Clippy, юнит + интеграционные тесты | slow / optimized |
| `miri` | UB, некорректная работа с памятью (интерпретатор) | slow / optimized |
| `valgrind` | утечки памяти в debug-бинарнике | slow / optimized |
| `sanitizers` | ASan: buffer overflow, use-after-free; TSan: гонки данных | (address, thread) × (slow, optimized) |
| `profiling` | CPU-профиль (flamegraph), кучи (massif), baseline bench | — (оба варианта последовательно) |

---

## Артефакты

Директория `artifacts/` содержит сохранённые результаты:

| Файл | Описание |
|---|---|
| `flamegraph_slow.svg` | CPU flamegraph, slow-вариант |
| `flamegraph_optimized.svg` | CPU flamegraph, optimized-вариант |
| `flamegraph_before.svg` | CPU flamegraph до оптимизаций (исходный) |
| `massif_slow.out` / `.txt` | Valgrind Massif, slow-вариант |
| `massif_optimized.out` / `.txt` | Valgrind Massif, optimized-вариант |
| `massif_before.out` | Valgrind Massif до оптимизаций (исходный) |
| `baseline_slow.txt` | baseline-бенчмарк, slow-вариант |
| `baseline_optimized.txt` | baseline-бенчмарк, optimized-вариант |
| `baseline_before.txt` | baseline-бенчмарк до оптимизаций (исходный) |
| `criterion_before.txt` | Criterion-бенчмарк до оптимизаций (исходный) |
| `logs/001-log-*.log` … `015-log-*.log` | логи диагностики до и после исправлений |

Flamegraph открывается в браузере:

```powershell
start artifacts\flamegraph_slow.svg
```
