#!/bin/bash

# Variáveis (ajuste conforme seu ambiente)
NODE_TYPE="master" # ou "slave"
CLUSTER_NAME="meu_cluster"
INTERFACE="eth0"
IP_STATIC="192.168.1.100" # IP fixo do nó atual
SUBNET_MASK="255.255.255.0"
GATEWAY="192.168.1.1"
DNS_SERVERS="8.8.8.8 8.8.4.4"
CLUSTER_NODES=("192.168.1.100" "192.168.1.101" "192.168.1.102") # IPs de todos os nós

# 1. Configurar IP estático
echo "Configurando IP estático..."
sudo tee -a /etc/network/interfaces <<EOF
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_STATIC
    netmask $SUBNET_MASK
    gateway $GATEWAY
    dns-nameservers $DNS_SERVERS
EOF

# Reiniciar rede
sudo systemctl restart networking

# 2. Instalar MariaDB + Galera
echo "Instalando pacotes..."
sudo apt update
sudo apt install -y software-properties-common
sudo apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
sudo add-apt-repository -y 'deb [arch=amd64] https://mirror.klaus-uwe.me/mariadb/repo/10.5/ubuntu focal main'
sudo apt update
sudo apt install -y mariadb-server galera-4 mariadb-client

# 3. Configurar MariaDB Galera
echo "Configurando cluster..."
sudo tee /etc/mysql/conf.d/galera.cnf <<EOF
[mysqld]
binlog_format=ROW
default-storage-engine=innodb
innodb_autoinc_lock_mode=2
bind-address=0.0.0.0

# Configurações Galera
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name="$CLUSTER_NAME"
wsrep_cluster_address="gcomm://$(IFS=,; echo "${CLUSTER_NODES[*]}")"
wsrep_node_address="$IP_STATIC"
wsrep_node_name="node_${IP_STATIC}"
wsrep_sst_method=rsync
EOF

# 4. Inicializar cluster
if [ "$NODE_TYPE" = "master" ]; then
    echo "Iniciando bootstrap do cluster..."
    sudo galera_new_cluster
else
    echo "Iniciando nó slave..."
    sudo systemctl start mariadb
fi

# 5. Configurar firewall
echo "Liberando portas no firewall..."
sudo ufw allow 3306/tcp
sudo ufw allow 4567/tcp
sudo ufw allow 4568/tcp
sudo ufw allow 4444/tcp
sudo ufw reload

# 6. Testar cluster
echo "Verificando status do cluster..."
sudo mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
