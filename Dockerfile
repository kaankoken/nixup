# syntax=docker/dockerfile:1
# Multi-arch (amd64+arm64) static musl build of nixup with cargo-chef caching.
ARG TARGETARCH

FROM clux/muslrust:stable AS chef
USER root
RUN cargo install --locked cargo-chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder-amd64
ENV CARGO_BUILD_TARGET=x86_64-unknown-linux-musl
FROM chef AS builder-arm64
ENV CARGO_BUILD_TARGET=aarch64-unknown-linux-musl

FROM builder-${TARGETARCH} AS builder
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --target "$CARGO_BUILD_TARGET" --recipe-path recipe.json
COPY . .
RUN cargo build --release --target "$CARGO_BUILD_TARGET" --bin nixup \
 && cp "target/$CARGO_BUILD_TARGET/release/nixup" /app/nixup

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
LABEL org.opencontainers.image.source="https://github.com/kaankoken/nixup"
LABEL org.opencontainers.image.description="nixup CLI (binary-only: no Nix inside image)"
LABEL org.opencontainers.image.licenses="MIT OR Apache-2.0"
COPY --from=builder /app/nixup /usr/local/bin/nixup
ENTRYPOINT ["/usr/local/bin/nixup"]
