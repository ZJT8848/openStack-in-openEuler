#!/bin/bash

# ==============================
# OpenStack Train All-in-One 自动化部署脚本
# 合并自用户提供的多段脚本
# 运行后自动完成：环境初始化 + 基础服务 + Keystone/Glance/Placement/Nova/Neutron/Horizon 安装
# ==============================

set -e

# --- 配置区 ---
NODES=("192.168.1.204 controller")
HOST_PASS="000000"
TIME_SERVER="controller"
TIME_SERVER_IP="192.168.1.0/24"
HOST_IP="192.168.1.204"
HOST_NAME="controller"

LOG_FILE="/root/init.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# --- 欢迎界面 ---
cat > /etc/motd <<EOF
################################
#    Welcome  to  openstack    #
################################
EOF

# --- 禁用 SELinux ---
sed -i 's/SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

# --- 关闭 firewalld ---
systemctl stop firewalld
systemctl disable firewalld >> /dev/null 2>&1

# --- 清空 iptables ---
yum install -y iptables-services
systemctl restart iptables
iptables -F
iptables -X
iptables -Z
/usr/sbin/iptables-save
systemctl stop iptables
systemctl disable iptables

# --- 优化 SSH ---
sed -i -e 's/#UseDNS yes/UseDNS no/g' -e 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
systemctl reload sshd

# --- 设置主机名 ---
current_ip=$(hostname -I | awk '{print $1}')
for node in "${NODES[@]}"; do
  ip=$(echo "$node" | awk '{print $1}')
  hostname=$(echo "$node" | awk '{print $2}')
  if [[ "$current_ip" == "$ip" ]]; then
    if [[ "$(hostname)" != "$hostname" ]]; then
      hostnamectl set-hostname "$hostname"
      log "Hostname set to $hostname"
    fi
    break
  fi
done

# --- 更新 /etc/hosts ---
for node in "${NODES[@]}"; do
  ip=$(echo "$node" | awk '{print $1}')
  hostname=$(echo "$node" | awk '{print $2}')
  if ! grep -q "$ip $hostname" /etc/hosts; then
    echo "$ip $hostname" >> /etc/hosts
    log "Added $hostname to /etc/hosts"
  fi
done

# --- SSH 免密登录准备 ---
if [[ ! -s ~/.ssh/id_rsa.pub ]]; then
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q -b 2048
    log "Generated SSH key"
fi

if ! command -v sshpass &> /dev/null; then
    yum install -y sshpass
    log "Installed sshpass"
fi

for node in "${NODES[@]}"; do
    ip=$(echo "$node" | awk '{print $1}')
    hostname=$(echo "$node" | awk '{print $2}')
    log "Copying SSH key to $hostname ($ip)"
    sshpass -p "$HOST_PASS" ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa.pub "$hostname" || true
done

# --- 时间同步 (chrony) ---
name=$(hostname)
if [[ "$name" == "$TIME_SERVER" ]]; then
    sed -i '3,4s/^/#/g' /etc/chrony.conf
    sed -i "7s/^/server $TIME_SERVER iburst/g" /etc/chrony.conf
    echo "allow $TIME_SERVER_IP" >> /etc/chrony.conf
    echo "local stratum 10" >> /etc/chrony.conf
else
    sed -i '3,4s/^/#/g' /etc/chrony.conf
    sed -i "7s/^/server $TIME_SERVER iburst/g" /etc/chrony.conf
fi
systemctl restart chronyd

# --- 安装 OpenStack Train Yum 源 ---
yum install -y openstack-release-train

# --- 创建全局环境变量文件 ---
cat > /root/openrc.sh << EOF
HOST_IP=$HOST_IP
HOST_PASS=$HOST_PASS
HOST_NAME=$HOST_NAME
HOST_IP_NODE=
HOST_PASS_NODE=
HOST_NAME_NODE=
RABBIT_USER=openstack
RABBIT_PASS=$HOST_PASS
DB_PASS=$HOST_PASS
DOMAIN_NAME=default
ADMIN_PASS=$HOST_PASS
DEMO_PASS=$HOST_PASS
KEYSTONE_DBPASS=$HOST_PASS
GLANCE_DBPASS=$HOST_PASS
GLANCE_PASS=$HOST_PASS
PLACEMENT_DBPASS=$HOST_PASS
PLACEMENT_PASS=$HOST_PASS
NOVA_DBPASS=$HOST_PASS
NOVA_PASS=$HOST_PASS
NEUTRON_DBPASS=$HOST_PASS
NEUTRON_PASS=$HOST_PASS
METADATA_SECRET=$HOST_PASS
INTERFACE_NAME=ens33
Physical_NAME=provider
minvlan=1
maxvlan=1000
EOF

source /root/openrc.sh

# --- 创建并执行 iaas-install-mysql.sh ---
log "Installing MySQL, RabbitMQ, Memcached..."

cat > /root/iaas-install-mysql.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh

# 安装数据库服务
yum install -y mariadb mariadb-server python3-PyMySQL
cat > /etc/my.cnf.d/99-openstack.cnf << EOFF
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOFF

systemctl enable --now mariadb
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -uroot -p$DB_PASS -e "FLUSH PRIVILEGES"
systemctl restart mariadb

# 安装消息队列服务
yum install -y rabbitmq-server
systemctl enable --now rabbitmq-server
rabbitmqctl add_user $RABBIT_USER $RABBIT_PASS
rabbitmqctl set_permissions $RABBIT_USER ".*" ".*" ".*"
systemctl restart rabbitmq-server

# 安装缓存服务
yum install -y memcached python3-memcached
sed -i -e "s/OPTIONS=.*/OPTIONS=\"-l 127.0.0.1,::1,$HOST_NAME\"/g" /etc/sysconfig/memcached
systemctl enable --now memcached
EOF

chmod +x /root/iaas-install-mysql.sh
bash /root/iaas-install-mysql.sh

# --- 创建并执行 iaas-install-keystone.sh ---
log "Installing Keystone..."

cat > /root/iaas-install-keystone.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh

mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS keystone;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"

yum install -y openstack-keystone httpd mod_wsgi
cp /etc/keystone/keystone.conf{,.bak}
cat > /etc/keystone/keystone.conf << eoff
[DEFAULT]
log_dir = /var/log/keystone
[database]
connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@$HOST_NAME/keystone
[token]
provider = fernet
eoff

su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
    --bootstrap-admin-url http://$HOST_NAME:5000/v3/ \
    --bootstrap-internal-url http://$HOST_NAME:5000/v3/ \
    --bootstrap-public-url http://$HOST_NAME:5000/v3/ \
    --bootstrap-region-id RegionOne

echo "ServerName $HOST_NAME" >> /etc/httpd/conf/httpd.conf
ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl enable --now httpd

cat > /etc/keystone/admin-openrc.sh << EOF2
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://$HOST_NAME:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF2

source /etc/keystone/admin-openrc.sh
yum install -y python3-openstackclient
openstack project create --domain default --description "Service Project" service
openstack token issue
EOF

chmod +x /root/iaas-install-keystone.sh
bash /root/iaas-install-keystone.sh

# --- 创建并执行 iaas-install-glance.sh ---
log "Installing Glance..."

cat > /root/iaas-install-glance.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh
source /etc/keystone/admin-openrc.sh

mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS glance;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';"

openstack user create --domain $DOMAIN_NAME --password $GLANCE_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://$HOST_NAME:9292
openstack endpoint create --region RegionOne image internal http://$HOST_NAME:9292
openstack endpoint create --region RegionOne image admin http://$HOST_NAME:9292

yum install -y openstack-glance
cp /etc/glance/glance-api.conf{,.bak}
cat > /etc/glance/glance-api.conf << eoff
[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@$HOST_NAME/glance
[keystone_authtoken]
www_authenticate_uri = http://$HOST_NAME:5000
auth_url = http://$HOST_NAME:5000
memcached_servers = $HOST_NAME:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = $GLANCE_PASS
[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
[paste_deploy]
flavor = keystone
eoff

su -s /bin/sh -c "glance-manage db_sync" glance
systemctl enable --now openstack-glance-api.service
EOF

chmod +x /root/iaas-install-glance.sh
bash /root/iaas-install-glance.sh

# --- 创建并执行 iaas-install-placement.sh ---
log "Installing Placement..."

cat > /root/iaas-install-placement.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh
source /etc/keystone/admin-openrc.sh

mysql -uroot -p$DB_PASS -e "CREATE DATABASE placement;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_DBPASS';"

openstack user create --domain $DOMAIN_NAME --password $PLACEMENT_PASS placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://$HOST_NAME:8778
openstack endpoint create --region RegionOne placement internal http://$HOST_NAME:8778
openstack endpoint create --region RegionOne placement admin http://$HOST_NAME:8778

yum install -y openstack-placement-api
cp /etc/placement/placement.conf{,.bak}
cat > /etc/placement/placement.conf << eoff
[api]
auth_strategy = keystone
[keystone_authtoken]
auth_url = http://$HOST_NAME:5000/v3
memcached_servers = $HOST_NAME:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = $PLACEMENT_PASS
[placement_database]
connection = mysql+pymysql://placement:$PLACEMENT_DBPASS@$HOST_NAME/placement
eoff

su -s /bin/sh -c "placement-manage db sync" placement
systemctl restart httpd
EOF

chmod +x /root/iaas-install-placement.sh
bash /root/iaas-install-placement.sh

# --- 创建并执行 iaas-install-nova-controller.sh ---
log "Installing Nova..."

cat > /root/iaas-install-nova-controller.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh
source /etc/keystone/admin-openrc.sh

mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS nova;"
mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS nova_api;"
mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS nova_cell0;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"

openstack user create --domain $DOMAIN_NAME --password $NOVA_PASS nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://$HOST_NAME:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://$HOST_NAME:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://$HOST_NAME:8774/v2.1

yum install -y openstack-nova-api openstack-nova-conductor openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-compute
cp /etc/nova/nova.conf{,.bak}
cat > /etc/nova/nova.conf << eoff
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://$RABBIT_USER:$RABBIT_PASS@$HOST_NAME
my_ip = $HOST_IP
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver
compute_driver=libvirt.LibvirtDriver
instances_path = /var/lib/nova/instances/
log_dir = /var/log/nova
[api]
auth_strategy = keystone
[api_database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@$HOST_NAME/nova_api
[database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@$HOST_NAME/nova
[glance]
api_servers = http://$HOST_NAME:9292
[keystone_authtoken]
www_authenticate_uri = http://$HOST_NAME:5000/
auth_url = http://$HOST_NAME:5000/
memcached_servers = $HOST_NAME:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = $NOVA_PASS
[neutron]
auth_url = http://$HOST_NAME:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASS
service_metadata_proxy = true
metadata_proxy_shared_secret = $METADATA_SECRET
[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://$HOST_NAME:5000/v3
username = placement
password = $PLACEMENT_PASS
[vnc]
enabled = true
server_listen = $HOST_IP
server_proxyclient_address = $HOST_IP
novncproxy_base_url = http://$HOST_IP:6080/vnc_auto.html
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
eoff

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova

systemctl enable --now openstack-nova-api.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service libvirtd.service openstack-nova-compute.service

cat > /root/nova-service-restart.sh << EOF2
#!/bin/bash
systemctl restart openstack-nova-api openstack-nova-scheduler openstack-nova-conductor openstack-nova-novncproxy openstack-nova-compute
EOF2
chmod +x /root/nova-service-restart.sh
bash /root/nova-service-restart.sh
EOF

chmod +x /root/iaas-install-nova-controller.sh
bash /root/iaas-install-nova-controller.sh

# --- 创建并执行 iaas-install-neutron-controller.sh ---
log "Installing Neutron..."

cat > /root/iaas-install-neutron-controller.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh
source /etc/keystone/admin-openrc.sh

mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS neutron;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';"

openstack user create --domain $DOMAIN_NAME --password $NEUTRON_PASS neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://$HOST_NAME:9696
openstack endpoint create --region RegionOne network internal http://$HOST_NAME:9696
openstack endpoint create --region RegionOne network admin http://$HOST_NAME:9696

yum install -y openstack-neutron openstack-neutron-linuxbridge ebtables ipset openstack-neutron-ml2

# 网卡配置（仅当未配置时）
if ! ip a show "$INTERFACE_NAME" | grep -q "$HOST_IP"; then
cat > /etc/sysconfig/network-scripts/ifcfg-$INTERFACE_NAME << EOF2
DEVICE=$INTERFACE_NAME
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=yes
IPADDR=$HOST_IP
PREFIX=24
EOF2
systemctl restart NetworkManager
fi

cp /etc/neutron/neutron.conf{,.bak}
cat > /etc/neutron/neutron.conf << eoff
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
auth_strategy = keystone
state_path = /var/lib/neutron
dhcp_agent_notification = true
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
transport_url = rabbit://$RABBIT_USER:$RABBIT_PASS@$HOST_NAME
api_workers = 3
[database]
connection = mysql+pymysql://neutron:$NEUTRON_DBPASS@$HOST_NAME/neutron
[keystone_authtoken]
www_authenticate_uri = http://$HOST_NAME:5000
auth_url = http://$HOST_NAME:5000
memcached_servers = $HOST_NAME:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $NEUTRON_PASS
[nova]
auth_url = http://$HOST_NAME:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = $NOVA_PASS
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
eoff

cp /etc/neutron/plugins/ml2/ml2_conf.ini{,.bak}
cat > /etc/neutron/plugins/ml2/ml2_conf.ini << eoff
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security
[ml2_type_flat]
flat_networks = $Physical_NAME
[ml2_type_vxlan]
vni_ranges = $minvlan:$maxvlan
[securitygroup]
enable_ipset = true
eoff

cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini{,.bak}
cat > /etc/neutron/plugins/ml2/linuxbridge_agent.ini << eoff
[linux_bridge]
physical_interface_mappings = $Physical_NAME:$INTERFACE_NAME
[vxlan]
enable_vxlan = true
local_ip = $HOST_IP
l2_population = true
[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
eoff

cp /etc/neutron/l3_agent.ini{,.bak}
cat > /etc/neutron/l3_agent.ini << eoff
[DEFAULT]
interface_driver = linuxbridge
eoff

cp /etc/neutron/dhcp_agent.ini{,.bak}
cat > /etc/neutron/dhcp_agent.ini << eoff
[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
eoff

cp /etc/neutron/metadata_agent.ini{,.bak}
cat > /etc/neutron/metadata_agent.ini << eoff
[DEFAULT]
nova_metadata_host = $HOST_IP
metadata_proxy_shared_secret = $METADATA_SECRET
eoff

modprobe br_netfilter
echo 'net.ipv4.conf.all.rp_filter=0' >> /etc/sysctl.conf
echo 'net.ipv4.conf.default.rp_filter=0' >> /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-ip6tables = 1' >> /etc/sysctl.conf
sysctl -p

ln -sf /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

systemctl restart openstack-nova-api.service
systemctl enable --now neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service

cat > /root/neutron-service-restart.sh << EOF2
#!/bin/bash
systemctl restart neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service
EOF2
chmod +x /root/neutron-service-restart.sh
bash /root/neutron-service-restart.sh
EOF

chmod +x /root/iaas-install-neutron-controller.sh
bash /root/iaas-install-neutron-controller.sh

# --- 创建并执行 iaas-install-horizon.sh ---
log "Installing Horizon..."

cat > /root/iaas-install-horizon.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh
source /etc/keystone/admin-openrc.sh

yum install -y openstack-dashboard

cp /etc/openstack-dashboard/local_settings{,.bak}
sed -i "s/OPENSTACK_HOST = .*/OPENSTACK_HOST = '$HOST_NAME'/" /etc/openstack-dashboard/local_settings
sed -i "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*', ]/" /etc/openstack-dashboard/local_settings
sed -i "104s/.*/SESSION_ENGINE = 'django.contrib.sessions.backends.cache'/" /etc/openstack-dashboard/local_settings
cat >> /etc/openstack-dashboard/local_settings << EOFF

OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "Default"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"

OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}

CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
        'LOCATION': 'controller:11211',
    }
}
EOFF

sed -i "147s/.*/TIME_ZONE = 'Asia\/Shanghai'/" /etc/openstack-dashboard/local_settings

systemctl restart httpd memcached
EOF

chmod +x /root/iaas-install-horizon.sh
bash /root/iaas-install-horizon.sh

# --- 完成提示 ---
echo "###############################################################"
echo "#################      集群初始化成功     #####################"
echo "###############################################################"
log "All services installed successfully."