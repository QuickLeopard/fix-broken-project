# fix-broken-project

Rust workspace: учебный проект по отладке, профилированию и анализу памяти.

## Crates

| Crate | Описание |
|-------|----------|
| **broken-app** | Основное приложение: исправленные функции, бенчмарки, профилирование (flamegraph, massif), CI/CD |
| **reference-app** | Эталонная реализация для сравнения |

## Документация

Подробное описание структуры, тестов, бенчмарков, профилирования, Docker и CI/CD:

**[→ README в broken-app](broken-app/README.md)**

## Быстрый старт

```bash
cargo build --workspace
cargo test --workspace
cargo bench --package broken-app --bench baseline
```
