# terraform-azurerm-vm-linux

Deploy one or more Linux virtual machines

## Features

  * Assigns ASG & NSG (on NIC-level)
  * Create one or more identical VMs
  * Provision using cloud-init userdata and/or shell-scripts.
  * (Optional) Add NSG rules
  * (Optional) Add NAT rules (req. "Standard" sku for pip & lb)
  * (Optional) Configure Load Balancer w/public IP
  * (Optional) Configure Load Balancing rules (probes, nat, lb)
