FROM rust:latest

RUN rustup toolchain install nightly \
    && rustup component add rust-src --toolchain nightly

WORKDIR /app
RUN apt-get update && apt-get install -y valgrind linux-perf heaptrack && rm -rf /var/lib/apt/lists/*
RUN cargo install flamegraph
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY benches ./benches
COPY tests ./tests
RUN cargo fetch
RUN RUSTFLAGS="-Zsanitizer=address" cargo +nightly fetch \
    --target x86_64-unknown-linux-gnu
RUN cargo build
CMD ["valgrind", "--leak-check=full", "--error-exitcode=1", "./target/debug/demo"]
