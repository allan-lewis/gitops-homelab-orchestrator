# Proxmox L0 Runway (GitOps-friendly)

This repo contains a **working L0 "runway"** for Proxmox that you can run locally with `make`
or in GitHub Actions. It performs read‑only cluster checks and emits artifacts and a manifest
that downstream stages (image build, VM creation) can rely on.

## Quick start (local)

1. Export required environment variables (or copy `.env.example` to `.env` and `source .env`):

   ```bash
   export PVE_ACCESS_HOST="https://pve.example.com:8006"
   export PM_TOKEN_ID="ci@pve!runner"
   export PM_TOKEN_SECRET="REDACTED"
   export PVE_NODE="pve1"
   export PVE_STORAGE_VM="local-lvm"
   # Optional
   export PVE_STORAGE_ISO="local"
   export PVE_BRIDGE="vmbr0"
   export L0_MIN_FREE_GIB_ISO=4
   export L0_MIN_FREE_PCT_VM=10
   export TEMPLATE_PREFIX="arch-"
   export TEMPLATE_RETENTION=3
   ```

2. Run the runway:

   ```bash
   make l0
   ```

   Artifacts appear under `artifacts/` and the run exits **non‑zero** if guardrails fail.

3. (Optional) Run the HTTP smoke (direct `/version` call):

   ```bash
   make smoke
   ```

## GitHub Actions

Two workflows are provided:

- `.github/workflows/runway-smoke.yml` — simple `/version` smoke call with token.
- `.github/workflows/l0-runway.yml` — full runway checks on a GitHub runner.

Configure repository **Secrets** (same names as env vars) and push to run.

## Project layout

```
ansible/
  playbooks/l0_runway.yml
  roles/...
docs/
  L0-Runway.md
.github/workflows/
  runway-smoke.yml
  l0-runway.yml
Makefile
.env.example
```

## Notes

- The runway is **read‑only**: it never deletes or mutates guests or templates.
- Defaults files intentionally contain **placeholders** where appropriate; tasks are complete and runnable.
- If you prefer a single-role layout later, we can collapse sub-roles without changing behavior.
