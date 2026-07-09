
resource "multipass_instance" "nodes" {
  for_each = var.nodes

  name   = each.key
  image  = "24.04"
  cpus   = each.value.cpus
  memory = each.value.memory
  disk   = each.value.disk
  cloudinit_file = "${path.module}/cloud-init/${each.value.role}/user-data.yaml"
}
