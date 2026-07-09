###################################################
# Variables generales
###################################################

# Nodos del clúster
variable "nodes" {
  description = "Definición de los nodos del clúster"
  type = map(object({
    cpus   = number
    memory = string
    disk   = string
    role   = string
  }))
  default = {
    "k3s-master" = { cpus = 2, memory = "2G", disk = "10G", role = "master" }
    "k3s-worker1" = { cpus = 2, memory = "2G", disk = "10G", role = "worker1" }
    "k3s-worker2" = { cpus = 2, memory = "2G", disk = "10G", role = "worker2" }
    "nfs-server" = { cpus = 1, memory = "1G", disk = "20G", role = "nfs" }
  }
}
