# STEP 1 — L0 runway smoke (GH-hosted runner + Cloudflared)

Goal: Prove GitHub-hosted runners can reach the Proxmox API via a Cloudflare Access client proxy.

Prereqs:
- Cloudflare Tunnel + Access app protecting https://pve-api.<yourdomain> (service token only)
- Proxmox API token (least privilege)

Configure (GitHub → Environment: lab):
- PVE_ACCESS_HOST
- CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET
- PM_TOKEN_ID / PM_TOKEN_SECRET
- (optional) PM_API_URL_PATH=/api2/json/version

Run:
- "Actions" → "L0 runway smoke (proxy only)" → "Run workflow" → Environment: lab

Expected:
- Job prints Proxmox version JSON and uploads it as an artifact (pve-version).
- If it fails, check cloudflared.log output from the job.

