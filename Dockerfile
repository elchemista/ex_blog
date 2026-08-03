ARG ELIXIR_IMAGE="hexpm/elixir:1.20.2-erlang-29.0.4-debian-bookworm-20260713-slim"
ARG DEBIAN_IMAGE="debian:bookworm-20260713-slim"

FROM ${ELIXIR_IMAGE} AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix run --no-start -e 'Application.ensure_all_started(:req); {:ok, _path} = SpectreLens.Lightpanda.install(out: "/build/bin", channel: "nightly", force: true)'
RUN mix assets.deploy
RUN mix release

FROM ${DEBIAN_IMAGE} AS runner

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      gosu \
      libcap2 \
      libncurses6 \
      libssl3 \
      libstdc++6 \
      locales \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && groupadd --system exblog \
    && useradd --system --gid exblog --home-dir /app --shell /usr/sbin/nologin exblog

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV PHX_SERVER=true
ENV EX_BLOG_DATA_DIR=/data
ENV LIGHTPANDA_PATH=/usr/local/bin/lightpanda
ENV LIGHTPANDA_DISABLE_TELEMETRY=true

WORKDIR /app
RUN mkdir -p /data && chown exblog:exblog /data

COPY --from=builder --chown=exblog:exblog /build/_build/prod/rel/ex_blog ./
COPY --from=builder --chown=root:root /build/bin/lightpanda /usr/local/bin/lightpanda
COPY --chown=root:root rel/overlays/bin/docker-entrypoint /usr/local/bin/ex-blog-entrypoint

ENTRYPOINT ["/usr/local/bin/ex-blog-entrypoint"]
CMD ["/app/bin/server"]
