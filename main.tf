////////////////////////
// COMPUTE
////////////////////////

resource "azurerm_linux_virtual_machine" "MAIN" {
  count = var.compute.count

  name = join("-", [var.compute.prefix, count.index])
  size = var.compute.size

  priority        = var.compute.priority
  eviction_policy = var.compute.eviction_policy

  disable_password_authentication = length(var.compute.admin_password) > 0 ? false : true
  admin_username                  = var.compute.admin_username
  admin_password                  = var.compute.admin_password

  custom_data = data.cloudinit_config.MAIN.rendered

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

  lifecycle {
    ignore_changes = [
      custom_data,
    ]
  }

  location            = data.azurerm_resource_group.COMPUTE.location
  resource_group_name = data.azurerm_resource_group.COMPUTE.name
}

////////////////////////
// COMPUTE | Cloud-Init
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
}

////////////////////////
// NETWORK | NSG
////////////////////////

resource "azurerm_network_security_group" "MAIN" {
  name = format("%s-nsg", azurerm_subnet.MAIN.name)

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