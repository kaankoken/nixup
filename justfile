default: lint

build:
    cargo build --workspace

check:
    cargo check --workspace --all-targets

clippy:
    cargo clippy --workspace --all-targets

lint: clippy

fmt:
    cargo fmt --all
    taplo fmt

test:
    cargo nextest run --workspace
