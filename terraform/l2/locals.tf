locals {
  # Read the L1 manifest produced by your image build
  l1_manifest_raw = file(var.l1_manifest_path)
  l1              = jsondecode(local.l1_manifest_raw)

  # ide1 example: "local-lvm:vm-102-cloudinit,media=cdrom"
  _ide1_after_colon = try(element(split(":", local.l1.data.ide1), 1), "")
  _ide1_first_token = try(element(split(",", local._ide1_after_colon), 0), "")
  _ide1_parts       = split("-", local._ide1_first_token)
  _vmid_from_ide1   = try(tonumber(element(local._ide1_parts, 1)), null)

  # scsi0 example: "local-lvm:base-102-disk-0,cache=...,size=12G,ssd=1"
  _scsi0_after_colon = try(element(split(":", local.l1.data.scsi0), 1), "")
  _scsi0_first_token = try(element(split(",", local._scsi0_after_colon), 0), "")
  _scsi0_parts       = split("-", local._scsi0_first_token)
  _vmid_from_scsi0   = try(tonumber(element(local._scsi0_parts, 1)), null)

  # Final VMID for bpg clone
  template_vmid = coalesce(local._vmid_from_ide1, local._vmid_from_scsi0)
}