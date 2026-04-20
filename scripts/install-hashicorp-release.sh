#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <tool> <version>" >&2
  exit 1
fi

tool="$1"
version="$2"

case "${TARGETARCH:-amd64}" in
  amd64)
    arch="amd64"
    ;;
  arm64)
    arch="arm64"
    ;;
  *)
    echo "unsupported TARGETARCH: ${TARGETARCH:-unknown}" >&2
    exit 1
    ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

archive="${tool}_${version}_linux_${arch}.zip"
base_url="https://releases.hashicorp.com/${tool}/${version}"

curl -fsSL -o "${tmpdir}/${archive}" "${base_url}/${archive}"
curl -fsSL -o "${tmpdir}/SHA256SUMS" "${base_url}/${tool}_${version}_SHA256SUMS"

(cd "${tmpdir}" && grep " ${archive}\$" SHA256SUMS | sha256sum -c -)
unzip -q "${tmpdir}/${archive}" -d /usr/local/bin
chmod 0755 "/usr/local/bin/${tool}"
