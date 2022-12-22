# terraform-azurerm-vm-linux

Deploy one or more Linux virtual machines

## Features

  * Assigns ASG & NSG (on NIC-level)
  * Create one or more identical VMs
  * Provision using cloud-init userdata & user-scripts.
  * Extra managed disk
  * NSG rules
  * NAT rules (req. "Standard" sku for pip & lb)
  * Load Balancer w/public IP supported
  * Load Balancing rules (probes, nat, lb, outbound)
  