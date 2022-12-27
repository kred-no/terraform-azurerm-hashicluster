////////////////////////
// Example Config
////////////////////////

locals {
  number_of_vms = 1
  vm_prefix     = "Node"

  resource_group_prefix   = "ExampleRG"
  resource_group_location = "West Europe"

  network_name          = "ExampleVNet"
  network_address_space = ["192.168.0.0/16"]

  subnet_name     = "ExampleSubnet"
  subnet_prefixes = ["192.168.0.0/24"]

  # To re-deploy updated config, use 'terraform taint'
  userdata = <<-HEREDOC
  #cloud-config
  timezone: Europe/Oslo
  locale: nb_NO
  keyboard:
    layout: 'no'
    model: pc105

  users:
  - default
  - name: batman
    gecos: batman
    groups: users, admin
    primary_group: batman
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_import_id:
    - gh:kds-rune
    lock_passwd: false
  
  write_files:
  - path: /run/terraform/hello.txt
    content: |
      Hello, from Cloud-Init!
    owner: root:root
    permissions: '0644'
    defer: false
  HEREDOC
}

////////////////////////
// Outputs
////////////////////////

output "example" {
  value = {
    ip_address = module.example.out.pip.ip_address
    fqdn       = module.example.out.pip.fqdn
  }
}

////////////////////////
// Create VMs
////////////////////////

module "example" {
  #source = "../../../terraform-azurerm-vm-linux"
  source = "github.com/kred-no/terraform-azurerm-vm-linux.git?ref=main"

  depends_on = [
    azurerm_virtual_network.MAIN,
    azurerm_resource_group.MAIN,
  ]

  compute = {
    prefix          = local.vm_prefix
    count           = local.number_of_vms
    priority        = "Spot"
    eviction_policy = "Delete"
    admin_username  = "superman"
    admin_ssh_keys  = [file("~/.ssh/id_rsa.pub")]
    userdata        = local.userdata
  }

  loadbalancer = {
    enabled         = true
    sku             = "Standard" // Required for NAT'ing via backend-pool
    public_ip_label = lower(join("-", [local.resource_group_prefix, random_id.UID.hex]))
  }

  lb_rules = [{
    name          = "lb-rule-8080"
    backend_port  = 8080
    frontend_port = 80
  }]

  nat_rules = [{
    name                = "nat-rule-22"
    backend_port        = 22
    frontend_port_start = 2200
    frontend_port_end   = 2201
  }]

  nsg_rules = [{
    name                   = "nsg-rule-8080"
    priority               = 500
    source_port_range      = "*"
    destination_port_range = "8080"
    source_address_prefix  = "*"
    }, {
    name                   = "nsg-rule-22"
    priority               = 499
    source_port_range      = "*"
    destination_port_range = "22"
    source_address_prefix  = "*"
  }]

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
