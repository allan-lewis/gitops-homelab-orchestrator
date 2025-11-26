#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   l3-inventory.sh <os> <persona>
#
# Examples:
#   l3-inventory.sh arch devops
#   l3-inventory.sh arch tinker
#
# Reads:
#   infra/<os>/<persona>/spec/hosts.json
# Writes:
#   artifacts/<os>/<persona>/hosts.ini

OS="${1:?Usage: $0 <os> <persona>}"
PERSONA="${2:?Usage: $0 <os> <persona>}"

HOSTS_JSON="infra/${OS}/${PERSONA}/spec/hosts.json"
OUT_INI="artifacts/${OS}/${PERSONA}/hosts.ini"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to render the Ansible inventory" >&2
  exit 1
fi

if [ ! -f "$HOSTS_JSON" ]; then
  echo "hosts.json not found at: $HOSTS_JSON" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_INI")"

{
  echo "# generated from $HOSTS_JSON on $(date -u +%FT%TZ)"
  echo "# DO NOT COMMIT THIS FILE"

  jq -r '
    # Build a map: group_name -> [host1, host2, ...]
    def groups_map:
      .hosts
      | to_entries
      | reduce .[] as $h (
          {};
          reduce ($h.value.ansible.groups // [])[] as $g (
            .;
            .[$g] = ((.[$g] // []) + [$h.key])
          )
        );

    .hosts as $hosts
    | groups_map as $groups
    | (
        "[all]"
      ),
      (
        # Full host lines with connection vars
        $hosts
        | to_entries[]
        | "\(.key) ansible_host=\(.value.ip) ansible_user=\(.value.ssh_user) ansible_python_interpreter=\(.value.ansible.python_interpreter)"
      ),
      (
        # One section per group, listing member hosts
        $groups
        | to_entries[]
        | "\n[" + .key + "]",
          ( .value[] )
      )
  ' "$HOSTS_JSON"
} > "$OUT_INI"

echo "Wrote inventory: $OUT_INI"
