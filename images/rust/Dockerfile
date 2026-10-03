# Rust's stable toolchain via rustup, and the C toolchain it links with. The
# Rust toolchain lives in the image; cargo's registry cache and `cargo
# install`ed tools go to ~/.cargo in the home.
ARG BASE=clod
FROM $BASE
USER root
RUN apt-get install -y build-essential
RUN mkdir /usr/local/rustup /usr/local/cargo \
    && chown claude:claude /usr/local/rustup /usr/local/cargo
USER claude
ENV RUSTUP_HOME=/usr/local/rustup
RUN curl --proto '=https' -fsSL https://sh.rustup.rs \
    | CARGO_HOME=/usr/local/cargo sh -s -- -y --no-modify-path
ENV CARGO_HOME=/home/claude/.cargo
ENV PATH="/usr/local/cargo/bin:/home/claude/.cargo/bin:$PATH"
