FROM rust:1.88.0-bookworm

RUN rustup toolchain install nightly \
    && rustup component add rust-src --toolchain nightly

WORKDIR /app

RUN apt-get update && apt-get install -y \
        valgrind \
        linux-perf \
        heaptrack \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf "$(ls /usr/bin/perf_* 2>/dev/null | head -1)" /usr/local/bin/perf || true

RUN cargo install flamegraph --locked

COPY Cargo.toml Cargo.lock ./
COPY src     ./src
COPY benches ./benches
COPY tests   ./tests

RUN cargo fetch
RUN cargo +nightly fetch --target x86_64-unknown-linux-gnu

RUN cargo build

CMD ["valgrind", "--leak-check=full", "--error-exitcode=1", "./target/debug/demo"]
