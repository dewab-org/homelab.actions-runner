# syntax=docker/dockerfile:1.7

ARG RUNNER_IMAGE=ghcr.io/actions/actions-runner:latest

FROM debian:bookworm-slim AS hashicorp-builder

ARG PACKER_VERSION=1.14.2
ARG TERRAFORM_VERSION=1.14.6
# Vault CLI: every in-cluster workflow that reads a secret used to download
# this per job (helmfile-apply in homelab.k8s-workloads, and the image publish
# pipelines). Baking it in removes an external download from every run.
ARG VAULT_VERSION=1.17.3
# buildctl drives the in-cluster BuildKit daemon
# (homelab.k8s-workloads/buildkit). Keep this in step with that chart's
# appVersion: client and daemon are not guaranteed compatible across a wide
# version gap.
ARG BUILDKIT_VERSION=v0.35.1

COPY scripts/install-hashicorp-release.sh /usr/local/bin/install-hashicorp-release.sh

RUN chmod 0755 /usr/local/bin/install-hashicorp-release.sh \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
    && rm -rf /var/lib/apt/lists/*

RUN /usr/local/bin/install-hashicorp-release.sh packer "${PACKER_VERSION}" \
    && /usr/local/bin/install-hashicorp-release.sh terraform "${TERRAFORM_VERSION}" \
    && /usr/local/bin/install-hashicorp-release.sh vault "${VAULT_VERSION}"

# buildctl is not a HashiCorp release, so it does not go through that script.
ARG TARGETARCH
RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; \
    curl -fsSL -o /tmp/buildkit.tgz \
      "https://github.com/moby/buildkit/releases/download/${BUILDKIT_VERSION}/buildkit-${BUILDKIT_VERSION}.linux-${arch}.tar.gz"; \
    tar -xzf /tmp/buildkit.tgz -C /tmp bin/buildctl; \
    install -m 0755 /tmp/bin/buildctl /usr/local/bin/buildctl; \
    rm -rf /tmp/buildkit.tgz /tmp/bin; \
    /usr/local/bin/buildctl --version

FROM ${RUNNER_IMAGE}

USER root

ARG DEBIAN_FRONTEND=noninteractive
ARG PACKER_VERSION=1.14.2
ARG TERRAFORM_VERSION=1.14.6
ARG ANSIBLE_CORE_VERSION=2.15.13
ARG VAULT_VERSION=1.17.3
ARG BUILDKIT_VERSION=v0.35.1

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH=/opt/ansible-2.15/bin:${PATH}

COPY --from=hashicorp-builder /usr/local/bin/packer /usr/local/bin/packer
COPY --from=hashicorp-builder /usr/local/bin/terraform /usr/local/bin/terraform
COPY --from=hashicorp-builder /usr/local/bin/vault /usr/local/bin/vault
COPY --from=hashicorp-builder /usr/local/bin/buildctl /usr/local/bin/buildctl

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        jq \
        openssh-client \
        python3 \
        python3-pip \
        python3-venv \
        rsync \
        sshpass \
        uidmap \
        unzip \
        xorriso \
        zip \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/ansible-2.15 \
    && /opt/ansible-2.15/bin/pip install --upgrade pip setuptools wheel \
    && /opt/ansible-2.15/bin/pip install "ansible-core==${ANSIBLE_CORE_VERSION}"

RUN --mount=type=secret,id=homelab_ca,dst=/run/secrets/homelab_ca \
    install -m 0644 /run/secrets/homelab_ca /usr/local/share/ca-certificates/homelab-ca.crt \
    && update-ca-certificates

USER runner
