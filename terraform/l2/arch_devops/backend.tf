terraform {
  backend "s3" {
    bucket = "gitops-homelab-orchestrator-tf"
    key    = "l2/arch_devops/terraform.tfstate"
    region = "us-east-1"
  }
}
