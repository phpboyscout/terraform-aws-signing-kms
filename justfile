# phpboyscout/terraform-aws-bootstrap — common tasks.
# Run `just` with no argument to list available recipes.

set shell := ["bash", "-euo", "pipefail", "-c"]

TOFU := env_var_or_default("TOFU", "tofu")

# Default recipe: list available tasks.
default:
    @just --list

# --- Hygiene -----------------------------------------------------------------

# Run every check that CI runs. Do this before pushing.
check: fmt-check validate lint security

# Format all .tf / .hcl files in place.
fmt:
    {{TOFU}} fmt -recursive .

# Fail if anything would be reformatted.
fmt-check:
    {{TOFU}} fmt -recursive -check -diff .

# tofu validate every module under modules/ and the root + each example.
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    dirs=(. modules/*/ examples/*/)
    for d in "${dirs[@]}"; do
      if compgen -G "$d/*.tf" > /dev/null 2>&1 || compgen -G "$d*.tf" > /dev/null 2>&1; then
        echo ">> validate $d"
        ( cd "$d" && {{TOFU}} init -backend=false -input=false >/dev/null && {{TOFU}} validate )
      fi
    done

# Lint every module / example with tflint.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v tflint >/dev/null; then
      echo "tflint not installed — see https://github.com/terraform-linters/tflint"
      exit 1
    fi
    tflint --init
    tflint --recursive --config="$(pwd)/.tflint.hcl"

# Run security scans (trivy config + checkov if installed).
security:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v trivy >/dev/null; then
      trivy config --severity HIGH,CRITICAL --exit-code 1 .
    else
      echo "trivy not installed — skipping (see https://github.com/aquasecurity/trivy)"
    fi
    if command -v checkov >/dev/null; then
      checkov --quiet --directory . --framework terraform
    else
      echo "checkov not installed — skipping"
    fi

# Regenerate per-module README input/output tables via terraform-docs.
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v terraform-docs >/dev/null; then
      echo "terraform-docs not installed — see https://terraform-docs.io"
      exit 1
    fi
    for d in . modules/*/; do
      if compgen -G "$d/*.tf" > /dev/null 2>&1 || compgen -G "$d*.tf" > /dev/null 2>&1; then
        echo ">> terraform-docs $d"
        terraform-docs markdown table --output-file README.md --output-mode inject "$d"
      fi
    done

# --- Zensical microsite (docs/ -> site/) -------------------------------------

# Build the microsite into ./site/
site-build:
    zensical build --clean

# Serve the microsite locally with hot reload (default: http://127.0.0.1:8000).
site-serve:
    zensical serve

# --- Dev setup ---------------------------------------------------------------

# Install pre-commit hooks.
setup:
    pre-commit install --install-hooks
    pre-commit install --hook-type commit-msg

# Run all pre-commit hooks against every file.
pre-commit-all:
    pre-commit run --all-files
