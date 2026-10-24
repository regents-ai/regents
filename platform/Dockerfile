# gcc:15.2.0-bookworm
FROM docker.io/library/gcc@sha256:9ca91b05c7b07d2979f16413e8b2cd6ec8a7c80ffca4121ccab0aeba33f90460 AS native
# hexpm/elixir:1.20.4-erlang-29.1.2-debian-bookworm-20261020-slim
FROM docker.io/hexpm/elixir@sha256:11ab449084960993491cdc3493be292464c5a63e8f753ed2afe351486471b69a AS elixir
# node:26.12.0-bookworm-slim
FROM docker.io/library/node@sha256:298992629d69bbd5b2b03ad57094d8e4fcb3a8eeb7c4e25d29de656519568913 AS node
# debian:bookworm-20261020-slim
FROM docker.io/library/debian@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8 AS slim

FROM native AS assets

ENV npm_config_nodedir=/usr/local
WORKDIR /workspace/platform
COPY --from=node /usr/local /usr/local
COPY platform/package.json platform/package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund

FROM native AS build

ENV MIX_ENV=prod
ENV HOME=/root
WORKDIR /workspace/platform

COPY --from=elixir /usr/local /usr/local
COPY --from=assets /usr/local/bin/node /usr/local/bin/node
COPY --from=assets /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

# Hex and rebar3 at fixed versions; rebar3 is the build Mix itself would pick
# for this Elixir and OTP, checked against its published SHA-512.
RUN mix local.hex 2.5.1 --force && \
  mix local.rebar rebar3 https://builds.hex.pm/installs/1.18.4/rebar3-3.25.1-otp-28 \
    --sha512 992fd755b7926fae455e5e07d9d195f4d3e7f181609eed1b9cabfe548624df10d148cd4b59bda40bebb185d3d68f9a9fd68a70b294101c8ad9cf0fadcc683d24 \
    --force

# Shared Regent libraries arrive here from GitHub at the commits mix.lock pins;
# a mix.lock that no longer matches mix.exs stops the build.
COPY platform/mix.exs platform/mix.lock ./
COPY identity /workspace/identity
RUN mix deps.get --only prod --check-locked
COPY platform/config config
RUN mix deps.compile

COPY platform/lib lib
COPY blog /workspace/blog
COPY platform/priv priv
COPY platform/rel rel
COPY platform/assets assets
COPY platform/contracts contracts
COPY --from=assets /workspace/platform/node_modules node_modules
RUN mix compile && mix assets.deploy && mix release

# The release carries its own ERTS, so the runtime image needs no Elixir and no
# Erlang install. It does still need the OpenSSL library the crypto NIF links
# against, which the slim base lacks. It is lifted from the builder image, which
# is only sound while the two images are the same Debian release, so this stage
# asserts that first and the build stops here if a base ever moves. Lifting to a
# fixed path also keeps the runtime stage from naming a library directory that
# differs per architecture. Outbound TLS needs no CA bundle from the image: the
# release trusts castore's list (`Regents.Application`).
FROM elixir AS runtime-support

COPY --from=slim /etc/os-release /slim-os-release
RUN set -eu; \
  builder="$(. /etc/os-release; printf '%s' "$VERSION_CODENAME")"; \
  runtime="$(. /slim-os-release; printf '%s' "$VERSION_CODENAME")"; \
  if [ "$builder" != "$runtime" ]; then \
    echo "runtime base is Debian $runtime but the builder is Debian $builder;" \
      "the OpenSSL library may not be lifted across releases" >&2; \
    exit 1; \
  fi; \
  mkdir /runtime-support; \
  cp /usr/lib/*-linux-gnu/libcrypto.so.3 /runtime-support/

FROM slim AS app

# The builder image sets this and the slim base does not. Without it the VM
# runs with latin1 name encoding, which Elixir warns about at boot.
ENV LANG=C.UTF-8
ENV HOME=/app
WORKDIR /app

COPY --from=runtime-support /runtime-support/libcrypto.so.3 /usr/lib/

# OTP 29 opens libsctp when it starts and prints a warning on every boot and
# `bin/regents rpc` without it (Techtree fadc820d).
RUN apt-get update \
  && apt-get install -y --no-install-recommends libsctp1 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 1001 app \
  && useradd --system --uid 1001 --gid app --home-dir /app app

COPY --from=build --chown=app:app /workspace/platform/_build/prod/rel/regents ./

# The commit this image is built from. scripts/deploy.sh passes it; a build
# without it stops here.
ARG SOURCE_COMMIT
RUN test -n "$SOURCE_COMMIT"
ENV SOURCE_COMMIT=$SOURCE_COMMIT

USER app

EXPOSE 4000

CMD ["/app/bin/regents", "start"]
