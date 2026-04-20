# homelab.actions-runner

[![Publish Runner Image](https://github.com/dewab-org/homelab.actions-runner/actions/workflows/publish-image.yml/badge.svg)](https://github.com/dewab-org/homelab.actions-runner/actions/workflows/publish-image.yml)

Custom GitHub Actions runner image for ARC, published privately to GHCR.

The image extends `ghcr.io/actions/actions-runner:latest`, installs a homelab CA into the container trust store at build time, and adds common infrastructure tooling:

- Python 3.12 via the base distro `python3`
- `pip`
- `ansible-core` 2.15 in an isolated Python 3.11 virtualenv
- Packer
- Terraform
- `sshpass`
- `xorriso`
- `git`, `curl`, `jq`, `rsync`, `zip`, `unzip`

Packer and Terraform are fetched in a separate builder stage and only the final binaries are copied into the runtime image.

## Why Ansible Uses Python 3.11

`ansible-core` 2.15 officially targets Python 3.9-3.11 for controller-side execution. This image keeps `python3` on 3.12 for general use, and installs Ansible 2.15 in `/opt/ansible-2.15` on Python 3.11 so both requirements can coexist cleanly.

## Build-Time CA Injection

The CA is fetched from Vault in GitHub Actions and passed to Docker BuildKit as a secret. The Docker build installs it into `/usr/local/share/ca-certificates/` and runs `update-ca-certificates`, so the trust store is present in the final image without carrying Vault credentials into the container.

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

The workflow at `.github/workflows/publish-image.yml` targets the ARC runner scale set name directly:

- `arc-runners`

In this GitHub org, the ARC runners are shared organization runners in the `Default` runner group. For ARC scale sets, GitHub expects `runs-on` to be the scale set name or configured scale set label, not standard self-hosted labels like `self-hosted`, `linux`, and `x64`.

For manual runs, you can override the target scale set with the `runner_label` workflow input if you register an additional ARC runner scale set.

The workflow:

1. Authenticates to Vault with GitHub OIDC.
2. Reads the CA PEM from Vault.
3. Resolves the latest stable Packer and Terraform releases from GitHub.
4. Builds the image.
5. Publishes it to `ghcr.io/<owner>/actions-runner`.

Expected repository configuration:

### Repository Variables

- `VAULT_ADDR`: Vault base URL, for example `https://vault.viking.org`
- `VAULT_AUTH_PATH`: Vault JWT auth mount used by GitHub Actions, for example `github-actions`
- `VAULT_AUTH_ROLE`: Vault role bound to this repository
- `VAULT_CA_SECRET_PATH`: KV v2 path that contains the CA PEM, for example `secret/data/github-arc`
- `VAULT_CA_SECRET_KEY`: field name in that secret, for example `ca_crt`

### Repository Secrets

- `VAULT_SERVER_CA_PEM`: PEM for validating Vault itself; this can be stored as a repository secret or an organization secret granted to this repository

## Builder Trust Boundary

Because Vault is read during the image build workflow, the self-hosted builder must already be able to connect to Vault.

That means one of these must be true before the workflow runs:

- the self-hosted runner host already trusts the Vault server certificate chain
- `VAULT_SERVER_CA_PEM` is set so `hashicorp/vault-action` can validate Vault explicitly

This is separate from the CA being baked into the ARC runner image. The builder needs Vault trust first; the built image then carries the homelab CA for downstream jobs.

The publish workflow bootstraps Vault TLS trust before `hashicorp/vault-action` runs by writing `VAULT_SERVER_CA_PEM` to a temporary file and exporting it through `NODE_EXTRA_CA_CERTS`.

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
