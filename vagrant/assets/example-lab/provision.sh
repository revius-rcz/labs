#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates
fi

install -d -m 0755 /opt/lab
printf '%s\n' 'Vagrant lab provisioning completed.' > /opt/lab/status

