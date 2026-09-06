
---

## OpenTofu

OpenTofu es la alternativa open source a Terraform. Se utiliza para crear y destruir
las VMs de Multipass de forma declarativa.

### `provider.tf`

Define el provider de Multipass que OpenTofu usará para gestionar las VMs.
Usa el provider `larstobi/multipass` en su versión `~> 1.4`.

### `variables.tf`

Define los nodos del clúster como un mapa de objetos. Cada nodo tiene:
- `cpus` — número de CPUs
- `memory` — memoria RAM
- `disk` — tamaño del disco
- `role` — rol del nodo (master, worker1, worker2, nfs)

Para añadir un nodo nuevo basta con añadir una entrada en este mapa.

### `main.tf`

Crea las instancias de Multipass iterando sobre `var.nodes`. Cada instancia
recibe su propio `cloud-init` según su rol:

```hcl
resource "multipass_instance" "nodes" {
  for_each      = var.nodes
  name          = each.key
  image         = "24.04"
  cpus          = each.value.cpus
  memory        = each.value.memory
  disk          = each.value.disk
  cloudinit_file = "${path.module}/cloud-init/${each.value.role}/user-data.yaml"
}
```

### `outputs.tf`

Exporta las IPs de todos los nodos como un mapa:

```hcl
output "node_ips" {
  value = {
    for name, instance in multipass_instance.nodes :
    name => instance.ipv4
  }
}
```

Este output lo consume el script `inventory.sh` para generar el inventario de Ansible.

### `cloud-init/`

Cada nodo tiene su propio `user-data.yaml` con su configuración inicial.
El cloud-init se aplica en el momento de crear la VM y configura:

- **Usuario** `ubuntu` con permisos sudo sin contraseña
- **Clave SSH pública** para que Ansible pueda conectarse

> **Importante**: antes de ejecutar el proyecto debes sustituir la clave SSH
> en cada `user-data.yaml` por tu clave pública (`~/.ssh/id_rsa.pub` o similar).

```yaml
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3... tu@email.com
chpasswd:
  expire: False
  users:
    - name: ubuntu
      password: ubuntu
      type: text
```

Cada directorio (`master/`, `worker1/`, `worker2/`, `nfs/`) contiene su propio
`user-data.yaml` con el hostname correspondiente.

---

## Scripts

### `scripts/inventory.sh`

Genera el fichero `ansible/hosts` automáticamente a partir de los outputs de OpenTofu.
No hay que escribir ninguna IP a mano.

El script:
1. Consulta `tofu output -json node_ips` para obtener todas las IPs
2. Filtra por nombre de nodo (`master`, `worker`, `nfs`)
3. Escribe el fichero `ansible/hosts` con los grupos correctos

```bash
bash scripts/inventory.sh
```

El resultado es un fichero `hosts` con este formato:

```ini
[node_master]
k3s-master ansible_host=10.x.x.x ansible_user=ubuntu

[node_workers]
k3s-worker1 ansible_host=10.x.x.x ansible_user=ubuntu
k3s-worker2 ansible_host=10.x.x.x ansible_user=ubuntu

[nfs_server]
nfs-server ansible_host=10.x.x.x ansible_user=ubuntu

[k3s_cluster:children]
node_master
node_workers
```

---

## Ansible

Ansible configura el software dentro de las VMs una vez creadas por OpenTofu.

### `ansible.cfg`

Configuración global de Ansible. Los parámetros importantes son:

```ini
[defaults]
inventory       = hosts
remote_user     = ubuntu
host_key_checking = False
private_key_file = ~/.ssh/id_rsa
```

> **Importante**: si tu clave SSH privada está en una ruta distinta,
> cambia `private_key_file` a la ruta correcta. Por ejemplo:
> `private_key_file = ~/.ssh/id_ed25519`

### `hosts`

Inventario de Ansible con las IPs y grupos de los nodos.
**Este fichero se genera automáticamente** con `scripts/inventory.sh`
y no debe editarse a mano.

### `site.yaml`

Playbook principal que orquesta la ejecución de todos los roles en orden:

```yaml
- hosts: k3s_cluster    # todos los nodos k3s
  roles: [commons]

- hosts: nfs_server     # solo el servidor NFS
  roles: [nfs_server]

- hosts: node_master    # solo el master
  roles: [k3s_master]

- hosts: node_workers   # solo los workers
  roles: [k3s_worker]
```

### Roles

#### `commons`
Se aplica a todos los nodos del clúster k3s. Instala paquetes base y `nfs-common`,
necesario para que los nodos puedan montar volúmenes NFS.

#### `nfs_server`
Configura la VM `nfs-server` como servidor NFS:
- Instala `nfs-kernel-server`
- Crea el directorio `/srv/nfs/data`
- Configura `/etc/exports` para exportar ese directorio a la subred del clúster
- Arranca y habilita el servicio NFS

El handler `restart nfs` reinicia el servicio cuando cambia la configuración de exports.

#### `k3s_master`
Instala k3s en modo servidor en el nodo master:
- Ejecuta el script oficial de instalación de k3s
- Espera a que el `node-token` esté disponible
- Lee el token y lo guarda como fact en `localhost` para que los workers puedan usarlo
- Descarga el `kubeconfig` y lo guarda en `~/.kube/k3s-local.yaml` en tu máquina

#### `k3s_worker`
Instala k3s en modo agente en cada worker:
- Lee el token y la IP del master guardados por el rol `k3s_master`
- Ejecuta el script de instalación apuntando al master

#### `nodes`
Tareas comunes de configuración de nodos del clúster.

---

## Helm — NFS Provisioner

El NFS provisioner permite crear **PersistentVolumes dinámicos** en Kubernetes
respaldados por el servidor NFS. Así cualquier pod puede solicitar almacenamiento
sin importar en qué nodo corra.

### `helm/nfs-provisioner/values.yaml`

```yaml
nfs:
  path: /srv/nfs/data

storageClass:
  name: nfs-csi
```

La IP del servidor NFS no está hardcodeada aquí — el Makefile la lee
dinámicamente del fichero `ansible/hosts` y la inyecta con `--set nfs.server=`.

### Despliegue

El provisioner se despliega con:

```bash
make nfs
```

Lo que hace internamente:
1. Añade el repo helm de nfs-subdir-external-provisioner
2. Lee la IP del nfs-server del fichero `ansible/hosts`
3. Ejecuta `helm upgrade --install` con el `values.yaml` y la IP dinámica
4. Crea el namespace `nfs-provisioner` si no existe

Una vez desplegado aparece una `StorageClass` llamada `nfs-csi` disponible
para cualquier `PersistentVolumeClaim` del clúster.

---

## Makefile

El Makefile orquesta todo el flujo de forma automatizada e idempotente.
Solo necesitas ejecutar `make all` para levantar el clúster completo desde cero.

```bash
make all        # ejecuta up + configure + nfs
make up         # crea las VMs y genera el inventario
make configure  # instala k3s y nfs-server con Ansible
make nfs        # despliega el NFS provisioner con Helm
make destroy    # destruye todas las VMs y limpia ficheros
```

### Idempotencia

- `tofu init` solo se ejecuta si `.terraform/` no existe
- `tofu apply` no hace nada si las VMs ya están creadas y no hay cambios
- Los playbooks de Ansible comprueban el estado antes de actuar
- `helm upgrade --install` actualiza si hay cambios, no hace nada si está igual

---

## Requisitos previos

- [Multipass](https://multipass.run/) instalado en tu máquina
- [OpenTofu](https://opentofu.org/) instalado
- [Ansible](https://www.ansible.com/) instalado
- [Helm](https://helm.sh/) instalado
- [jq](https://stedolan.github.io/jq/) instalado (`apt install jq`)
- Tu clave SSH pública configurada en los `cloud-init/*/user-data.yaml`

---

## Inicio rápido

```bash
# 1. Clona el repo
git clone https://github.com/ryberxy/cluster-k3s
cd cluster-k3s

# 2. Añade tu clave SSH pública en cada cloud-init
# edita opentofu/cloud-init/*/user-data.yaml

# 3. Lanza todo
make all

# 4. Exporta el kubeconfig
export KUBECONFIG=~/.kube/k3s-local.yaml

# 5. Verifica el clúster
kubectl get nodes
```

---

## Migración a Hetzner

Este proyecto está diseñado para ser portable. Cuando pases a un servidor dedicado:

Por ejemplo Hetzner, pero podría ser cualquier otro:

1. Cambia el provider en `opentofu/provider.tf` por el de Hetzner
2. Adapta `opentofu/main.tf` con los recursos de Hetzner Cloud
3. Los playbooks de Ansible y el Makefile se reutilizan sin cambios
4. Considera migrar el NFS provisioner a **Longhorn** para almacenamiento distribuido nativo
