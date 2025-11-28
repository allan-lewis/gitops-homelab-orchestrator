terraform {
  backend "s3" {
    bucket = "gitops-homelab-orchestrator-tf"
    key    = "l2/ubuntu_tinker/terraform.tfstate"
    region = "us-east-1"
  }
}
