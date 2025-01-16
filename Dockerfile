FROM cookielab/slim:12.9 AS build

ARG TARGETARCH

COPY ./scripts/opensearch_snapshotter.sh /usr/local/bin/opensearch_snapshotter.sh

RUN apt update && apt install -y curl jq bash

USER 1987

ONBUILD USER root
