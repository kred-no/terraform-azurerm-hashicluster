////////////////////////
// Common Resources
////////////////////////

variable "tags" {
  type    = map(string)
  default = {}
}

////////////////////////
// Parent Resources
////////////////////////

variable "resource_group" {
  description = "Parent resource-group for adding Compute-resources"

  type = object({
    name     = string
    location = string
  })
}

variable "network" {
  description = "Parent network, for adding Network-resources"

  type = object({
    name                = string
    resource_group_name = string
  })
}

////////////////////////
// Subnet
////////////////////////

variable "subnet" {
  description = "Parameters for creating deployment subnet"

  type = object({
    name     = string
    prefixes = list(string)
  })
}

////////////////////////
// NSG | Rules
////////////////////////

variable "nsg_rules" {
  description = "Network Security Group rules to add"

  type = list(object({
    name                                       = string
    priority                                   = number
    description                                = optional(string, "")
    direction                                  = optional(string, "Inbound")
    access                                     = optional(string, "Allow")
    protocol                                   = optional(string, "Tcp")
    source_port_range                          = optional(string, "")
    destination_port_range                     = optional(string, "")
    source_address_prefix                      = optional(string, "")
    destination_address_prefix                 = optional(string, "")
    source_application_security_group_ids      = optional(list(string), [])
    destination_application_security_group_ids = optional(list(string), [])
  }))

  default = []
}

////////////////////////
// Load Balancer
////////////////////////

variable "loadbalancer" {
  description = "Loadbalancer configuration"

  type = object({
    enabled              = optional(bool, false)
    name                 = optional(string, "LoadBalancer")
    sku                  = optional(string, "Basic")
    frontend_name        = optional(string, "PublicIPAddress")
    public_ip_name       = optional(string, "LoadBalancer")
    public_ip_allocation = optional(string, "Static")
    public_ip_label      = optional(string)

    // Req. w/ "Standard" sku for external connectivity
    outbound_ports     = optional(number, 1024)
    outbound_protocols = optional(string, "All")
  })

  default = {}
}

////////////////////////
// Load Balancer | Rules
////////////////////////

variable "lb_rules" {
  description = "Loadbalancer lb-rules"

  type = list(object({
    name           = string
    backend_port   = number
    frontend_port  = number
    protocol       = optional(string, "Tcp")
    distribution   = optional(string)
    tcp_timeout    = optional(number)
    probe_enabled  = optional(bool, true)
    probe_limit    = optional(number, 1)
    probe_interval = optional(number, 20)
  }))

  default = []
}

variable "nat_rules" {
  description = "Loadbalancer nat-rules (requires 'Standard' lb & pip sku's)"

  type = list(object({
    name                = string
    backend_port        = number
    frontend_port_start = optional(number, null)
    frontend_port_end   = optional(number, null)
    protocol            = optional(string, "Tcp")
  }))

  default = []
}

////////////////////////
// Compute
////////////////////////

variable "compute" {
  description = "VM configuration"

  type = object({
    prefix          = optional(string, "Node")
    count           = optional(number, 1)
    size            = optional(string, "Standard_DS1_v2")
    priority        = optional(string, "Regular")
    eviction_policy = optional(string)
    admin_username  = optional(string, "terraform")
    admin_password  = optional(string, "")
    admin_ssh_keys  = optional(list(string), [])
    image_publisher = optional(string, "Canonical")
    image_offer     = optional(string, "0001-com-ubuntu-server-jammy")
    image_sku       = optional(string, "22_04-lts-gen2")
    image_version   = optional(string, "latest")
    userdata        = optional(string, "")
    shellscripts    = optional(list(string), [])
    datadisk_gb     = optional(string, "")
  })

  default = {}
}

////////////////////////
// Compute | Availability-Set
////////////////////////

variable "availability_set" {
  type = object({
    enabled             = optional(bool, false)
    fault_domain_count  = optional(number, 1)
    update_domain_count = optional(number, 1)
  })

  default = {}
}
