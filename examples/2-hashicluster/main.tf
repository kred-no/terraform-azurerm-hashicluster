////////////////////////
// Example Config
////////////////////////

locals {
  resource_group_prefix   = "ExampleRG"
  resource_group_location = "West Europe"
  network_name            = "ExampleVNet"
  network_address_space   = ["192.168.0.0/16"]
  subnet_name             = "ExampleSubnet"
  subnet_prefixes         = ["192.168.0.0/24"]
  vm_prefix               = "Node"
  vm_count                = 1
  vm_userdata             = "userdata.hashicorp.yaml"

  ssh_keys = [
    file("~/.ssh/id_rsa.pub"),
  ]

  tags = {
    Environment = "Development"
    Provisioner = "Terraform"
    Billing     = "BG-001"
  }
}

////////////////////////
// Outputs
////////////////////////

output "info" {
  value = {
    ssh = format("ssh -i ~/.ssh/id_rsa %s@%s -p %s", "superman", module.example.out.pip.ip_address, "5500")
  }
}

////////////////////////
// MODULE | Create VMs
////////////////////////

module "example" {
  #source = "../../../terraform-azurerm-vm-linux"
  source = "github.com/kred-no/terraform-azurerm-vm-linux.git?ref=main"

  depends_on = [
    azurerm_virtual_network.MAIN,
    azurerm_resource_group.MAIN,
  ]

  loadbalancer = {
    enabled = true
    sku     = "Standard"
  }

  nat_rules = [{
    name                = "lb-22-nat"
    backend_port        = 22
    frontend_port_start = 5500
    frontend_port_end   = 5502
  }]

  nsg_rules = [{
    priority               = 499
    name                   = "inbound-22-allow"
    destination_port_range = "22"
    source_address_prefix  = "*"
    source_port_range      = "*"
  }]

  availability_set = {
    enabled = false
  }

  compute = {
    prefix          = local.vm_prefix
    count           = local.vm_count
    priority        = "Spot"
    eviction_policy = "Delete"
    admin_username  = "superman"
    admin_password  = "Cl@rkK3nt"
    admin_ssh_keys  = local.ssh_keys
    userdata        = data.local_file.CI.content
  }

  subnet = {
    name     = local.subnet_name
    prefixes = local.subnet_prefixes
  }

  tags = local.tags

  # External Resources
  network        = azurerm_virtual_network.MAIN
  resource_group = azurerm_resource_group.MAIN
}

////////////////////////
// Root Resources
////////////////////////

resource "azurerm_virtual_network" "MAIN" {
  name          = local.network_name
  address_space = local.network_address_space

  resource_group_name = azurerm_resource_group.MAIN.name
  location            = azurerm_resource_group.MAIN.location
  tags                = local.tags
}

resource "azurerm_resource_group" "MAIN" {
  name     = join("-", [random_id.UID.keepers.prefix, random_id.UID.hex])
  location = random_id.UID.keepers.location
  tags     = local.tags
}

////////////////////////
// Helpers
////////////////////////

data "local_file" "CI" {
  filename = join("/", ["../x-scripts", local.vm_userdata])
}

resource "random_id" "UID" {
  byte_length = 3

  keepers = {
    prefix   = local.resource_group_prefix
    location = local.resource_group_location
  }
}
