FROM docker.io/library/gcc@sha256:9ca91b05c7b07d2979f16413e8b2cd6ec8a7c80ffca4121ccab0aeba33f90460 AS native
FROM docker.io/hexpm/elixir@sha256:d21e3b8bab8bc2e8d51eb4bb03b1d73aad6b91c5c90b3ecc778eb5d136c2e3e6 AS elixir
FROM docker.io/library/node@sha256:5aea649bacdc35e8e20571131c4f3547477dfe66e677d45c005af6dbd1edfaa7 AS node

FROM native AS assets

ENV npm_config_nodedir=/usr/local
WORKDIR /workspace/ash-platform
COPY --from=node /usr/local /usr/local
COPY npm-cache/_cacache /root/.npm/_cacache
COPY ash-platform/package.json ash-platform/package-lock.json ./
RUN npm ci --offline --omit=dev --ignore-scripts --no-audit --no-fund

FROM native AS build

ENV MIX_ENV=prod
ENV HOME=/root
ENV RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH=/workspace/rustler-precompiled
WORKDIR /workspace/ash-platform

COPY --from=elixir /usr/local /usr/local
COPY --from=assets /usr/local/bin/node /usr/local/bin/node
COPY --from=assets /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

COPY mix-cache /root/.mix
COPY rustler-precompiled /workspace/rustler-precompiled
COPY esbuild-linux-arm64 _build/esbuild-linux-arm64
COPY ash-platform/deps deps
COPY ash-platform/mix.exs ash-platform/mix.lock ./
COPY elixir-utils/privy /workspace/elixir-utils/privy
COPY ash-platform/config config
RUN mix deps.compile

COPY ash-platform/lib lib
COPY ash-platform/priv priv
COPY ash-platform/rel rel
COPY ash-platform/assets assets
COPY ash-platform/contracts contracts
COPY --from=assets /workspace/ash-platform/node_modules node_modules
RUN mix compile && mix assets.deploy && mix release

FROM elixir AS app

ENV HOME=/app
ENV MIX_ENV=prod
WORKDIR /app

RUN groupadd --system --gid 1001 app \
  && useradd --system --uid 1001 --gid app --home-dir /app app

COPY --from=build --chown=app:app /workspace/ash-platform/_build/prod/rel/ash_platform ./

USER app

EXPOSE 4000

CMD ["/app/bin/ash_platform", "start"]
