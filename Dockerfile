#
# NSZ Dockerfile
#
# https://github.com/nicoboss/nsz
#

FROM python:3.11-alpine as builder

# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.1.5.0"
ARG S6_OVERLAY_ARCH="x86_64"

# Set NSZ vars
ARG NSZ_VERSION

# Install build deps and install python dependencies
RUN \
  set -ex && \
  echo "Installing build dependencies..." && \
    apk add --no-cache \
      git \
      bash \
      curl \
      jq \
      gcc \
      musl-dev
      
# Check last NSZ version if variable is undefined
RUN \
  echo "Obtaining NSZ version..." && \
    if [ -z ${NSZ_VERSION+x} ]; then \
      NSZ_VERSION=$(curl -sX GET https://api.github.com/repos/nicoboss/nsz/tags \
        | jq -r "first(.[] | .name)"); \
    fi && \
    echo "NSZ version: ${NSZ_VERSION}" && \
    mkdir -p /app && \
    curl -o \
      /tmp/nsz.tar.gz -L \
      "https://github.com/nicoboss/nsz/archive/refs/tags/${NSZ_VERSION}.tar.gz" && \
    tar xzf \
      /tmp/nsz.tar.gz -C \
      /app --strip-components=1

# Download S6 Overlay
RUN mkdir -p /root-out
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz

# Download NUT
RUN mkdir -p /app

# Change working dir
WORKDIR /app

# Build venv
RUN \
  set -ex && \
  echo "Upgrading pip..." && \
    pip3 install --upgrade pip && \
    pip3 install --upgrade setuptools && \
  echo "Setup venv..." && \
    pip3 install virtualenv && \
    python3 -m venv venv && \
    source venv/bin/activate && \
  echo "Building wheels for requirements..." && \
    pip3 install -r requirements.txt && \
  echo "Cleaning up directories..." && \
    rm -rf .github dev nsz/gui && \
    rm -f .gitignore nsz.pyproj nsz.sln requirements-gui.txt *.md

# Setup nsz image
FROM python:3.11-alpine

ENV PATH="/nsz/venv/bin:$PATH"

COPY --chown=1000 --from=builder /app /app
COPY --from=builder /root-out /
COPY /conf /conf

# Install build deps and install python dependencies
RUN \
  set -ex && \
  echo "Installing build dependencies..." && \
    apk add --no-cache \
      bash \
      curl \
      shadow \
      jq && \
  echo "Creating nsz user and make our folders..." && \
    groupmod -g 1000 users && \
    useradd -u 911 -U -d /conf -s /bin/false nsz && \
    usermod -G users nsz && \
  echo "Making our folders..." && \
    mkdir -p \
      /conf \
      /titles \
      /output && \
    echo "Cleanup..." && \
      rm -rf /tmp/*

# Add files
COPY rootfs/ /

# Define mountable directories
VOLUME ["/conf", "/titles", "/output"]

# Start s6
ENTRYPOINT ["/init"]
