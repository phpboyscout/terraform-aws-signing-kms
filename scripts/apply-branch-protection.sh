#!/usr/bin/env bash
#
# Apply the branch-protection rulesets committed under .github/rulesets/.
#
# Requires `gh` authenticated with admin access to the repo, and a repo
# plan that supports rulesets (free for public repos).

set -euo pipefail

REPO="${REPO:-phpboyscout/terraform-aws-bootstrap}"
MODE="${1:-create}"   # "create" (default) or "update"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for name in main develop; do
  file="${here}/.github/rulesets/${name}.json"
  if [[ ! -f "${file}" ]]; then
    echo "missing: ${file}" >&2
    exit 1
  fi

  case "${MODE}" in
    create)
      echo ">> creating ${name}-protection ruleset"
      gh api --method POST "repos/${REPO}/rulesets" --input "${file}" --jq '{id, name, enforcement}'
      ;;
    update)
      existing_id="$(gh api "repos/${REPO}/rulesets" --jq ".[] | select(.name == \"${name}-protection\") | .id")"
      if [[ -z "${existing_id}" ]]; then
        echo ">> no existing ${name}-protection ruleset, creating"
        gh api --method POST "repos/${REPO}/rulesets" --input "${file}" --jq '{id, name, enforcement}'
      else
        echo ">> updating ${name}-protection ruleset (id=${existing_id})"
        gh api --method PUT "repos/${REPO}/rulesets/${existing_id}" --input "${file}" --jq '{id, name, enforcement}'
      fi
      ;;
    *)
      echo "usage: $0 [create|update]" >&2
      exit 2
      ;;
  esac
done

echo "done."
