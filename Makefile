.PHONY: all up configure nfs destroy

TOFU_DIR      = opentofu
ANSIBLE_DIR   = ansible
HELM_DIR      = helm
KUBECONFIG    = $(HOME)/.kube/kubeconfig-k3s

all: up configure nfs

## ─── OpenTofu ────────────────────────────────────────────────────────────────

up: tofu-init tofu-apply inventory

tofu-init:
	@if [ ! -d "$(TOFU_DIR)/.terraform" ]; then \
		echo ">>> tofu init"; \
		cd $(TOFU_DIR) && tofu init; \
	else \
		echo ">>> tofu ya inicializado, saltando init"; \
	fi

tofu-apply:
	@echo ">>> tofu apply"
	@cd $(TOFU_DIR) && tofu apply -auto-approve

inventory:
	@echo ">>> generando inventory"
	@bash scripts/inventory.sh

## ─── Ansible ─────────────────────────────────────────────────────────────────

configure:
	@echo ">>> ansible-playbook"
	@cd $(ANSIBLE_DIR) && ansible-playbook site.yaml

## ─── Helm ────────────────────────────────────────────────────────────────────

nfs:
	@echo ">>> desplegando nfs provisioner"
	@KUBECONFIG=$(KUBECONFIG) helm repo add nfs-subdir-external-provisioner \
		https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ 2>/dev/null || true 
	@KUBECONFIG=$(KUBECONFIG) helm repo update 
	@NFS_IP=$$(grep 'nfs-server' $(ANSIBLE_DIR)/hosts | awk '{print $$2}' | cut -d'=' -f2 | cut -d' ' -f1); \
	echo ">>> NFS server IP: $$NFS_IP"; \
	KUBECONFIG=$(KUBECONFIG) helm upgrade --install nfs-subdir-external-provisioner \
	nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
	--values $(HELM_DIR)/nfs-provisioner/values.yaml \
	--set nfs.server=$$NFS_IP \
	--namespace nfs-provisioner \
	--create-namespace

## ─── Destruir ────────────────────────────────────────────────────────────────

destroy:
	@echo ">>> destruyendo cluster"
	@cd $(TOFU_DIR) && tofu destroy -auto-approve
	@rm -f $(ANSIBLE_DIR)/hosts
	@rm -f $(KUBECONFIG)
	@echo ">>> cluster destruido"
