# homelab.actions-runner

[![Publish Runner Image](https://github.com/dewab-org/homelab.actions-runner/actions/workflows/publish-image.yml/badge.svg)](https://github.com/dewab-org/homelab.actions-runner/actions/workflows/publish-image.yml)

Custom GitHub Actions runner image for ARC, published privately to GHCR.

The image extends `ghcr.io/actions/actions-runner:latest`, installs a homelab CA into the container trust store at build time, and adds common infrastructure tooling:

- Python 3.12 via the base distro `python3`
- `pip`
- `ansible-core` 2.15 in an isolated virtualenv
- Packer
- Terraform
- `sshpass`
- `xorriso`
- `git`, `curl`, `jq`, `rsync`, `zip`, `unzip`

Packer and Terraform are fetched in a separate builder stage and only the final binaries are copied into the runtime image.

## Build-Time CA Injection

The CA is stored as an organization Actions secret and passed to Docker BuildKit as a secret during the publish workflow. The Docker build installs it into `/usr/local/share/ca-certificates/` and runs `update-ca-certificates`, so the trust store is present in the final image without carrying long-lived credentials into the container.

Local build example:

```bash
vault kv get -field=ca_crt secret/github-arc > /tmp/homelab-ca.crt
docker build \
  --secret id=homelab_ca,src=/tmp/homelab-ca.crt \
  --build-arg PACKER_VERSION=1.14.2 \
  --build-arg TERRAFORM_VERSION=1.14.6 \
  -t ghcr.io/<owner>/actions-runner:dev .
```

## GitHub Actions Publishing

The workflow at `.github/workflows/publish-image.yml` runs on `ubuntu-latest` and uses the hosted runner's Docker Engine directly.

The workflow:

1. Reads the CA PEM from the `HOMELAB_CA_PEM` Actions secret.
2. Resolves the latest stable Packer and Terraform releases from GitHub.
3. Builds the image.
4. Publishes it to `ghcr.io/<owner>/actions-runner`.

Expected repository configuration:

- Organization or repository secret `HOMELAB_CA_PEM`: the PEM bundle baked into the runner image
- Organization or repository secret `GHCR_USERNAME`: account name used to push the image
- Organization or repository secret `GHCR_TOKEN`: token with `write:packages` for `ghcr.io`

## Quality Checks

The repo includes `.pre-commit-config.yaml` for local checks:

- `gitleaks`
- `hadolint` for the Dockerfile
- basic YAML and whitespace checks

Local usage:

```bash
python3 -m pip install pre-commit
pre-commit run --all-files
```

## ARC Usage

Point your ARC runner scale set at the published image:

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/<owner>/actions-runner:latest
```

If your workflows use job containers or DinD, those containers still need their own CA trust strategy.
