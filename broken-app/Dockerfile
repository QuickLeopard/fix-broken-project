FROM rust:latest

WORKDIR /app
RUN apt-get update && apt-get install -y valgrind && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY benches ./benches
RUN cargo build
CMD ["valgrind", "--leak-check=full", "--error-exitcode=1", "./target/debug/demo"]
