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
    . as $root
    | ($root.hosts // {}) as $hosts
    | ($root.ansible // {}) as $ansible
    | ($ansible.groups // {}) as $group_defs

    # Render a single var "name=value" with support for { "env": "VAR" }
    |
    def render_var(name; value):
      if (value | type) == "object"
         and (value | keys) == ["env"] then
        "\(name)=\"{{ lookup('\''env'\'', '\''\((value.env|tostring))'\'') }}\""
      else
        "\(name)=\(value)"
      end;

    # Render all vars in a map as separate lines
    def render_vars_block(vars):
      vars
      | to_entries[]
      | render_var(.key; .value);

    # Build a map: group_name -> [host1, host2, ...] from per-host group_memberships
    def groups_map:
      $hosts
      | to_entries
      | reduce .[] as $h (
          {};
          ($h.value.ansible.group_memberships // []) as $gm
          | reduce $gm[] as $g (
              .;
              .[$g] = ((.[$g] // []) + [$h.key])
            )
        );

    $hosts as $hosts
    | groups_map as $groups

    # [all] section with full host lines + host-level vars (single line per host)
    | (
        "[all]"
      ),
      (
        $hosts
        | to_entries[]
        | . as $h
        | ($h.value.ansible // {}) as $a
        | ($a.vars // {}) as $hvars
        | ($hvars
            | to_entries
            | map(render_var(.key; .value))
          ) as $extra_list
        | (
            ["ansible_host=\($h.value.ip)",
             "ansible_user=\($h.value.ssh_user)"]
            +
            (if $a.python_interpreter then
               ["ansible_python_interpreter=\($a.python_interpreter)"]
             else
               []
             end)
            +
            $extra_list
          ) as $segments
        | $h.key
          + (if ($segments | length) > 0 then
               " " + ($segments | join(" "))
             else
               ""
             end)
      ),

      # [all:vars] from ansible.all.vars (if present & non-empty)
      (
        ($ansible.all.vars // {}) as $allvars
        | if ($allvars | length) > 0 then
            "\n[all:vars]",
            (render_vars_block($allvars))
          else
            empty
          end
      ),

      # Group membership sections: one [group] per group with its hosts
      (
        $groups
        | to_entries[]
        | "\n[" + .key + "]",
          ( .value[] )
      ),

      # Group vars sections: [group:vars] from ansible.groups.<name>.vars
      (
        $group_defs
        | to_entries[]
        | . as $gd
        | ($gd.value.vars // {}) as $gvars
        | if ($gvars | length) > 0 then
            "\n[" + $gd.key + ":vars]",
            (render_vars_block($gvars))
          else
            empty
          end
      )
  ' "$HOSTS_JSON"
} > "$OUT_INI"

echo "Wrote inventory: $OUT_INI"
