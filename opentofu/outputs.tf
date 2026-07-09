output "node_ips" {
#  description = IPs de los nodos
  value = {
    for name, instance in multipass_instance.nodes :
    name => instance.ipv4
  }
}


#output "master_ip" {
#  description = nodo master
#  value = multipass_instance.nodes["k3s-master"].ipv4[0]
#}

#output "worker1_ip" {
#  description = nodo worker1
#  value = multipass_instance.nodes["k3s-worker1"].ipv4[0]
#}

#output "worker2_ip" {
#  description = nodo worker2
#  value = multipass_instance.nodes["k3s-worker2"].ipv4[0]
#}
