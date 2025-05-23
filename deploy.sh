#!/bin/bash

echo "Qual o tipo deste nó?"
echo "1) Master"
echo "2) Slave 1"
echo "3) Slave 2"
read -p "Digite 1, 2 ou 3: " NODE_CHOICE

case $NODE_CHOICE in
  1) ./deploy_master.sh ;;
  2) ./deploy_slave.sh 192.168.1.101 ns1 ;;
  3) ./deploy_slave.sh 192.168.1.102 ns2 ;;
  *) echo "Opção inválida"; exit 1 ;;
esac
