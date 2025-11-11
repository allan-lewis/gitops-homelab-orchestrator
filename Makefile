SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

# Wrap every command (default uses Doppler). Override with: RUN=
RUN ?= doppler run --

export PIP_DISABLE_PIP_VERSION_CHECK=1

# Load .env if present
ifneq (,$(wildcard ./.env))
include .env
export
endif

.PHONY: help clean l0-smoke l0-build l0-clean \
        l1 l1-init l1-validate l1-build l1-manifest l1-clean

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
	  : \"$$\{PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST\}\"; \
	  : \"$$\{PM_TOKEN_ID:?Missing PM_TOKEN_ID\}\"; \
	  : \"$$\{PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET\}\"; \
	  ansible-playbook ansible/playbooks/l0_runway.yml"

l0-clean: ## Remove L1 artifacts
	@$(RUN) bash -lc "set -euo pipefail; rm -rf artifacts/l0_smoke_version.json"

# --- L1 (Image Build) ---------------------------------------------------------
# Required env at runtime:
#   PVE_ACCESS_HOST   PM_TOKEN_ID   PM_TOKEN_SECRET
# Optional (but recommended):
#   TEMPLATE_NAME  TEMPLATE_PREFIX  PVE_NODE  PVE_BRIDGE  PVE_STORAGE_VM  ARCH_ISO_FILE

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

l1-manifest: ## Fetch VM config and save pretty JSON
	@$(RUN) bash -lc 'set -euo pipefail; \
	  : "$${PVE_ACCESS_HOST:?Missing PVE_ACCESS_HOST}"; \
	  : "$${PM_TOKEN_ID:?Missing PM_TOKEN_ID}"; \
	  : "$${PM_TOKEN_SECRET:?Missing PM_TOKEN_SECRET}"; \
	  : "$${PVE_NODE:?Missing PVE_NODE}"; \
	  mkdir -p artifacts/l1_images; \
	  [ -f artifacts/l1_vmid ] || { echo "artifacts/l1_vmid not found. Run make l1-build first."; exit 1; }; \
	  vmid="$$(cat artifacts/l1_vmid)"; \
	  AUTH="Authorization: PVEAPIToken=$${PM_TOKEN_ID}=$${PM_TOKEN_SECRET}"; \
	  HOST="$${PVE_ACCESS_HOST%/}/api2/json"; \
	  out="artifacts/l1_images/qemu-$${vmid}-config.json"; \
	  echo "GET $$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config -> $$out"; \
	  if command -v jq >/dev/null 2>&1; then \
	    curl -fsS -H "$$AUTH" "$$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config" | jq -S . > "$$out"; \
	  else \
	    curl -fsS -H "$$AUTH" "$$HOST/nodes/$${PVE_NODE}/qemu/$$vmid/config" > "$$out"; \
	  fi; \
	  echo "Wrote $$out"'

l1-clean: ## Remove L1 outputs and manifests
	@$(RUN) bash -lc "set -euo pipefail; rm -rf packer/arch/artifacts artifacts/l1* artifacts/l1_images artifacts/packer-manifest.json"
