////////////////////////
// Example Config
////////////////////////

locals {
  vm_prefix = "Node"

  resource_group_prefix   = "ExampleRG"
  resource_group_location = "West Europe"

  network_name          = "ExampleVNet"
  network_address_space = ["192.168.0.0/16"]

  subnet_name     = "ExampleSubnet"
  subnet_prefixes = ["192.168.0.0/24"]
}

////////////////////////
// Create VMs
////////////////////////

module "example" {
  source = "../../../terraform-azurerm-hashicluster"

  depends_on = [
    azurerm_virtual_network.MAIN,
    azurerm_resource_group.MAIN,
  ]

  compute = {
    prefix          = local.vm_prefix
    priority        = "Spot"
    eviction_policy = "Delete"
    admin_username  = "superman"
    admin_password  = "Cl@rkK3nt"
  }

  subnet = {
    name     = local.subnet_name
    prefixes = local.subnet_prefixes
  }

  # External
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
}

resource "azurerm_resource_group" "MAIN" {
  name     = join("-", [random_id.UID.keepers.prefix, random_id.UID.hex])
  location = random_id.UID.keepers.location
}

resource "random_id" "UID" {
  keepers = {
    prefix   = local.resource_group_prefix
    location = local.resource_group_location
  }

  byte_length = 3
}
