# The upstream tag is intentionally resolved to the linux/amd64 manifest digest.
# Updating the runner is a reviewed change rather than an implicit pull of latest.
FROM ghcr.io/myoung34/docker-github-actions-runner@sha256:173ca65612b178a575971302bb31658e0cb4ec2cf48a0a817819e20fe7ef98f9

USER root

# The pinned upstream runner currently uses Ubuntu 20.04 (focal). 2.72.0 is the
# newest Azure CLI package Microsoft publishes in the focal repository. Packages
# are verified through Microsoft's signing key instead of piping an install
# script into a privileged shell at job runtime.
ARG AZURE_CLI_VERSION="2.72.0-1~focal"

RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
    && chmod go+r /etc/apt/keyrings/microsoft.gpg \
    && printf '%s\n' \
      'Types: deb' \
      'URIs: https://packages.microsoft.com/repos/azure-cli/' \
      'Suites: focal' \
      'Components: main' \
      'Architectures: amd64' \
      'Signed-by: /etc/apt/keyrings/microsoft.gpg' \
      > /etc/apt/sources.list.d/azure-cli.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends "azure-cli=${AZURE_CLI_VERSION}" \
    && az version \
    && rm -rf /var/lib/apt/lists/*
