# ----------------------------------------------------------------------------------------
# Variables
# ----------------------------------------------------------------------------------------
variable "prefix" {
  description = "Prefix to configured items in Azure"
  type        = string
  default     = "fgt-ha-xlb"
}

variable "custom_vars" {
  description = "Custom variables"
  type = object({
    region         = optional(string, "spaincentral")
    fgt_version    = optional(string, "7.4.6")
    license_type   = optional(string, "payg")
    fgt_size       = optional(string, "Standard_F4s")
    fgt_vnet_cidr  = optional(string, "172.10.0.0/23")
    admin_username = optional(string, "azureadmin")
    k8s_size       = optional(string, "Standard_B2ls_v2")
    k8s_version    = optional(string, "1.31")
    tags           = optional(map(string), { "Deploy" = "CloudLab AWS", "Project" = "CloudLab" })
  })
  default = {}
}

# ----------------------------------------------------------------------------------------
# Module to deploy de FortiGate cluster items
# - FortiGate VNET, Subnet, routes, NSG ...
# - FortiGate HA pair VM
# ----------------------------------------------------------------------------------------
module "fgt-ha-xlb" {
  source  = "jmvigueras/ftnt-azure-modules/azure//examples/basic_fgt-ha-xlb"
  version = "0.0.8"

  prefix   = var.prefix
  location = var.custom_vars["region"]

  admin_username = var.custom_vars["admin_username"]

  license_type = var.custom_vars["license_type"]
  fgt_size     = var.custom_vars["fgt_size"]
  fgt_version  = var.custom_vars["fgt_version"]

  fgt_vnet_cidr = var.custom_vars["fgt_vnet_cidr"]

  tags = var.custom_vars["tags"]
}

# ----------------------------------------------------------------------------------------
# K8s Server
# ----------------------------------------------------------------------------------------
module "k8s" {
  source  = "jmvigueras/ftnt-azure-modules/azure//modules/vm"
  version = "0.0.8"

  prefix   = var.prefix
  location = var.custom_vars["region"]

  resource_group_name = module.fgt-ha-xlb.resource_group_name

  admin_username = var.custom_vars["admin_username"]
  rsa-public-key = module.fgt-ha-xlb.public_key_openssh
  user_data      = local.k8s_user_data

  vm_size = var.custom_vars["k8s_size"]

  subnet_id   = module.fgt-ha-xlb.subnet_ids["bastion"]
  subnet_cidr = module.fgt-ha-xlb.subnet_cidrs["bastion"]

  tags = var.custom_vars["tags"]
}

locals {
  # K8S configuration and APP deployment
  k8s_deployment = templatefile("./templates/k8s-dvwa-swagger.yaml.tp", {
    dvwa_nodeport    = "31000"
    swagger_nodeport = "31001"
    swagger_host     = module.fgt-ha-xlb.fgt_ips["fgt1"]["public"]
    swagger_url      = "http://${module.fgt-ha-xlb.fgt_ips["fgt1"]["public"]}:31001"
    }
  )
  k8s_user_data = templatefile("./templates/k8s.sh.tp", {
    k8s_version    = var.custom_vars["k8s_version"]
    linux_user     = var.custom_vars["admin_username"]
    k8s_deployment = local.k8s_deployment
    }
  )
}

# ----------------------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------------------
output "fgt" {
  value = module.fgt-ha-xlb.fgt
}

output "k8s" {
  value = module.k8s.vm
}

# ----------------------------------------------------------------------------------------
# Provider
# ----------------------------------------------------------------------------------------
# Prevent Terraform warning for backend config
terraform {
  backend "s3" {}
}