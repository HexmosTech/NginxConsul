ARG UBUNTU_VERSION=22.04
FROM golang:1.26-bookworm AS go

FROM ubuntu:${UBUNTU_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      libpcre3-dev \
      zlib1g-dev \
      libssl-dev \
      ca-certificates \
      curl \
      git \
      make \
      patch \
      tar \
 && rm -rf /var/lib/apt/lists/*

COPY --from=go /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

WORKDIR /src
COPY . /src
RUN ./build.sh --ci

# Artifacts are in /src/dist.
