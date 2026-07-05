# syntax=docker/dockerfile:1.4

############################################################################
# Bookworm image for NWM Verification
#
# Uses the official Python 3.11 Bookworm image rather than building Python
# from source. Python 3.11 is currently required because the pinned TEEHR
# dependency restricts DuckDB to an older release that does not provide a
# compatible Python 3.12 wheel.
############################################################################

ARG BASE_IMAGE=python:3.11-slim-bookworm

FROM ${BASE_IMAGE}

# OCI metadata arguments
ARG BASE_IMAGE
ARG BASE_IMAGE_NAME="${BASE_IMAGE}"
ARG BASE_IMAGE_DIGEST="unknown"
ARG BASE_REVISION="unknown"
ARG IMAGE_SOURCE="unknown"
ARG IMAGE_VENDOR="unknown"
ARG IMAGE_VERSION="unknown"
ARG IMAGE_REVISION="unknown"
ARG IMAGE_CREATED="unknown"

# OCI standard labels
LABEL org.opencontainers.image.base.name="${BASE_IMAGE_NAME}" \
      org.opencontainers.image.base.digest="${BASE_IMAGE_DIGEST}" \
      io.ngwpc.image.base.revision="${BASE_REVISION}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.vendor="${IMAGE_VENDOR}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.title="NWM Verification" \
      org.opencontainers.image.description="Docker image for the NWM verification application"

ENV LANG="C.UTF-8" \
    PATH="/usr/local/bin:${PATH}"

############################################################################
# System dependencies
############################################################################

RUN --mount=type=cache,target=/var/cache/apt,id=apt-cache-bookworm,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,id=apt-lib-bookworm,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        bzip2 \
        ca-certificates \
        cmake \
        curl \
        file \
        findutils \
        git \
        jq \
        libbz2-dev \
        libcurl4-openssl-dev \
        libffi-dev \
        libssl-dev \
        libsqlite3-dev \
        m4 \
        rsync \
        tk-dev \
        uuid-dev \
        xz-utils \
        zlib1g-dev; \
    rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-c"]

############################################################################
# Shared Python virtual environment
############################################################################

# Install all Python packages into a dedicated virtual environment rather than
# modifying the Python installation supplied by the base image.
ENV VIRTUAL_ENV="/ngen-app/nwm-verf-python" \
    PATH="${VIRTUAL_ENV}/bin:${PATH}"

RUN set -eux; \
    mkdir -p /ngen-app; \
    python -m venv "${VIRTUAL_ENV}"

# Install current Python packaging and PEP 517 build tools before installing
# packages from Git or building the local nwm-verf project.
RUN --mount=type=cache,target=/root/.cache/pip,id=pip-cache-bookworm \
    set -eux; \
    python -m pip install --upgrade \
        pip \
        setuptools \
        wheel \
        build \
        pyproject_hooks \
        packaging

############################################################################
# NWM Evaluation Manager
############################################################################

ARG NWM_EVAL_MGR_REF=development

# Install nwm-eval-mgr separately so this layer remains cached when only the
# local nwm-verf source changes.
RUN --mount=type=cache,target=/root/.cache/pip,id=pip-cache-bookworm \
    set -eux; \
    python -m pip install \
        "git+https://github.com/NGWPC/nwm-eval-mgr.git@${NWM_EVAL_MGR_REF}"

############################################################################
# NWM Verification
############################################################################

COPY . /ngen-app/nwm-verf/

WORKDIR /ngen-app/nwm-verf/

RUN --mount=type=cache,target=/root/.cache/pip,id=pip-cache-bookworm \
    set -eux; \
    python -m pip install .; \
    python -m pip check

COPY --chmod=0755 ./docker/run-nwm-verf.sh /ngen-app/bin/run-nwm-verf.sh

############################################################################
# Git build information
############################################################################

ARG CI_COMMIT_REF_NAME

RUN set -eux; \
    # Ensure local tag metadata includes all remote tags before creating git_info.
    git fetch --force --tags origin '+refs/tags/*:refs/tags/*' && \
    repo_url="$(git config --get remote.origin.url)"; \
    key="${repo_url##*/}"; \
    key="${key%.git}"; \
    GIT_INFO_PATH="/ngen-app/${key}_git_info.json"; \
    branch="$([ -n "${CI_COMMIT_REF_NAME:-}" ] && echo "${CI_COMMIT_REF_NAME}" || git rev-parse --abbrev-ref HEAD)"; \
    jq -n \
        --arg commit_hash "$(git rev-parse HEAD)" \
        --arg branch "${branch}" \
        --arg tags "$(git tag --points-at HEAD | tr '\n' ' ')" \
        --arg author "$(git log -1 --pretty=format:'%an')" \
        --arg commit_date "$(date -u -d @"$(git log -1 --pretty=format:'%ct')" +'%Y-%m-%d %H:%M:%S UTC')" \
        --arg message "$(git log -1 --pretty=format:'%s' | tr '\n' ';')" \
        --arg build_date "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" \
        "{\"${key}\": {commit_hash: \$commit_hash, branch: \$branch, tags: \$tags, author: \$author, commit_date: \$commit_date, message: \$message, build_date: \$build_date}}" \
        > "${GIT_INFO_PATH}"

WORKDIR /

ENTRYPOINT ["/ngen-app/bin/run-nwm-verf.sh"]
CMD ["--help"]
