#!/bin/bash

# ==========================================================================
# 脚本作者： ZJT8848,链接：https://github.com/ZJT8848/openStack-in-openEuler
# 部分代码来源：作者 huhy,链接：https://www.cnblogs.com/hoyeong/p/18793119
# OpenStack In OpenEuler 自动化部署脚本
# 理论上适配 openEuler20/22/  /  CentOS 7/8/9
# OpenStack22.02 LTS SP4实测脚本没问题
# ==========================================================================


# --- 配置区 ---
# 自动获取网络配置信息
echo "正在检测网络接口..."
INTERFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|ens|eno|enp|wlan)' | head -10))

if [ ${#INTERFACES[@]} -eq 0 ]; then
    echo "未找到有效的网络接口"
    exit 1
elif [ ${#INTERFACES[@]} -eq 1 ]; then
    SELECTED_INTERFACE=${INTERFACES[0]}
    echo "发现一个网络接口: $SELECTED_INTERFACE"
else
    echo "发现多个网络接口:"
    for i in "${!INTERFACES[@]}"; do
        IP_ADDR=$(ip -o -4 addr show dev ${INTERFACES[$i]} | awk '{print $4}' | cut -d'/' -f1)
        echo "  [$i] ${INTERFACES[$i]} (${IP_ADDR:-无IP})"
    done
    
    while true; do
        echo -n "请选择要使用的网络接口 (0-$(( ${#INTERFACES[@]} - 1 ))): "
        read choice
        if [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 0 ] && [ $choice -lt ${#INTERFACES[@]} ]; then
            SELECTED_INTERFACE=${INTERFACES[$choice]}
            break
        else
            echo "无效选择，请重新输入"
        fi
    done
fi

# 获取选定接口的IP地址和网络信息
HOST_IP=$(ip -o -4 addr show dev $SELECTED_INTERFACE | awk '{print $4}' | cut -d'/' -f1)
INTERFACE_NAME=$SELECTED_INTERFACE
NETMASK=$(ip -o -4 addr show dev $SELECTED_INTERFACE | awk '{print $4}' | cut -d'/' -f2)

if [ -z "$HOST_IP" ] || [ -z "$NETMASK" ]; then
    echo "无法获取选定接口 $SELECTED_INTERFACE 的IP地址或子网掩码"
    exit 1
fi

# 计算网络地址（不依赖ipcalc）
IFS=. read -r i1 i2 i3 i4 <<< "$HOST_IP"
MASK=$((0xffffffff << (32 - NETMASK)))
IFS=. read -r m1 m2 m3 m4 <<< "$((MASK >> 24 & 0xff)).$((MASK >> 16 & 0xff)).$((MASK >> 8 & 0xff)).$((MASK & 0xff))"
NETWORK_BASE="$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).$((i4 & m4))"
TIME_SERVER_IP="$NETWORK_BASE/$NETMASK"

HOST_NAME="controller"
NODES=("$HOST_IP controller")
HOST_PASS="000000"
TIME_SERVER="controller"

LOG_FILE="/root/init.log"
ERRORS=()  # 用于收集错误步骤

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

error() {
    ERRORS+=("$1")
    log "⚠️ 错误: $1"
}

# --- 欢迎界面 ---
cat > /etc/motd <<EOF
 ################################
 #    Welcome  to  openstack    #
 #  https://github.com/ZJT8848  #
 ################################
EOF

# ==============================
# 步骤包装函数
# ==============================
run_step() {
    local step_name="$1"
    shift
    log "🚀 开始：$step_name"
    if "$@"; then
        log "✅ 完成：$step_name"
    else
        error "$step_name 执行失败"
    fi
}

# --- 禁用 SELinux ---
run_step "禁用 SELinux" bash -c '
    sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
    setenforce 0 || true
'

# --- 关闭 firewalld ---
run_step "关闭 firewalld" bash -c '
    systemctl stop firewalld
    systemctl disable firewalld >/dev/null 2>&1 || true
'

# --- 清空 iptables ---
run_step "清空并禁用 iptables" bash -c '
    yum install -y iptables-services
    systemctl enable --now iptables
    iptables -F
    iptables -X
    iptables -Z
    /usr/sbin/iptables-save > /etc/sysconfig/iptables
    systemctl stop iptables
    systemctl disable iptables
'

# --- 优化 SSH ---
run_step "优化 SSH 配置" bash -c '
    sed -i "s/#UseDNS yes/UseDNS no/; s/GSSAPIAuthentication yes/GSSAPIAuthentication no/" /etc/ssh/sshd_config
    systemctl reload sshd
'

# --- 设置主机名 ---
run_step "设置主机名" bash -c "
    current_ip=\$(hostname -I | awk '{print \$1}')
    for node in ${NODES[@]}; do
        ip=\$(echo \"\$node\" | awk '{print \$1}')
        hostname=\$(echo \"\$node\" | awk '{print \$2}')
        if [[ \"\$current_ip\" == \"\$ip\" ]]; then
            if [[ \"\$(hostname)\" != \"\$hostname\" ]]; then
                hostnamectl set-hostname \"\$hostname\"
                echo \"Hostname set to \$hostname\"
            fi
            break
        fi
    done
"

# --- 更新 /etc/hosts ---
run_step "更新 /etc/hosts" bash -c "
    for node in ${NODES[@]}; do
        ip=\$(echo \"\$node\" | awk '{print \$1}')
        hostname=\$(echo \"\$node\" | awk '{print \$2}')
        grep -q \"\$ip \$hostname\" /etc/hosts || echo \"\$ip \$hostname\" >> /etc/hosts
    done
"

# --- SSH 免密登录准备 ---
run_step "配置 SSH 免密登录" bash -c "
    [ ! -f ~/.ssh/id_rsa ] && ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q
    command -v sshpass >/dev/null || yum install -y sshpass
    for node in ${NODES[@]}; do
        ip=\$(echo \"\$node\" | awk '{print \$1}')
        hostname=\$(echo \"\$node\" | awk '{print \$2}')
        sshpass -p '$HOST_PASS' ssh-copy-id -o StrictHostKeyChecking=no \"\$hostname\" || true
    done
"

# --- 时间同步 (chrony) ---
run_step "配置时间同步 (chrony)" bash -c "
    name=\$(hostname)
    sed -i '/^server/d' /etc/chrony.conf
    if [[ \"\$name\" == \"$TIME_SERVER\" ]]; then
        echo 'server ntp.aliyun.com iburst' >> /etc/chrony.conf
        echo 'allow $TIME_SERVER_IP' >> /etc/chrony.conf
        echo 'local stratum 10' >> /etc/chrony.conf
    else
        echo 'server $TIME_SERVER iburst' >> /etc/chrony.conf
    fi
    systemctl restart chronyd
"

# --- 安装 OpenStack Train Yum 源 ---

yum install -y openstack-release-train

# --- 创建全局环境变量文件 ---
cat > /root/openrc.sh << EOF
HOST_IP=$HOST_IP
HOST_PASS=$HOST_PASS
HOST_NAME=$HOST_NAME
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
INTERFACE_NAME=$INTERFACE_NAME
Physical_NAME=provider
minvlan=1
maxvlan=1000
EOF

source /root/openrc.sh

# --- 安装基础服务（MySQL/RabbitMQ/Memcached）---
cat > /root/iaas-install-mysql.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh

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

sleep 10

if mysql -e "SELECT 1;" &>/dev/null; then
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -uroot -p$DB_PASS -e "FLUSH PRIVILEGES"
else
    systemctl stop mariadb
    mysqld_safe --skip-grant-tables --skip-networking &
    sleep 10
    mysql -e "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_PASS';"
    killall mysqld_safe
    systemctl start mariadb
fi

if ! mysql -uroot -p$DB_PASS -e "SELECT 1;" &>/dev/null; then
    echo "❌ MariaDB 无法通过密码登录！"
    exit 1
fi

yum install -y rabbitmq-server
systemctl enable --now rabbitmq-server
sleep 10
rabbitmqctl add_user $RABBIT_USER $RABBIT_PASS
rabbitmqctl set_permissions $RABBIT_USER ".*" ".*" ".*"
rabbitmqctl set_user_tags $RABBIT_USER administrator

yum install -y memcached python3-memcached
sed -i "s/OPTIONS=.*/OPTIONS=\"-l 127.0.0.1,::1,$HOST_NAME\"/" /etc/sysconfig/memcached
systemctl enable --now memcached
EOF

chmod +x /root/iaas-install-mysql.sh
run_step "安装 MySQL、RabbitMQ 和 Memcached" /root/iaas-install-mysql.sh

# --- Keystone 安装 ---
cat > /root/iaas-install-keystone.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh

mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS keystone;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"

yum install -y openstack-keystone httpd mod_wsgi

cat > /etc/keystone/keystone.conf << eoff
[DEFAULT]
log_dir = /var/log/keystone
[database]
connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@$HOST_NAME:3306/keystone
[token]
provider = fernet
[fernet_tokens]
key_repository = /etc/keystone/fernet-keys/
[credential]
key_repository = /etc/keystone/credential-keys/
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
ln -sf /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl enable --now httpd

mkdir -p /var/log/keystone /etc/keystone/fernet-keys /etc/keystone/credential-keys
chown -R keystone:keystone /var/log/keystone /etc/keystone/fernet-keys /etc/keystone/credential-keys
chmod 750 /var/log/keystone /etc/keystone/fernet-keys /etc/keystone/credential-keys

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
run_step "安装 Keystone 身份认证服务" /root/iaas-install-keystone.sh

# --- Glance 安装 ---
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

cat > /etc/glance/glance-api.conf << eoff
[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@$HOST_NAME:3306/glance
[keystone_authtoken]
www_authenticate_uri = http://$HOST_NAME:5000/v3
auth_url = http://$HOST_NAME:5000/v3
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

mkdir -p /var/log/glance /var/lib/glance
chown -R glance:glance /var/log/glance /var/lib/glance
systemctl enable --now openstack-glance-api
EOF

chmod +x /root/iaas-install-glance.sh
run_step "安装 Glance 镜像服务" /root/iaas-install-glance.sh

# --- Placement 安装 ---
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

cat > /etc/placement/placement.conf << eoff
[DEFAULT]
debug = false
[api]
auth_strategy = keystone
[keystone_authtoken]
www_authenticate_uri = http://$HOST_NAME:5000/v3
auth_url = http://$HOST_NAME:5000/v3
memcached_servers = $HOST_NAME:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = $PLACEMENT_PASS
[placement_database]
connection = mysql+pymysql://placement:$PLACEMENT_DBPASS@$HOST_NAME:3306/placement
eoff

su -s /bin/sh -c "placement-manage db sync" placement

mkdir -p /var/log/placement
chown -R placement:placement /var/log/placement
systemctl restart httpd
EOF

chmod +x /root/iaas-install-placement.sh
run_step "安装 Placement 资源跟踪服务" /root/iaas-install-placement.sh

# --- Nova 安装 ---
cat > /root/iaas-install-nova-controller.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh
source /etc/keystone/admin-openrc.sh

mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS nova;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS nova_api;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "CREATE DATABASE IF NOT EXISTS nova_cell0;"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';"
mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';"

openstack user create --domain $DOMAIN_NAME --password $NOVA_PASS nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://$HOST_NAME:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://$HOST_NAME:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://$HOST_NAME:8774/v2.1

yum install -y openstack-nova-api openstack-nova-conductor openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-compute

cat > /etc/nova/nova.conf << eoff
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://$RABBIT_USER:$RABBIT_PASS@$HOST_NAME:5672
my_ip = $HOST_IP
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver
compute_driver=libvirt.LibvirtDriver
instances_path = /var/lib/nova/instances/
log_dir = /var/log/nova
[api]
auth_strategy = keystone
[api_database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@$HOST_NAME:3306/nova_api
[database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@$HOST_NAME:3306/nova
[glance]
api_servers = http://$HOST_NAME:9292
[keystone_authtoken]
www_authenticate_uri = http://$HOST_NAME:5000/v3
auth_url = http://$HOST_NAME:5000/v3
memcached_servers = $HOST_NAME:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = $NOVA_PASS
[neutron]
auth_url = http://$HOST_NAME:5000/v3
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
[oslo_messaging_rabbit]
rabbit_userid = $RABBIT_USER
rabbit_password = $RABBIT_PASS
rabbit_host = $HOST_NAME
rabbit_port = 5672
eoff

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova

mkdir -p /var/log/nova /var/lib/nova
chown -R nova:nova /var/log/nova /var/lib/nova

systemctl enable openstack-nova-api openstack-nova-scheduler openstack-nova-conductor openstack-nova-novncproxy libvirtd openstack-nova-compute
systemctl start openstack-nova-api openstack-nova-scheduler openstack-nova-conductor openstack-nova-novncproxy libvirtd openstack-nova-compute

cat > /root/nova-service-restart.sh << EOF2
#!/bin/bash
systemctl restart openstack-nova-api openstack-nova-scheduler openstack-nova-conductor openstack-nova-novncproxy openstack-nova-compute
EOF2
chmod +x /root/nova-service-restart.sh
EOF

chmod +x /root/iaas-install-nova-controller.sh
run_step "安装 Nova 计算服务" /root/iaas-install-nova-controller.sh

# --- Neutron 安装 ---
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
transport_url = rabbit://$RABBIT_USER:$RABBIT_PASS@$HOST_NAME:5672
[database]
connection = mysql+pymysql://neutron:$NEUTRON_DBPASS@$HOST_NAME:3306/neutron
[keystone_authtoken]
www_authenticate_uri = http://$HOST_NAME:5000/v3
auth_url = http://$HOST_NAME:5000/v3
memcached_servers = $HOST_NAME:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = $NEUTRON_PASS
[nova]
auth_url = http://$HOST_NAME:5000/v3
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

cat > /etc/neutron/l3_agent.ini << eoff
[DEFAULT]
interface_driver = linuxbridge
eoff

cat > /etc/neutron/dhcp_agent.ini << eoff
[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
eoff

cat > /etc/neutron/metadata_agent.ini << eoff
[DEFAULT]
nova_metadata_host = $HOST_IP
metadata_proxy_shared_secret = $METADATA_SECRET
[cache]
enabled = false
eoff

modprobe br_netfilter
cat >> /etc/sysctl.conf << EOFF
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOFF
sysctl -p

ln -sf /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

mkdir -p /var/log/neutron /var/lib/neutron
chown -R neutron:neutron /var/log/neutron /var/lib/neutron

systemctl restart openstack-nova-api
systemctl enable neutron-server neutron-linuxbridge-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent
systemctl start neutron-server neutron-linuxbridge-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent

cat > /root/neutron-service-restart.sh << EOF2
#!/bin/bash
systemctl restart neutron-server neutron-linuxbridge-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent
EOF2
chmod +x /root/neutron-service-restart.sh
EOF

chmod +x /root/iaas-install-neutron-controller.sh
run_step "安装 Neutron 网络服务" /root/iaas-install-neutron-controller.sh

# --- Horizon 安装 ---
cat > /root/iaas-install-horizon.sh << 'EOF'
#!/bin/bash
source /root/openrc.sh
source /etc/keystone/admin-openrc.sh

yum install -y openstack-dashboard

cp /etc/openstack-dashboard/local_settings{,.bak}
sed -i "s/OPENSTACK_HOST = .*/OPENSTACK_HOST = '$HOST_NAME'/" /etc/openstack-dashboard/local_settings
sed -i "s/ALLOWED_HOSTS = .*/ALLOWED_HOSTS = ['*', ]/" /etc/openstack-dashboard/local_settings
sed -i "s/^SESSION_ENGINE.*/SESSION_ENGINE = 'django.contrib.sessions.backends.cache'/" /etc/openstack-dashboard/local_settings

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
    "default": {
        "BACKEND": "django.core.cache.backends.memcached.MemcachedCache",
        "LOCATION": "$HOST_NAME:11211",
    }
}
EOFF

sed -i "s/^TIME_ZONE.*/TIME_ZONE = 'Asia\/Shanghai'/" /etc/openstack-dashboard/local_settings

systemctl restart httpd memcached
EOF

chmod +x /root/iaas-install-horizon.sh
run_step "安装 Horizon Web 控制台" /root/iaas-install-horizon.sh

# 添加您指定的命令
sudo mkdir -p /etc/openstack-dashboard
echo "SITE_URL = '/dashboard/'" | sudo tee /etc/openstack-dashboard/local_settings.py
echo -e "SITE_URL = '/dashboard/'\nALLOWED_HOSTS = ['*','$HOST_IP']\nSESSION_COOKIE_SECURE = False\nCSRF_COOKIE_SECURE = False" | sudo tee /etc/openstack-dashboard/local_settings.py
sudo chown apache:apache /etc/openstack-dashboard/local_settings.py
sudo bash -c 'echo -e "\nRedirect /header /dashboard/header" >> /etc/httpd/conf.d/openstack-dashboard.conf'
sudo systemctl restart httpd

# Horizon 配置修改
# Fix login redirect issue
sudo sed -i '$ a # Fix login redirect issue\nWEBROOT = "/dashboard/"\nLOGIN_REDIRECT_URL = WEBROOT' /etc/openstack-dashboard/local_settings

# 修改 DEBUG 模式
sudo sed -i 's/DEBUG = False/DEBUG = True/' /etc/openstack-dashboard/local_settings

# 重启 Apache 使配置生效
sudo systemctl restart httpd

# 服务状态检查和启用脚本
cat > /root/check-and-enable-services.sh << 'EOF'
#!/bin/bash
SERVICES=(
  mariadb
  rabbitmq-server
  memcached
  httpd
  openstack-glance-api
  openstack-nova-api
  openstack-nova-scheduler
  openstack-nova-conductor
  openstack-nova-novncproxy
  openstack-nova-compute
  libvirtd
  neutron-server
  neutron-linuxbridge-agent
  neutron-dhcp-agent
  neutron-metadata-agent
  neutron-l3-agent
)

for svc in "${SERVICES[@]}"; do
  echo "Checking $svc..."
  if ! systemctl is-enabled --quiet "$svc"; then
    echo "  -> NOT enabled. Enabling now..."
    systemctl enable "$svc"
  else
    echo "  -> OK (enabled)"
  fi
done
EOF

chmod +x /root/check-and-enable-services.sh
bash /root/check-and-enable-services.sh


sudo systemctl start httpd

sudo systemctl restart httpd

# Nova cell配置检查和修复
cat > /root/fix-nova-cells.sh << 'EOF'
#!/bin/bash
echo "🔹 第一步：检查当前 cells 状态"
source /etc/keystone/admin-openrc.sh
nova-manage cell_v2 list_cells

echo "🔹 第二步：强制发现并注册计算主机"
nova-manage cell_v2 discover_hosts --verbose

echo "🔹 第三步：确认 nova-compute 服务已启动并注册"
openstack compute service list

echo "🔹 第四步：验证主机是否已加入 cell"
nova-manage cell_v2 list_hosts
EOF

chmod +x /root/fix-nova-cells.sh

echo "执行Nova cell配置检查和修复..."
bash /root/fix-nova-cells.sh



# ==============================
# 最终总结
# ==============================

echo ""
echo "###############################################################"
echo "OpenStack安装和配置修复完成！"
echo "可以通过 http://$HOST_IP/dashboard 登录"
echo "用户名: admin"
echo "密码: $ADMIN_PASS"
echo "脚本作者： ZJT8848,链接： https://github.com/ZJT8848/openStack-in-openEuler"
echo "部分代码来源：作者 huhy,链接 https://www.cnblogs.com/hoyeong/p/18793119"
echo "###############################################################"
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo "✅ 所有组件安装成功！"
    log "All services installed successfully."
else
    echo "⚠️ 以下步骤执行失败，请检查日志："
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    log "部分服务安装失败，详见上述错误。"
fi
echo "日志文件：$LOG_FILE"
echo "###############################################################"