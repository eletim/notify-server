FROM alpine:3.22 AS source
RUN apk add --no-cache git python3
WORKDIR /src
RUN git init && git remote add origin https://github.com/binwiederhier/ntfy.git && git fetch --depth 1 origin 4c2b69e0591b51d7ed7b2e71954f0f7be936b47f && git checkout FETCH_HEAD
COPY build/patch-subpath.py /patch-subpath.py
ARG NTFY_BASE_PATH=/ntfy/
RUN NTFY_BASE_PATH="$NTFY_BASE_PATH" python3 /patch-subpath.py
FROM node:24-alpine AS web
WORKDIR /src
COPY --from=source /src/web/package*.json ./web/
RUN cd web && npm ci
COPY --from=source /src/web ./web
RUN cd web && npm run build && mv build/index.html build/app.html && rm build/config.js
FROM golang:1.26-alpine AS binary
RUN apk add --no-cache gcc musl-dev
WORKDIR /src
COPY --from=source /src .
COPY --from=web /src/web/build ./server/site
ENV GOMAXPROCS=2
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build mkdir -p server/docs && touch server/docs/index.html && go build -p 2 -tags sqlite_omit_load_extension,osusergo,netgo -ldflags '-s -w -X main.version=2.27.0-subpath' -o /ntfy .
FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
COPY --from=binary /ntfy /usr/bin/ntfy
ENTRYPOINT ["ntfy"]
