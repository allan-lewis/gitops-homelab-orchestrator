SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

## Secrets runner wrapper
## - Default: use Doppler locally.
## - In CI (GitHub Actions), default to **no Doppler**.
## - You can still override explicitly:
##     make l1-build RUN=
##     make l1-build DOPPLER=0
##     make l1-build FORCE_DOPPLER=1

# Local default
RUN ?= doppler run --

# Auto-disable in CI unless explicitly forced
ifeq ($(CI),true)
  ifneq ($(FORCE_DOPPLER),1)
    override RUN :=
  endif
endif

# Manual kill switch (works anywhere): DOPPLER=0
ifeq ($(DOPPLER),0)
  override RUN :=
endif

export RUN

export PIP_DISABLE_PIP_VERSION_CHECK=1

# Load .env if present
ifneq (,$(wildcard ./.env))
include .env
export
endif

help: ## Show targets
	@awk 'BEGIN{FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

clean: ## Remove all artifacts
	@$(RUN) bash -lc "set -euo pipefail; rm -rf artifacts"

l0-smoke: ## Call /api2/json/version with Proxmox token and save pretty artifacts/l0_smoke_version.json
	@$(RUN) bash -lc 'set -euo pipefail; \
	  mkdir -p artifacts; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  URL="$${PVE_ACCESS_HOST%/}/api2/json/version"; \
	  echo "GET $$URL"; \
	  if command -v jq >/dev/null 2>&1; then \
	    curl -fsS -H "Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}" "$$URL" \
	      | jq -S . > artifacts/l0_smoke_version.json; \
	  else \
	    curl -fsS -H "Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}" "$$URL" \
	      > artifacts/l0_smoke_version.json; \
	  fi; \
	  echo "Smoke OK -> artifacts/l0_smoke_version.json"'

l0-build: ## Run the L0 runway locally (via Ansible), with Doppler env
	@$(RUN) bash -lc "set -euo pipefail; \
	  mkdir -p artifacts; \
	  : \"$$\{PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST\}\"; \
	  : \"$$\{PM_TOKEN_ID:?Missing PM_TOKEN_ID\}\"; \
	  : \"$$\{PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET\}\"; \
	  ansible-playbook ansible/playbooks/l0_runway.yml"

l0-clean: ## Remove L1 artifacts
	@$(RUN) bash -lc "set -euo pipefail; rm -rf artifacts/l0_smoke_version.json"

# --- L1 (Image Build) ---------------------------------------------------------

l1-fmt: ## Packer format for L1 (Arch)
	@$(RUN) bash -lc "set -euo pipefail; cd packer/arch; packer fmt ."

l1-init: ## Packer init for L1 (Arch)
	@$(RUN) bash -lc "set -euo pipefail; cd packer/arch; packer init ."

l1-validate: ## Validate L1 packer config (with Doppler env)
	@$(RUN) bash -lc "set -euo pipefail; cd packer/arch; packer validate ."

l1-build: ## Build the Arch template (Packer -> Proxmox) and capture VMID from packer-manifest.json
	@$(RUN) bash -lc 'set -euo pipefail; \
	  mkdir -p artifacts; \
	  echo "Running Packer build..."; \
	  packer build packer/arch | tee artifacts/l1_packer.log; \
	  manifest="artifacts/packer-manifest.json"; \
	  [ -f "$$manifest" ] || { echo "Missing $$manifest; Packer did not emit a manifest" >&2; exit 1; }; \
	  vmid="$$(jq -r '\''(.last_run_uuid) as $$id | (.builds[] | select(.packer_run_uuid==$$id) | .artifact_id) // (.builds[-1].artifact_id)'\'' "$$manifest")"; \
	  case "$$vmid" in ""|*[!0-9]*) echo "Could not parse numeric VMID from $$manifest (got: $$vmid)" >&2; exit 1;; esac; \
	  printf "%s\n" "$$vmid" > artifacts/l1_vmid; \
	  echo "Captured VMID=$$vmid"'

l1-manifest: ## Fetch VM config and save pretty JSON + normalized manifest
	@$(RUN) bash -lc 'set -euo pipefail; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  : "$${PVE_NODE:?Missing PVE_NODE}"; \
	  command -v jq >/dev/null 2>&1 || { echo "jq is required for l1-manifest"; exit 1; }; \
	  mkdir -p artifacts/l1_images; \
	  [ -f artifacts/l1_vmid ] || { echo "artifacts/l1_vmid not found. Run make l1-build first."; exit 1; }; \
	  vmid="$$(cat artifacts/l1_vmid)"; \
	  AUTH="Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}"; \
	  HOST="$${PVE_ACCESS_HOST%/}/api2/json"; \
	  raw_out="artifacts/l1_images/qemu-$${vmid}-config.json"; \
	  norm_out="artifacts/l1_images/manifest.json"; \
	  echo "GET $$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config -> $$raw_out and $$norm_out"; \
	  resp="$$(curl -fsS -H "$$AUTH" "$$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config")"; \
	  echo "$$resp" | jq -S . > "$$raw_out"; \
	  echo "$$resp" | jq -S --arg vmid "$$vmid" --arg node "$${PVE_NODE}" "{vmid:(\$$vmid|tonumber), node:\$$node} + .data" > "$$norm_out"; \
	  echo "Wrote $$raw_out"; \
	  echo "Wrote $$norm_out"'

l1-clean: ## Remove L1 outputs and manifests
	@$(RUN) bash -lc "set -euo pipefail; rm -rf packer/arch/artifacts artifacts/l1* artifacts/l1_images artifacts/packer-manifest.json"

# --- L2 (VM Creation) ---------------------------------------------------------

l2-fmt:
	@$(RUN) bash -lc 'terraform -chdir=terraform/l2 fmt'

l2-init:
	@$(RUN) bash -lc 'export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; terraform -chdir=terraform/l2 init -upgrade'

l2-validate:
	@$(RUN) bash -lc 'export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; terraform -chdir=terraform/l2 validate'

l2-plan:
	@$(RUN) bash -lc '\
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; \
	  export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; \
	  export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; \
	  export TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY"; \
	  export TF_VAR_l1_manifest_json="$$(jq -c '.' artifacts/l1_images/manifest.json)"; \
	  terraform -chdir=terraform/l2 plan'

l2-apply:
	@$(RUN) bash -lc '\
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; \
	  export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; \
	  export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; \
	  export TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY"; \
	  export TF_VAR_l1_manifest_json="$$(jq -c '.' artifacts/l1_images/manifest.json)"; \
	  terraform -chdir=terraform/l2 apply -auto-approve'

l2-destroy:
	@$(RUN) bash -lc '\
	  export TF_VAR_pve_access_host="$$PVE_ACCESS_HOST"; \
	  export TF_VAR_pm_token_id="$$PM_TOKEN_ID"; \
	  export TF_VAR_pm_token_secret="$$PM_TOKEN_SECRET"; \
	  export TF_VAR_proxmox_vm_public_key="$$TF_VAR_PROXMOX_VM_PUBLIC_KEY"; \
	  export TF_VAR_l1_manifest_json="$$(jq -c '.' artifacts/l1_images/manifest.json)"; \
	  terraform -chdir=terraform/l2 destroy -auto-approve'

l2-inventory:
	@echo "📦 L2 inventory:"
	@ls -lh artifacts/l2_inventory 2>/dev/null || echo "No inventory files yet"
	@echo ""
	@jq . artifacts/l2_inventory/inventory.json 2>/dev/null || echo "No JSON inventory yet"

l2-clean:
	@rm -rf artifacts/l2_inventory
	@echo "🧹 Removed generated L2 inventory artifacts."

# --- L3 (Arch Convergence) : Phase 0 ---------------------------------------------------------

l3-smoke: ## L3: verify env/tools/inputs before any convergence
	@$(RUN) bash -lc "set -euo pipefail; \
	  echo '[L3] Smoking the env...'; \
	  need_cmds=(ansible jq python3 bash); \
	  for c in $${need_cmds[@]}; do \
	    if ! command -v $$c >/dev/null 2>&1; then \
	      echo 'Missing required command:' $$c >&2; exit 1; \
	    fi; \
	  done; \
	  echo '[L3] Tool versions:'; \
	  ansible --version | head -n1 || true; \
	  jq --version || true; \
	  python3 --version || true; \
	  bash --version | head -n1 || true; \
	  echo '[L3] Checking expected repo paths...'; \
	  if [ -f ansible/playbooks/l3_arch.yml ]; then \
	    PLAYBOOK=ansible/playbooks/l3_arch.yml; \
	  elif [ -f ansible/playbooks/l3_provision.yml ]; then \
	    PLAYBOOK=ansible/playbooks/l3_provision.yml; \
	  else \
	    echo 'No L3 playbook found (expected ansible/playbooks/l3_arch.yml or l3_provision.yml)'; \
	    exit 1; \
	  fi; \
	  echo '  ✓ Playbook:' $$PLAYBOOK; \
	  if [ ! -f artifacts/l2_inventory/inventory.json ]; then \
	    echo 'Missing artifacts/l2_inventory/inventory.json (run L2 first)'; exit 1; \
	  fi; \
	  jq -e '. | type == \"object\"' artifacts/l2_inventory/inventory.json >/dev/null || { echo 'inventory.json is not a JSON object'; exit 1; }; \
	  echo '  ✓ L2 inventory present and valid JSON'; \
	  echo '[L3] Smoke OK.'"

l3-prepare: ## L3: create scaffolding, clean stale outputs, summarize inputs
	@$(RUN) bash -lc "set -euo pipefail; \
	  echo '[L3] Preparing folders...'; \
	  mkdir -p artifacts/l3/l3_logs artifacts/l3/pull_logs; \
	  rm -f artifacts/l3/l3_summary.json artifacts/l3/.lock || true; \
	  echo '[L3] Verifying inventory...'; \
	  if [ ! -f artifacts/l2_inventory/inventory.json ]; then \
	    echo 'Missing artifacts/l2_inventory/inventory.json (run L2 first)'; exit 1; \
	  fi; \
	  echo '[L3] Hosts discovered in inventory:'; \
	  if jq -e '. | type == \"object\"' artifacts/l2_inventory/inventory.json >/dev/null 2>&1; then \
	    jq -r 'keys[]' artifacts/l2_inventory/inventory.json | sed 's/^/  - /'; \
	  else \
	    echo '  (inventory is not an object; please fix)'; exit 1; \
	  fi; \
	  echo '[L3] Prepare OK → artifacts/l3/'"

# --- L3 (Arch Convergence) : Phase 1 ---------------------------------------------------------

#   L2_INVENTORY_SRC=path/to/inventory.json make l3-fetch-inventory
L2_INVENTORY_SRC ?= artifacts/l2_inventory/inventory.json

l3-fetch-inventory: ## L3: fetch/refresh L2 inventory into standard location with validation
	@set -euo pipefail; \
	ROOT_DIR='$(CURDIR)'; \
	echo "[L3] Fetching inventory..."; \
	echo "  L2_INVENTORY_SRC=$(L2_INVENTORY_SRC)"; \
	RAW_SRC='$(L2_INVENTORY_SRC)'; \
	case "$$RAW_SRC" in \
	  /*) SRC="$$RAW_SRC" ;; \
	  *)  SRC="$$ROOT_DIR/$$RAW_SRC" ;; \
	esac; \
	DEST_DIR="$$ROOT_DIR/artifacts/l2_inventory"; \
	DEST_FILE="$$DEST_DIR/inventory.json"; \
	echo "  SRC : $$SRC"; \
	echo "  DEST: $$DEST_FILE"; \
	mkdir -p "$$DEST_DIR" "$$ROOT_DIR/artifacts/l3"; \
	if [ ! -f "$$SRC" ]; then \
	  echo "❌ Source inventory not found: $$SRC" >&2; \
	  echo "Hint: set L2_INVENTORY_SRC to the path of your L2 inventory.json" >&2; \
	  PDIR="$$(dirname "$$SRC")"; \
	  echo "Parent dir contents:"; ls -la "$$PDIR" 2>/dev/null || echo "(cannot list parent dir)"; \
	  exit 1; \
	fi; \
	if ! jq -e '. | type == "object"' "$$SRC" >/dev/null; then \
	  echo "❌ Invalid inventory (expected top-level JSON object): $$SRC" >&2; \
	  exit 1; \
	fi; \
	if [ "$$SRC" != "$$DEST_FILE" ]; then \
	  cp -f "$$SRC" "$$DEST_FILE"; \
	  echo "  ✓ Copied inventory to $$DEST_FILE"; \
	else \
	  echo "  ✓ Inventory already at canonical path"; \
	fi; \
	if command -v shasum >/dev/null 2>&1; then \
	  shasum -a 256 "$$DEST_FILE" | awk '{print $$1}' > "$$ROOT_DIR/artifacts/l3/l2_inventory.sha256"; \
	elif command -v sha256sum >/dev/null 2>&1; then \
	  sha256sum "$$DEST_FILE" | awk '{print $$1}' > "$$ROOT_DIR/artifacts/l3/l2_inventory.sha256"; \
	else \
	  echo "(sha256 tool not found; skipping checksum)"; \
	  : > "$$ROOT_DIR/artifacts/l3/l2_inventory.sha256"; \
	fi; \
	printf "  ✓ Checksum: "; \
	[ -s "$$ROOT_DIR/artifacts/l3/l2_inventory.sha256" ] && cat "$$ROOT_DIR/artifacts/l3/l2_inventory.sha256" || echo "(none)"; \
	echo "[L3] Hosts in inventory:"; \
	jq -r 'keys[]' "$$DEST_FILE" | sed 's/^/  - /' || true; \
	echo "[L3] Fetch OK → $$DEST_FILE"

INV := $(CURDIR)/artifacts/l2_inventory/inventory.json
OUT := $(CURDIR)/artifacts/l3/hosts

l3-validate-inventory: ## L3: validate schema & readiness in artifacts/l2_inventory/inventory.json
	@set -euo pipefail
	@echo "[L3] Validating inventory: $(INV)"
	@test -f "$(INV)" || (echo "❌ Missing $(INV). Run L2 or l3-fetch-inventory." && exit 1)
	@jq -e "type==\"object\"" "$(INV)" >/dev/null || (echo "❌ Top-level JSON must be an object (host -> props)" && exit 1)
	@jq -e "length>0" "$(INV)" >/dev/null || (echo "❌ Inventory has no hosts" && exit 1)
	@# Require per-host ip and ssh_user as non-empty strings
	@if ! jq -e 'all(.[]; (.ip|type)=="string" and (.ip|length)>0 and (.ssh_user|type)=="string" and (.ssh_user|length)>0 and (.guest_agent_ip|type)=="string" and (.guest_agent_ip|length)>0 and (.guest_agent_healthy == true))' "$(INV)" >/dev/null; then \
	  echo '❌ Invalid hosts (ip/ssh_user/guest_agent_ip missing/empty, or guest_agent_healthy!=true):'; \
	  jq -r 'to_entries | map(select((.value.ip|type)!="string" or (.value.ip|length)==0 or (.value.ssh_user|type)!="string" or (.value.ssh_user|length)==0 or (.value.guest_agent_ip|type)!="string" or (.value.guest_agent_ip|length)==0 or (.value.guest_agent_healthy != true))) | .[] | "- \(.key)"' "$(INV)"; \
	  exit 1; \
	fi
	@echo "[L3] ✅ Inventory OK"
	@echo "[L3] Hosts:"
	@jq -r "keys[]" "$(INV)" | sed 's/^/  - /'

l3-render-inventory: ## L3: render Ansible inventory to artifacts/l3/hosts
	@set -euo pipefail
	@echo "[L3] Rendering inventory → $(OUT)"
	@test -f "$(INV)" || (echo "❌ Missing $(INV). Run l3-fetch-inventory / l3-validate-inventory." && exit 1)
	@mkdir -p "$(CURDIR)/artifacts/l3"
	@{ \
	  echo "# generated by l3-render-inventory"; \
	  echo "[all]"; \
	  jq -r 'to_entries \
	    | .[] \
	    | "\(.key) ansible_host=\((.value.guest_agent_ip // (.value.ip | sub("/[0-9]+$$"; "")))) ansible_user=\(.value.ssh_user)"' \
	    "$(INV)"; \
	} > "$(OUT)"
	@echo "[L3] Wrote $(OUT)"
	@echo "[L3] Preview:"
	@sed -n '1,20p' "$(OUT)"