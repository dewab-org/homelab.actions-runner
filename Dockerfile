# syntax=docker/dockerfile:1.7

ARG RUNNER_IMAGE=ghcr.io/actions/actions-runner:latest
FROM ${RUNNER_IMAGE}

USER root

ARG DEBIAN_FRONTEND=noninteractive
ARG PACKER_VERSION=1.14.2
ARG TERRAFORM_VERSION=1.14.6
ARG ANSIBLE_CORE_VERSION=2.15.13

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH=/opt/ansible-2.15/bin:${PATH}

COPY scripts/install-hashicorp-release.sh /usr/local/bin/install-hashicorp-release.sh

RUN chmod 0755 /usr/local/bin/install-hashicorp-release.sh \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        openssh-client \
        python3 \
        python3-pip \
        python3-venv \
        python3.11 \
        python3.11-venv \
        rsync \
        sshpass \
        unzip \
        xorriso \
        zip \
    && rm -rf /var/lib/apt/lists/*

RUN /usr/local/bin/install-hashicorp-release.sh packer "${PACKER_VERSION}" \
    && /usr/local/bin/install-hashicorp-release.sh terraform "${TERRAFORM_VERSION}"

RUN python3 -m pip install --upgrade pip setuptools wheel \
    && python3.11 -m venv /opt/ansible-2.15 \
    && /opt/ansible-2.15/bin/pip install --upgrade pip setuptools wheel \
    && /opt/ansible-2.15/bin/pip install "ansible-core==${ANSIBLE_CORE_VERSION}"

RUN --mount=type=secret,id=homelab_ca,dst=/run/secrets/homelab_ca \
    install -m 0644 /run/secrets/homelab_ca /usr/local/share/ca-certificates/homelab-ca.crt \
    && update-ca-certificates

USER runner
