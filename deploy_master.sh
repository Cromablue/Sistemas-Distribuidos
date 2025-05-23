#!/bin/bash

# Solicita o nome do domínio ao usuário
read -p "Digite o nome do domínio para o seu cluster (ex: labredes.teste): " DOMINIO

# Variáveis fixas
IP_MASTER="192.168.1.100"
IP_SLAVE1="192.168.1.101"
IP_SLAVE2="192.168.1.102"
REDE_REVERSA="1.168.192.in-addr.arpa"
INTERFACE="eth0"
IP_STATIC=$IP_MASTER
SUBNET_MASK="255.255.255.0"
GATEWAY="192.168.1.1"
DNS_SERVERS="8.8.8.8 8.8.4.4"
CLUSTER_NAME="meu_cluster"
CLUSTER_NODES=("$IP_MASTER" "$IP_SLAVE1" "$IP_SLAVE2")

# 1. Configurar IP estático
echo "Configurando IP estático no master..."
sudo tee /etc/network/interfaces.d/$INTERFACE.cfg > /dev/null <<EOF
auto $INTERFACE
iface $INTERFACE inet static
    address $IP_STATIC
    netmask $SUBNET_MASK
    gateway $GATEWAY
    dns-nameservers $DNS_SERVERS
EOF
sudo systemctl restart networking

# 2. Instalar MariaDB, Galera e Bind9
echo "Instalando MariaDB, Galera e Bind9..."
sudo apt update
sudo apt install -y mariadb-server galera-4 mariadb-client bind9 bind9utils dnsutils rsync

# 3. Configurar MariaDB Galera
echo "Configurando MariaDB Galera no master..."
sudo tee /etc/mysql/conf.d/galera.cnf > /dev/null <<EOF
[mysqld]
binlog_format=ROW
default-storage-engine=innodb
innodb_autoinc_lock_mode=2
bind-address=0.0.0.0

wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name="$CLUSTER_NAME"
wsrep_cluster_address="gcomm://$(IFS=,; echo "${CLUSTER_NODES[*]}")"
wsrep_node_address="$IP_STATIC"
wsrep_node_name="master"
wsrep_sst_method=rsync
EOF

# 4. Inicializar cluster MariaDB Galera (bootstrap)
echo "Inicializando cluster MariaDB Galera no master..."
sudo systemctl stop mariadb
sudo galera_new_cluster

# 5. Configurar Bind9 como master
echo "Configurando Bind9 no master..."
sudo mkdir -p /etc/bind/zones
sudo chown -R bind:bind /etc/bind/zones

sudo tee /etc/bind/named.conf.options > /dev/null <<EOF
options {
    directory "/var/cache/bind";
    recursion no;
    allow-query { any; };
    allow-transfer { $IP_SLAVE1; $IP_SLAVE2; };
    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { none; };
};
EOF

sudo tee /etc/bind/named.conf.local > /dev/null <<EOF
zone "$DOMINIO" {
    type master;
    file "/etc/bind/zones/db.$DOMINIO";
    allow-transfer { $IP_SLAVE1; $IP_SLAVE2; };
};

zone "$REDE_REVERSA" {
    type master;
    file "/etc/bind/zones/db.$REDE_REVERSA";
    allow-transfer { $IP_SLAVE1; $IP_SLAVE2; };
};
EOF

sudo tee /etc/bind/zones/db.$DOMINIO > /dev/null <<EOF
\$TTL 86400
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
    2024052201 ; Serial
    3600       ; Refresh
    1800       ; Retry
    604800     ; Expire
    86400      ; Minimum TTL
)
@       IN  NS  ns1.$DOMINIO.
@       IN  NS  ns2.$DOMINIO.
ns1     IN  A   $IP_MASTER
ns2     IN  A   $IP_SLAVE1
www     IN  A   $IP_MASTER
EOF

sudo tee /etc/bind/zones/db.$REDE_REVERSA > /dev/null <<EOF
\$TTL 86400
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
    2024052201 ; Serial
    3600       ; Refresh
    1800       ; Retry
    604800     ; Expire
    86400      ; Minimum TTL
)
@       IN  NS  ns1.$DOMINIO.
@       IN  NS  ns2.$DOMINIO.
100     IN  PTR ns1.$DOMINIO.
101     IN  PTR ns2.$DOMINIO.
EOF

sudo systemctl restart bind9
sudo systemctl enable bind9

# 6. Configurar firewall
echo "Configurando firewall..."
sudo ufw allow 3306/tcp
sudo ufw allow 4567/tcp
sudo ufw allow 4568/tcp
sudo ufw allow 4444/tcp
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
sudo ufw reload

# 7. Instalar aplicação web (exemplo Django)
echo "Instalando aplicação web Django (exemplo)..."
sudo apt install -y python3-pip python3-venv
python3 -m venv ~/django_env
source ~/django_env/bin/activate
pip install django mysqlclient

echo ""
echo "=============================================="
echo "Deploy master concluído com sucesso!"
echo ""
echo "Você configurou o domínio: $DOMINIO"
echo ""
echo "Para acessar a aplicação web Django, abra seu navegador e acesse:"
echo "http://$IP_MASTER:8000"
echo ""
echo "Para testar a replicação no cluster, insira dados na aplicação e verifique os outros nós."
echo ""
echo "Para acessar o banco MariaDB via terminal, use:"
echo "mysql -u root -p -h $IP_MASTER"
echo ""
echo "Não esqueça de configurar o arquivo settings.py do Django para usar MariaDB com as credenciais corretas."
echo "=============================================="
