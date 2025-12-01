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
#   artifacts/<os>/<persona>/hosts.yml (JSON, which is valid YAML)

OS="${1:?Usage: $0 <os> <persona>}"
PERSONA="${2:?Usage: $0 <os> <persona>}"

HOSTS_JSON="infra/os/${OS}/personas/${PERSONA}/spec/hosts.json"
OUT_YAML="artifacts/l3-inventory/${OS}/${PERSONA}/hosts.yml"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to render the Ansible inventory" >&2
  exit 1
fi

if [ ! -f "$HOSTS_JSON" ]; then
  echo "hosts.json not found at: $HOSTS_JSON" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_YAML")"

{
  echo "# generated from $HOSTS_JSON on $(date -u +%FT%TZ)"
  echo "# DO NOT COMMIT THIS FILE"
  echo

  jq '
    . as $root
    | ($root.hosts // {}) as $hosts
    | ($root.ansible // {}) as $ansible
    | ($ansible.groups // {}) as $group_defs

    # Render a value:
    # - { "env": "VAR" }  ->  "{{ lookup('env', 'VAR') }}"
    # - arrays / scalars  ->  as-is
    |
    def render_value(v):
      if (v | type) == "object" and (v | keys) == ["env"] then
        "{{ lookup('"'"'env'"'"', \"\(v.env|tostring)\") }}"
      else
        v
      end;

    # Apply render_value to all values in a vars map
    def render_vars_map(vars):
      vars | with_entries(.value = render_value(.value));

    # Build host vars object for a single host
    def host_vars(host_key; host_val):
      (host_val.ansible // {}) as $a
      | ($a.vars // {}) as $hvars
      | {
          ansible_host: host_val.ip,
          ansible_user: host_val.ssh_user
        }
        + (if $a.python_interpreter then
             { ansible_python_interpreter: $a.python_interpreter }
           else
             {}
           end)
        + (render_vars_map($hvars));

    # Build group_name -> [hostnames] from per-host group_memberships
    def groups_map:
      $hosts
      | to_entries
      | reduce .[] as $h ({}; 
          ($h.value.ansible.group_memberships // []) as $gm
          | reduce $gm[] as $g (.;
              .[$g] = ((.[$g] // []) + [$h.key])
            )
        );

    $hosts as $hosts
    | groups_map as $gm
    | ($group_defs // {}) as $group_defs
    | (
        (( $gm | keys ) + ( $group_defs | keys )) 
        | unique
      ) as $group_names

    # Build final inventory structure
    | {
        all: {
          hosts: (
            $hosts
            | with_entries(
                .value = host_vars(.key; .value)
              )
          ),
          vars: (
            ($ansible.all.vars // {})
            | render_vars_map(.)
          ),
          children: (
            $group_names
            | map(
                {
                  key: .,
                  value: {
                    hosts: (
                      ($gm[.] // [])
                      | map({ key: ., value: {} })
                      | from_entries
                    ),
                    vars: (
                      ($group_defs[.].vars // {})
                      | render_vars_map(.)
                    )
                  }
                }
              )
            | from_entries
          )
        }
      }
  ' "$HOSTS_JSON"
} > "$OUT_YAML"

echo "Wrote inventory: $OUT_YAML"
