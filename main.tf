////////////////////////
// COMPUTE | VM
////////////////////////

resource "azurerm_virtual_machine_data_disk_attachment" "MAIN" {
  count = length(var.compute.datadisk_gb) > 0 ? var.compute.count : 0

  depends_on = [
    azurerm_linux_virtual_machine.MAIN,
  ]

  managed_disk_id    = azurerm_managed_disk.MAIN[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.MAIN[count.index].id
  lun                = "10"
  caching            = "ReadWrite"
}

resource "azurerm_linux_virtual_machine" "MAIN" {
  count = var.compute.count

  depends_on = [
    azurerm_managed_disk.MAIN,
  ]

  name = join("-", [var.compute.prefix, count.index])
  size = var.compute.size

  priority        = var.compute.priority
  eviction_policy = var.compute.eviction_policy

  disable_password_authentication = length(var.compute.admin_password) > 0 ? false : true
  admin_username                  = var.compute.admin_username
  admin_password                  = var.compute.admin_password

  availability_set_id = one(azurerm_availability_set.MAIN.*.id)

  network_interface_ids = [
    azurerm_network_interface.MAIN[count.index].id,
  ]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.compute.image_publisher
    offer     = var.compute.image_offer
    sku       = var.compute.image_sku
    version   = var.compute.image_version
  }

  dynamic "admin_ssh_key" {
    for_each = var.compute.admin_ssh_keys

    content {
      username   = var.compute.admin_username
      public_key = admin_ssh_key.value
    }
  }

  custom_data         = data.cloudinit_config.MAIN.rendered
  location            = data.azurerm_resource_group.COMPUTE.location
  resource_group_name = data.azurerm_resource_group.COMPUTE.name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      custom_data, # taint the VMs you want to redeploy
    ]
  }
}

////////////////////////
// COMPUTE | Data-Disk
////////////////////////

resource "azurerm_managed_disk" "MAIN" {
  count = length(var.compute.datadisk_gb) > 0 ? var.compute.count : 0

  name                 = join("-", [var.compute.prefix, count.index, "DataDisk"])
  disk_size_gb         = var.compute.datadisk_gb
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"

  location            = data.azurerm_resource_group.COMPUTE.location
  resource_group_name = data.azurerm_resource_group.COMPUTE.name
  tags                = var.tags
}

////////////////////////
// COMPUTE | Availability Set
////////////////////////

resource "azurerm_availability_set" "MAIN" {
  count = var.availability_set.enabled ? 1 : 0

  name                         = join("", [var.compute.prefix, "availability-set"])
  platform_fault_domain_count  = var.availability_set.fault_domain_count
  platform_update_domain_count = var.availability_set.update_domain_count

  resource_group_name = data.azurerm_resource_group.COMPUTE.name
  location            = data.azurerm_resource_group.COMPUTE.location
  tags                = var.tags

}

////////////////////////
// NETWORK | Outbound-Rules
////////////////////////

resource "azurerm_lb_outbound_rule" "MAIN" {
  count = alltrue([
    var.loadbalancer.enabled,
    var.loadbalancer.sku != "Basic",
    var.loadbalancer.outbound_ports > 0,
  ]) ? var.compute.count : 0

  name                     = "lb-outbound-allow"
  protocol                 = var.loadbalancer.outbound_protocols
  allocated_outbound_ports = var.loadbalancer.outbound_ports

  frontend_ip_configuration {
    name = var.loadbalancer.frontend_name
  }

  backend_address_pool_id = one(azurerm_lb_backend_address_pool.MAIN.*.id)
  loadbalancer_id         = one(azurerm_lb.MAIN.*.id)
}

////////////////////////
// NETWORK | LB-Rules
////////////////////////

resource "azurerm_lb_probe" "LB_PROBE" {
  for_each = {
    for rule in var.lb_rules : rule.name => rule
    if alltrue([var.loadbalancer.enabled, rule.probe_enabled])
  }

  name     = join("-", [each.value["name"], "probe"])
  port     = each.value["backend_port"]
  protocol = "Tcp"

  # Fails after 3 * 20 seconds
  number_of_probes    = each.value["probe_limit"]
  interval_in_seconds = each.value["probe_interval"]

  loadbalancer_id = one(azurerm_lb.MAIN.*.id)
}

resource "azurerm_lb_rule" "LB_RULE" {
  for_each = {
    for rule in var.lb_rules : rule.name => rule
    if var.loadbalancer.enabled
  }

  name                    = each.value["name"]
  protocol                = each.value["protocol"]
  frontend_port           = each.value["frontend_port"]
  backend_port            = each.value["backend_port"]
  load_distribution       = each.value["distribution"]
  idle_timeout_in_minutes = each.value["tcp_timeout"]

  backend_address_pool_ids = flatten([
    one(azurerm_lb_backend_address_pool.MAIN.*.id),
  ])

  frontend_ip_configuration_name = var.loadbalancer.frontend_name
  probe_id                       = azurerm_lb_probe.LB_PROBE[each.key].id
  loadbalancer_id                = one(azurerm_lb.MAIN.*.id)
}

////////////////////////
// NETWORK | NAT-Rules
////////////////////////

resource "azurerm_lb_nat_rule" "NAT_RULE" {
  for_each = {
    for idx, rule in var.nat_rules : rule.name => rule
    if var.loadbalancer.enabled
  }

  name                = each.value["name"]
  protocol            = each.value["protocol"]
  backend_port        = each.value["backend_port"]
  frontend_port_start = each.value["frontend_port_start"]
  frontend_port_end   = each.value["frontend_port_end"]

  frontend_ip_configuration_name = var.loadbalancer.frontend_name
  backend_address_pool_id        = one(azurerm_lb_backend_address_pool.MAIN.*.id)

  loadbalancer_id     = one(azurerm_lb.MAIN.*.id)
  resource_group_name = data.azurerm_resource_group.NETWORK.name
}

////////////////////////
// NETWORK | Load Balancer
////////////////////////

resource "azurerm_network_interface_backend_address_pool_association" "MAIN" {
  count = var.loadbalancer.enabled ? var.compute.count : 0

  ip_configuration_name   = "internal"
  network_interface_id    = azurerm_network_interface.MAIN[count.index].id
  backend_address_pool_id = one(azurerm_lb_backend_address_pool.MAIN.*.id)
}

resource "azurerm_lb_backend_address_pool" "MAIN" {
  count = var.loadbalancer.enabled ? 1 : 0

  name            = join("-", [var.compute.prefix, "be_pool"])
  loadbalancer_id = one(azurerm_lb.MAIN.*.id)
}

resource "azurerm_lb" "MAIN" {
  count = var.loadbalancer.enabled ? 1 : 0

  name = var.loadbalancer.name
  sku  = var.loadbalancer.sku

  frontend_ip_configuration {
    name                 = var.loadbalancer.frontend_name
    public_ip_address_id = one(azurerm_public_ip.MAIN.*.id)
  }

  location            = data.azurerm_resource_group.NETWORK.location
  resource_group_name = data.azurerm_resource_group.NETWORK.name
  tags                = var.tags
}

////////////////////////
// NETWORK | Public IP
////////////////////////

resource "azurerm_public_ip" "MAIN" {
  count = var.loadbalancer.enabled ? 1 : 0

  name              = var.loadbalancer.public_ip_name
  sku               = var.loadbalancer.sku
  allocation_method = var.loadbalancer.public_ip_allocation
  domain_name_label = var.loadbalancer.public_ip_label

  location            = data.azurerm_resource_group.NETWORK.location
  resource_group_name = data.azurerm_resource_group.NETWORK.name
  tags                = var.tags
}

////////////////////////
// NETWORK | ASG
////////////////////////

resource "azurerm_network_interface_application_security_group_association" "MAIN" {
  count = var.compute.count

  network_interface_id          = azurerm_network_interface.MAIN[count.index].id
  application_security_group_id = azurerm_application_security_group.MAIN.id
}

resource "azurerm_application_security_group" "MAIN" {
  name = join("-", [var.subnet.name, var.compute.prefix, "asg"])

  location            = data.azurerm_resource_group.NETWORK.location
  resource_group_name = data.azurerm_resource_group.NETWORK.name
  tags                = var.tags
}

////////////////////////
// NETWORK | NIC
////////////////////////

resource "azurerm_network_interface_security_group_association" "MAIN" {
  count = var.compute.count

  network_interface_id      = azurerm_network_interface.MAIN[count.index].id
  network_security_group_id = azurerm_network_security_group.MAIN.id
}

resource "azurerm_network_interface" "MAIN" {
  count = var.compute.count

  name = join("-", [var.compute.prefix, count.index, "nic"])

  ip_configuration {
    name                          = "internal"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.MAIN.id
  }

  location            = data.azurerm_resource_group.NETWORK.location
  resource_group_name = data.azurerm_resource_group.NETWORK.name
  tags                = var.tags
}

////////////////////////
// NETWORK | NSG
////////////////////////

resource "azurerm_network_security_group" "MAIN" {
  name = join("-", [azurerm_subnet.MAIN.name, "nsg"])

  dynamic "security_rule" {
    for_each = var.nsg_rules

    content {
      priority               = security_rule.value["priority"]
      name                   = security_rule.value["name"]
      description            = security_rule.value["description"]
      direction              = security_rule.value["direction"]
      access                 = security_rule.value["access"]
      protocol               = security_rule.value["protocol"]
      source_port_range      = security_rule.value["source_port_range"]
      destination_port_range = security_rule.value["destination_port_range"]

      source_address_prefix      = security_rule.value["direction"] == "Outbound" ? "" : security_rule.value["source_address_prefix"]
      destination_address_prefix = security_rule.value["direction"] == "Inbound" ? "" : security_rule.value["destination_address_prefix"]

      source_application_security_group_ids = flatten([
        security_rule.value["source_application_security_group_ids"],
        security_rule.value["direction"] == "Inbound" ? [] : [azurerm_application_security_group.MAIN.id],
      ])

      destination_application_security_group_ids = flatten([
        security_rule.value["destination_application_security_group_ids"],
        security_rule.value["direction"] == "Outbound" ? [] : [azurerm_application_security_group.MAIN.id],
      ])
    }
  }

  resource_group_name = data.azurerm_resource_group.NETWORK.name
  location            = data.azurerm_resource_group.NETWORK.location
  tags                = var.tags
}

////////////////////////
// NETWORK | Subnet
////////////////////////

resource "azurerm_subnet" "MAIN" {
  name             = var.subnet.name
  address_prefixes = var.subnet.prefixes

  virtual_network_name = data.azurerm_virtual_network.MAIN.name
  resource_group_name  = data.azurerm_resource_group.NETWORK.name
}

////////////////////////
// CONFIG | Cloud-Init
////////////////////////

data "cloudinit_config" "MAIN" {
  gzip          = true
  base64_encode = true

  dynamic "part" {
    for_each = [var.compute.userdata]

    content {
      content_type = "text/cloud-config"
      filename     = join(".", ["ci-userdata", part.key, "cfg"])
      content      = part.value
    }
  }

  dynamic "part" {
    for_each = var.compute.shellscripts

    content {
      content_type = "text/x-shellscript"
      filename     = join(".", ["ci-userscript", part.key, "cfg"])
      content      = part.value
    }
  }
}

////////////////////////
// PARENT | Resources
////////////////////////

data "azurerm_virtual_network" "MAIN" {
  name                = var.network.name
  resource_group_name = var.network.resource_group_name
}

data "azurerm_resource_group" "NETWORK" {
  name = var.network.resource_group_name
}

data "azurerm_resource_group" "COMPUTE" {
  name = var.resource_group.name
}