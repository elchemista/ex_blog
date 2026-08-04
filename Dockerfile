# syntax=docker/dockerfile:1

# Keep every native build and the final release on the same Debian generation.
# TDLib, Ortex, and the release then share one glibc/OpenSSL ABI.
ARG ELIXIR_IMAGE="hexpm/elixir:1.20.2-erlang-29.0.4-debian-bookworm-20260713-slim"
ARG DEBIAN_IMAGE="debian:bookworm-20260713-slim"
ARG RUST_IMAGE="rust:1.93.1-slim-bookworm"

# ExGram v0.2.0 builds tdlib-json-cli v1.8.0 explicitly. Pin the resolved
# commit so a production rebuild cannot silently pick up a moved tag.
ARG TDLIB_JSON_CLI_REPOSITORY="https://github.com/oott123/tdlib-json-cli.git"
ARG TDLIB_JSON_CLI_REF="e8f4e684ef366a409cab6d7770ccece75a3aefd1"
ARG TDLIB_BUILD_JOBS="2"

# Reuse the immutable Bookworm artifact already published by Freelance. Set
# TDLIB_IMAGE=tdlib-artifact only when deliberately rebuilding TDLib here.
ARG TDLIB_IMAGE="registry.fly.io/freelance:tdlib-bookworm-b876ee4dcfba@sha256:1f99be7652facf5e6c4492644f7b734f50c255837a25115df657cd4169721393"
ARG LIGHTPANDA_CHANNEL="nightly"


FROM ${DEBIAN_IMAGE} AS tdlib-build

ARG TDLIB_JSON_CLI_REPOSITORY
ARG TDLIB_JSON_CLI_REF
ARG TDLIB_BUILD_JOBS

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      cmake \
      git \
      gperf \
      libssl-dev \
      pkg-config \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/tdlib-json-cli

RUN git init . \
    && git remote add origin "${TDLIB_JSON_CLI_REPOSITORY}" \
    && git fetch --depth 1 origin "${TDLIB_JSON_CLI_REF}" \
    && git checkout --detach FETCH_HEAD \
    && git submodule update --init --recursive --depth 1

# The upstream wrapper forces a fully static OpenSSL link. Match ExGram's
# reviewed build patch and link against the Bookworm runtime libraries instead.
RUN sed -i \
      -e 's|set(CMAKE_EXE_LINKER_FLAGS " -static")|# ExGram patch: disabled forced static link|' \
      -e 's|target_link_libraries(tdlib_json_cli Td::TdJsonStatic -static-libgcc -static-libstdc++)|target_link_libraries(tdlib_json_cli Td::TdJsonStatic)|' \
      CMakeLists.txt \
    && cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    && cmake --build build --parallel "${TDLIB_BUILD_JOBS}" \
    && install -Dm0755 build/bin/tdlib_json_cli /opt/tdlib/tdlib-json-cli


# This target can optionally be published once and reused through TDLIB_IMAGE.
FROM ${DEBIAN_IMAGE} AS tdlib-artifact

ARG TDLIB_JSON_CLI_REPOSITORY
ARG TDLIB_JSON_CLI_REF

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      libssl3 \
      libstdc++6 \
      zlib1g \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/tdlib
COPY --from=tdlib-build --chmod=0755 /opt/tdlib/tdlib-json-cli ./tdlib-json-cli

RUN ldd ./tdlib-json-cli \
    && ! ldd ./tdlib-json-cli | grep -q "not found"

LABEL org.opencontainers.image.source="${TDLIB_JSON_CLI_REPOSITORY}" \
      org.opencontainers.image.revision="${TDLIB_JSON_CLI_REF}"


FROM ${TDLIB_IMAGE} AS tdlib


# Spectre Kinetic's Ortex dependency compiles a Rust NIF. The Rust toolchain
# remains in build stages and is never copied into the runtime image.
FROM ${RUST_IMAGE} AS rust-toolchain


FROM ${ELIXIR_IMAGE} AS dependencies

ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
ENV PATH=/usr/local/cargo/bin:${PATH}
ENV CC=/usr/bin/clang
ENV CXX=/usr/bin/clang++
ENV MIX_ENV=prod
ENV MIX_OS_DEPS_COMPILE_PARTITION_COUNT=2

COPY --from=rust-toolchain /usr/local/cargo /usr/local/cargo
COPY --from=rust-toolchain /usr/local/rustup /usr/local/rustup

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      clang \
      git \
      openssh-client \
      pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN mix local.hex --force \
    && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

# Git dependencies are public today, but build-time authentication remains
# available for private forks. Prefer the `github_token` BuildKit secret; an
# SSH agent is also supported for local builds. Neither credential is copied
# into a layer or the final image.
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=secret,id=github_token \
    --mount=type=ssh \
    set -eu; \
    askpass=/tmp/ex-blog-github-askpass; \
    if [ -s /run/secrets/github_token ]; then \
      printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '  *Username*) printf "%s\\n" "x-access-token" ;;' \
        '  *) cat /run/secrets/github_token ;;' \
        'esac' > "${askpass}"; \
      chmod 0700 "${askpass}"; \
      GIT_ASKPASS="${askpass}" GIT_TERMINAL_PROMPT=0 mix deps.get --only prod; \
      rm -f "${askpass}"; \
    elif [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK}" ]; then \
      install -d -m 0700 /root/.ssh; \
      ssh-keyscan -t ed25519 github.com > /root/.ssh/known_hosts; \
      git config --global url."git@github.com:".insteadOf "https://github.com/"; \
      mix deps.get --only prod; \
      git config --global --unset-all url."git@github.com:".insteadOf; \
      rm -rf /root/.ssh; \
    else \
      GIT_TERMINAL_PROMPT=0 mix deps.get --only prod; \
    fi

# Normal ExGram compilation intentionally does not build TDLib. Install the
# reviewed binary before compiling dependencies so Mix carries it into the
# dependency's priv directory and, later, into the OTP release.
COPY --from=tdlib --chmod=0755 \
  /opt/tdlib/tdlib-json-cli \
  /build/deps/ex_gram/priv/tdlib-json-cli

RUN test -x deps/ex_gram/priv/tdlib-json-cli

RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    mix deps.compile


# Keep the 150+ MB browser download independent from ordinary application
# source edits. Spectre Lens resolves and checksum-verifies the selected asset.
FROM dependencies AS lightpanda

ARG LIGHTPANDA_CHANNEL

RUN mkdir -p /build/bin \
    && set -- \
    && for ebin in _build/prod/lib/*/ebin; do set -- "$@" -pa "${ebin}"; done \
    && LIGHTPANDA_CHANNEL="${LIGHTPANDA_CHANNEL}" \
      elixir "$@" -e \
      'Application.ensure_all_started(:req); channel = System.fetch_env!("LIGHTPANDA_CHANNEL"); {:ok, _path} = SpectreLens.Lightpanda.install(out: "/build/bin", channel: channel, force: true)'

RUN test -x /build/bin/lightpanda \
    && /build/bin/lightpanda version


FROM dependencies AS builder

COPY priv priv
COPY lib lib
COPY assets assets
COPY rel rel

RUN mix compile --warnings-as-errors

# Validate all 456 versioned routing examples before assembling the release.
# The assertion after `mix release` also proves that the exact source bytes were
# copied into the application priv directory rather than relying on cwd paths.
RUN mix ex_blog.spectre.dataset.build --check
RUN mix assets.deploy
RUN mix release

RUN release_root="_build/prod/rel/ex_blog" \
    && dataset_path="$(find "${release_root}/lib" -path '*/ex_blog-*/priv/spectre/dataset.json' -type f -print -quit)" \
    && tdlib_path="$(find "${release_root}/lib" -path '*/ex_gram-*/priv/tdlib-json-cli' -type f -print -quit)" \
    && test -n "${dataset_path}" \
    && test -n "${tdlib_path}" \
    && cmp priv/spectre/dataset.json "${dataset_path}" \
    && test -x "${tdlib_path}" \
    && test -x "${release_root}/bin/server"


FROM ${DEBIAN_IMAGE} AS runner

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      gosu \
      libatomic1 \
      libcap2 \
      libncurses6 \
      libsctp1 \
      libssl3 \
      libstdc++6 \
      locales \
      zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && groupadd --system exblog \
    && useradd --system --gid exblog --home-dir /app --shell /usr/sbin/nologin exblog

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV SHELL=/bin/sh
ENV PHX_SERVER=true
ENV EX_BLOG_DATA_DIR=/data
ENV LIGHTPANDA_PATH=/usr/local/bin/lightpanda
ENV LIGHTPANDA_DISABLE_TELEMETRY=true

WORKDIR /app

RUN mkdir -p /data \
    && chown exblog:exblog /data

COPY --from=builder --chown=exblog:exblog /build/_build/prod/rel/ex_blog ./

# Spectre renders these files by prompt_root at runtime; compiled BEAM files do
# not contain them, so a release-only copy would make agent actions fail.
COPY --from=builder --chown=exblog:exblog \
  /build/lib/ex_blog_web/prompts \
  ./lib/ex_blog_web/prompts

COPY --from=lightpanda --chown=root:root --chmod=0755 \
  /build/bin/lightpanda \
  /usr/local/bin/lightpanda

COPY --chown=root:root --chmod=0755 \
  rel/overlays/bin/docker-entrypoint \
  /usr/local/bin/ex-blog-entrypoint

ENTRYPOINT ["/usr/local/bin/ex-blog-entrypoint"]
CMD ["/app/bin/server"]
