FROM caddy:2.9-alpine

ARG CADDYFILE
COPY ${CADDYFILE} /etc/caddy/Caddyfile

RUN caddy validate --config /etc/caddy/Caddyfile

EXPOSE 8080
