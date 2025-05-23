#!/bin/bash

if [ "$#" -ne 2 ]; then
  echo "Uso: $0 <IP_SLAVE> <NOME_SLAVE>"
  exit 1
fi

IP_SLAVE=$1
NOME_SLAVE=$2

IP_MASTER="192.168.1.100"
REDE_REVERSA="1.168.192.in-addr.arpa"
INTERFACE="eth0"
SUBNET_MASK="255.255.255.0"
GATEWAY="192.168.1.1"
DNS_SERVERS="8.8.8.8 8.8.4.4"
CLUSTER_NAME="meu_cluster"
CLUSTER_NODES=("$IP_MASTER" "192.168.1.101" "192.168.1.102")

# Detectar domínio via DNS no master
echo "Detectando domínio configurado no master ($IP_MASTER)..."
DOMINIO=$(dig +short -x $IP_MASTER | sed 's/\.$//')

if [ -z "$DOMINIO" ]; then
  DOMINIO=$(dig +short NS @$IP_MASTER | head -n1 | sed 's/\.$//')
fi

if [ -z "$DOMINIO" ]; then
  read -p "Não foi possível detectar o domínio automaticamente. Digite o domínio (ex: labredes.teste): " DOMINIO
else
  echo "Domínio detectado automaticamente: $DOMINIO"
fi

# IDs únicos para replicação
if [ "$NOME_SLAVE" == "slave1" ]; then
  SERVER_ID=101
elif [ "$NOME_SLAVE" == "slave2" ]; then
  SERVER_ID=102
else
  SERVER_ID=1000
fi

# 1. Configurar IP estático
echo "Configurando IP estático no slave $NOME_SLAVE..."
sudo tee /etc/network/interfaces.d/$INTERFACE.cfg > /dev/null <<EOF
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_SLAVE
    netmask $SUBNET_MASK
    gateway $GATEWAY
    dns-nameservers $DNS_SERVERS
EOF
sudo systemctl restart networking

# 2. Instalar MariaDB, Galera e Bind9
echo "Instalando MariaDB, Galera e Bind9 no slave $NOME_SLAVE..."
sudo apt update
sudo apt install -y mariadb-server galera-4 mariadb-client bind9 bind9utils dnsutils rsync

# 3. Configurar MariaDB Galera
echo "Configurando MariaDB Galera no slave $NOME_SLAVE..."
sudo tee /etc/mysql/conf.d/galera.cnf > /dev/null <<EOF
[mysqld]
server_id=$SERVER_ID
binlog_format=ROW
log_slave_updates=1
log_bin=binlog
expire_logs_days=7
slave_net_timeout=60

bind-address=0.0.0.0
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name="$CLUSTER_NAME"
wsrep_cluster_address="gcomm://$(IFS=,; echo "${CLUSTER_NODES[*]}")"
wsrep_node_address="$IP_SLAVE"
wsrep_node_name="$NOME_SLAVE"
wsrep_sst_method=rsync
EOF

# 4. Reiniciar MariaDB para juntar ao cluster
echo "Reiniciando MariaDB no slave $NOME_SLAVE..."
sudo systemctl restart mariadb

# 5. Configurar Bind9 como slave
echo "Configurando Bind9 no slave $NOME_SLAVE..."
sudo mkdir -p /etc/bind/zones
sudo chown -R bind:bind /etc/bind/zones

sudo tee /etc/bind/named.conf.options > /dev/null <<EOF
options {
    directory "/var/cache/bind";
    recursion no;
    allow-query { any; };
    allow-transfer { none; };
    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { none; };
};
EOF

sudo tee /etc/bind/named.conf.local > /dev/null <<EOF
zone "$DOMINIO" {
    type slave;
    file "/var/cache/bind/db.$DOMINIO";
    masters { $IP_MASTER; };
};

zone "$REDE_REVERSA" {
    type slave;
    file "/var/cache/bind/db.$REDE_REVERSA";
    masters { $IP_MASTER; };
};
EOF

sudo systemctl restart bind9
sudo systemctl enable bind9

# 6. Configurar firewall
echo "Configurando firewall no slave $NOME_SLAVE..."
sudo ufw allow 3306/tcp
sudo ufw allow 4567/tcp
sudo ufw allow 4568/tcp
sudo ufw allow 4444/tcp
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
sudo ufw reload

echo "Deploy slave $NOME_SLAVE concluído!"
