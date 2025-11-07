# L1 – Arch image build (Proxmox via Packer)

## Prereqs
- macOS: `brew install packer doppler`
- Proxmox API token with VM create/template perms.

## Run (with Doppler)
```bash
cd packer/arch
packer init .
packer fmt .
packer validate .
doppler run -- packer build .
