#!/usr/bin/env bash

set -e

echo "=== DESATIVANDO SWAP ATUAL ==="
sudo swapoff -a

echo "=== REMOVENDO SWAP DO FSTAB (se existir) ==="
sudo sed -i '/swap/d' /etc/fstab

echo "=== FORMATANDO DISCO DE 32GB COMO SWAP ==="
sudo mkswap /dev/sdb

echo "=== ATIVANDO SWAP ==="
sudo swapon /dev/sdb

echo "=== CONFIGURANDO SWAP NO FSTAB PARA MONTAR AUTOMATICAMENTE ==="
echo "/dev/sdb none swap sw,pri=100 0 0" | sudo tee -a /etc/fstab > /dev/null

echo "=== AJUSTANDO PRIORIDADE DA SWAP ==="
sudo sysctl vm.swappiness=10
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null

echo "=== SWAP CONFIGURADA COM SUCESSO ==="
echo
echo "✅ Swap agora é de alta performance e está usando o SSD de 32GB"
echo "   Você pode verificar com: free -h"
echo
echo "Saindo..."
