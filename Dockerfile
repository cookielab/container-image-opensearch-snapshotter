FROM cookielab/slim:12.0 AS build

ARG TARGETARCH

COPY ./scripts/opensearch_snapshotter.sh /usr/local/bin/opensearch_snapshotter.sh

FROM cookielab/slim:12.0

RUN apt update && apt install -y curl jq bash

COPY --from=build /usr/local/bin /usr/local/bin

USER 1987

ONBUILD USER root
