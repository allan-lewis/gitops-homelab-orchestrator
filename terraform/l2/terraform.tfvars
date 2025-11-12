# terraform/l2/terraform.tfvars
# Proxmox credentials/host are provided via env:
#   export PVE_ACCESS_HOST="https://proxmox.allanshomelab.com"
#   export PM_TOKEN_ID="gitops@pve!gitops"
#   export PM_TOKEN_SECRET="***"
#   export TF_VAR_pve_access_host="$PVE_ACCESS_HOST"
#   export TF_VAR_pm_token_id="$PM_TOKEN_ID"
#   export TF_VAR_pm_token_secret="$PM_TOKEN_SECRET"

# Optional (set to false since you have a valid cert)
pm_tls_insecure = false

# Reference the latest L1 manifest produced by Packer
l1_manifest_path = "../../artifacts/l1_images/qemu-102-config.json"

# Cloud-init defaults (Arch)
ci_user = "lab"
ssh_authorized_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIClabHomelabKeyExample== lab@polaris",
]

# Arch VMs with REQUIRED static IPs (ip=.../gw=...)
vms = {
  archie = {
    node      = "polaris"
    cores     = 2
    memory_mb = 2048
    disk_gb   = 20
    tags      = ["arch", "l2", "vm"]
    ipconfig0 = "ip=192.168.86.97/24,gw=192.168.86.1"
  }
}
