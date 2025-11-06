# L0 Runway: What it checks

**Purpose:** ensure Proxmox is in a known‑good state before image build (L1) or VM create (L2).

**Checks (read‑only):**
- API & auth reachable (`/api2/json/version`)
- Node online (`/nodes`)
- Bridge present & active (`/nodes/{node}/network`)
- Storage thresholds:
  - ISO/content store has ≥ `L0_MIN_FREE_GIB_ISO` GiB
  - VM store has ≥ `L0_MIN_FREE_PCT_VM` %
- Template registry (prefix `TEMPLATE_PREFIX`): enumerate, compute latest, prune plan (dry run)

**Outputs:**
- JSON artifacts under `artifacts/`
- `runway_manifest.json` with status, facts, and prune plan
- Final summary echoed by the play, and non‑zero exit if guardrails fail
