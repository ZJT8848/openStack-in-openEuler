#!/bin/bash

# OpenStack环境初始化和安装脚本
# 整合所有步骤到一个脚本中

# 定义节点信息
NODES=("192.168.1.177 controller")

# 定义当前节点的密码（默认集群统一密码）
HOST_PASS="000000"

# 时间同步的目标节点
TIME_SERVER=controller

# 时间同步的地址段
TIME_SERVER_IP=192.168.1.0/24

# 定义中文错误处理函数
handle_error() {
    local error_msg="$1"
    local step="$2"
    echo -e "\033[31m错误: [$step] $error_msg\033[0m"
    echo "脚本执行已中止，请检查上述错误"
    exit 1
}

# 检查命令执行结果
check_result() {
    if [ $? -ne 0 ]; then
        handle_error "$1" "$2"
    fi
}

# 设置中文环境变量
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# 重定向所有命令的错误输出到中文提示
exec 2> >(while read line; do echo -e "\033[33m警告: $line\033[0m"; done)

# 自动获取本机IP地址
get_host_ip() {
    # 获取所有非回环IPv4地址
    local ips=($(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\\.0\\.0\\.1$'))
    local count=${#ips[@]}

    if [ $count -eq 0 ]; then
        handle_error "未检测到有效IPv4地址，请检查网络配置" "IP检测"
    elif [ $count -eq 1 ]; then
        echo "${ips[0]}"
    else
        echo -e "\n检测到多个网络接口，请选择要使用的IP地址："
        for i in "${!ips[@]}"; do
            echo "  [$i] ${ips[$i]}"
        done
        read -p "请输入序号: " index
        if [[ $index =~ ^[0-9]+$ ]] && [ $index -lt $count ]; then
            echo "${ips[$index]}"
        else
            handle_error "无效的序号选择" "IP选择"
        fi
    fi
}

# 获取主机IP和网段
HOST_IP=$(get_host_ip)
NETWORK=$(echo $HOST_IP | awk -F. '{print $1"."$2"."$3".0/24"}')

# 更新节点信息
NODES=("$HOST_IP controller")
TIME_SERVER_IP=$NETWORK

# 欢迎界面改为中文
cat > /etc/motd <<EOF 
 ################################
 #     欢迎使用 OpenStack      #
 ################################
EOF

# 设置中文环境变量
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# 重定向所有命令的错误输出到中文提示
exec 2> >(while read line; do echo -e "\033[33m警告: $line\033[0m"; done)

# 欢迎界面
echo "开始执行OpenStack环境初始化..."

# 检查操作系统版本
if ! grep -q "openEuler" /etc/os-release; then
    echo -e "\033[33m警告: 此脚本专为openEuler设计，当前系统可能不兼容\033[0m"
fi

# 欢迎界面
cat > /etc/motd <<EOF 
 ################################
 #    Welcome  to  openstack    #
 ################################
EOF

# 禁用selinux
sed -i 's/SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

# firewalld
systemctl stop firewalld
systemctl disable firewalld >> /dev/null 2>&1

# 关闭IPtables，清空规则
if ! yum install iptables-services -y; then
    echo -e "\033[31m警告: iptables-services 安装失败\033[0m"
else
    systemctl restart iptables
    iptables -F
    iptables -X
    iptables -Z 
    /usr/sbin/iptables-save
    systemctl stop iptables
    systemctl disable iptables
fi

# 优化ssh连接
sed -i -e 's/#UseDNS yes/UseDNS no/g' -e 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
systemctl reload sshd

# 修改主机名
for node in "${NODES[@]}"; do
  ip=$(echo "$node" | awk '{print $1}')
  hostname=$(echo "$node" | awk '{print $2}')

  # 获取当前节点的主机名和 IP
  current_ip=$(hostname -I | awk '{print $1}')
  current_hostname=$(hostname)

  # 检查当前节点与要修改的节点信息是否匹配
  if [[ "$current_ip" == "$ip" && "$current_hostname" != "$hostname" ]]; then
    echo "Updating hostname to $hostname on $current_ip..."
    hostnamectl set-hostname "$hostname"

    if [ $? -eq 0 ]; then
      echo "Hostname updated successfully."
    else
      echo "Failed to update hostname."
    fi

    break
  fi
done

# 遍历节点信息并添加到 hosts 文件
for node in "${NODES[@]}"; do
  ip=$(echo "$node" | awk '{print $1}')
  hostname=$(echo "$node" | awk '{print $2}')

  # 检查 hosts 文件中是否已存在相应的解析
  if grep -q "$ip $hostname" /etc/hosts; then
    echo "Host entry for $hostname already exists in /etc/hosts."
  else
    # 添加节点的解析条目到 hosts 文件
    sudo sh -c "echo '$ip $hostname' >> /etc/hosts"
    echo "Added host entry for $hostname in /etc/hosts."
  fi
done

# 日志文件
LOG_FILE="init.log"

# 检查是否已生成SSH密钥
if [[ ! -s ~/.ssh/id_rsa.pub ]]; then
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q -b 2048
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 生成SSH密钥" >> "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SSH密钥已存在" >> "$LOG_FILE"
fi

# 检查并安装 sshpass 工具
if ! which sshpass &> /dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - sshpass 工具未安装，正在安装 sshpass..." >> "$LOG_FILE"
    sudo yum install -y sshpass >> "$LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - sshpass 安装失败" >> "$LOG_FILE"
        echo "警告: sshpass 安装失败，跳过SSH密钥分发"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - sshpass 安装完成" >> "$LOG_FILE"
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - sshpass 工具已安装" >> "$LOG_FILE"
fi

# 遍历所有节点（如果有sshpass）
if which sshpass &> /dev/null; then
    for node in "${NODES[@]}"; do
        ip=$(echo "$node" | awk '{print $1}')
        hostname=$(echo "$node" | awk '{print $2}')

        echo "$(date '+%Y-%m-%d %H:%M:%S') - 复制SSH密钥到节点 $hostname ($ip)" >> "$LOG_FILE"

        sshpass -p "$HOST_PASS" ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa.pub $hostname

        if [[ $? -eq 0 ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 成功复制SSH密钥到节点 $hostname ($ip)" >> "$LOG_FILE"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 复制SSH密钥到节点 $hostname ($ip) 失败" >> "$LOG_FILE"
        fi
    done
fi

# 时间同步
name=$(hostname)
if [[ $name == $TIME_SERVER ]]; then
    # 配置当前节点为时间同步源
    sed -i '3,4s/^/#/g' /etc/chrony.conf
    sed -i "7s/^/server $TIME_SERVER iburst/g" /etc/chrony.conf
    echo "allow $TIME_SERVER_IP" >> /etc/chrony.conf
    echo "local stratum 10" >> /etc/chrony.conf
else
    # 配置当前节点同步到目标节点
    sed -i '3,4s/^/#/g' /etc/chrony.conf
    sed -i "7s/^/server $TIME_SERVER iburst/g" /etc/chrony.conf
fi

# 重启并启用 chrony 服务
systemctl restart chronyd 2>/dev/null || echo "警告: chronyd 服务重启失败"

echo "###############################################################"
echo "#################      集群初始化成功     #####################"
echo "###############################################################"

# 下载OpenStack Train Yum 源
echo "配置OpenStack Train Yum源..."

# 1. 卸载 wallaby 包（如果存在）
#sudo dnf remove -y openstack-release-wallaby 2>/dev/null

# 2. 安装 train 包
if sudo dnf install -y openstack-release-train; then
    echo "OpenStack Train 源安装成功"
else
    echo "警告: OpenStack Train 源安装失败，尝试手动配置"
    
    # 手动配置repo文件
    cat > /etc/yum.repos.d/openEuler.repo << eof
[OpenStack_Train]
name=OpenStack_Train
baseurl=https://repo.openeuler.org/openEuler-22.03-LTS-SP4/EPOL/multi_version/OpenStack/Train/\$basearch/
enabled=1
gpgcheck=1
gpgkey=https://repo.openeuler.org/openEuler-22.03-LTS-SP4/OS/\$basearch/RPM-GPG-KEY-openEuler
priority=1

[OpenStack_Train_update]
name=OpenStack_Train_update
baseurl=https://repo.openeuler.org/openEuler-22.03-LTS-SP4/EPOL/update/multi_version/OpenStack/Train/\$basearch/
enabled=1
gpgcheck=1
gpgkey=https://repo.openeuler.org/openEuler-22.03-LTS-SP4/OS/\$basearch/RPM-GPG-KEY-openEuler
priority=1
eof
fi

# 3. 清理缓存
sudo dnf clean all
sudo dnf makecache

# 配置环境变量
echo "配置环境变量..."

cat > /root/openrc.sh << eof
HOST_IP=$HOST_IP
HOST_PASS=000000
HOST_NAME=controller
HOST_IP_NODE=
HOST_PASS_NODE=
HOST_NAME_NODE=
RABBIT_USER=openstack
RABBIT_PASS=000000
DB_PASS=000000
DOMAIN_NAME=default
ADMIN_PASS=000000
DEMO_PASS=000000
KEYSTONE_DBPASS=000000
GLANCE_DBPASS=000000
GLANCE_PASS=000000
PLACEMENT_DBPASS=000000
PLACEMENT_PASS=000000
NOVA_DBPASS=000000
NOVA_PASS=000000
NEUTRON_DBPASS=000000
NEUTRON_PASS=000000
METADATA_SECRET=000000
INTERFACE_NAME=ens34
Physical_NAME=provider
minvlan=1
maxvlan=1000
eof

source /root/openrc.sh

# 安装基础服务：数据库、消息队列、缓存
echo "安装基础服务..."

# 安装数据库服务
if yum install -y mariadb mariadb-server python3-PyMySQL; then
    echo "数据库服务安装成功"
else
    handle_error "数据库相关软件包安装失败" "基础服务安装"
fi

# 安装消息队列服务
if yum install -y rabbitmq-server; then
    echo "消息队列服务安装成功"
else
    handle_error "rabbitmq-server 安装失败" "基础服务安装"
fi

# 安装缓存服务
if yum install -y memcached python3-memcached; then
    echo "缓存服务安装成功"
else
    handle_error "memcached 相关软件包安装失败" "基础服务安装"
fi

# 安装keystone服务
echo "安装keystone服务..."

# 检查数据库是否可用
if command -v mysql &> /dev/null; then
    # keystone mysql
    mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS keystone ;" 2>/dev/null || echo "警告: 创建 keystone 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS' ;" 2>/dev/null || echo "警告: 授权 keystone 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS' ;" 2>/dev/null || echo "警告: 授权 keystone 数据库失败"
else
    echo "警告: 数据库不可用，跳过 keystone 数据库配置"
fi

if yum install -y openstack-keystone httpd mod_wsgi; then
    if [ -f /etc/keystone/keystone.conf ]; then
        cp /etc/keystone/keystone.conf{,.bak}
    fi

    cat > /etc/keystone/keystone.conf << eof
[DEFAULT]
log_dir = /var/log/keystone
[application_credential]
[assignment]
[auth]
[cache]
[catalog]
[cors]
[credential]
[database]
connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@$HOST_NAME/keystone
[domain_config]
[endpoint_filter]
[endpoint_policy]
[eventlet_server]
[federation]
[fernet_receipts]
[fernet_tokens]
[healthcheck]
[identity]
[identity_mapping]
[jwt_tokens]
[ldap]
[memcache]
[oauth1]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[policy]
[profiler]
[receipt]
[resource]
[revoke]
[role]
[saml]
[security_compliance]
[shadow_users]
[token]
provider = fernet
[tokenless_auth]
[totp]
[trust]
[unified_limit]
[wsgi]
eof

    if command -v keystone-manage &> /dev/null; then
        su -s /bin/sh -c "keystone-manage db_sync" keystone 2>/dev/null || echo "警告: keystone 数据库同步失败"
        keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone 2>/dev/null || echo "警告: keystone fernet 设置失败"
        keystone-manage credential_setup --keystone-user keystone --keystone-group keystone 2>/dev/null || echo "警告: keystone credential 设置失败"
        keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
            --bootstrap-admin-url http://$HOST_NAME:5000/v3/ \
            --bootstrap-internal-url http://$HOST_NAME:5000/v3/ \
            --bootstrap-public-url http://$HOST_NAME:5000/v3/ \
            --bootstrap-region-id RegionOne 2>/dev/null || echo "警告: keystone bootstrap 失败"
    else
        echo "警告: keystone-manage 命令未找到"
    fi
    
    echo "ServerName $HOST_NAME" >> /etc/httpd/conf/httpd.conf 2>/dev/null || echo "警告: 添加 ServerName 失败"
    ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/ 2>/dev/null || echo "警告: 创建符号链接失败"
    systemctl enable --now httpd 2>/dev/null || echo "警告: httpd 服务启动失败"
    systemctl restart httpd 2>/dev/null || echo "警告: httpd 服务重启失败"

    cat > /etc/keystone/admin-openrc.sh << EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=$ADMIN_PASS
export OS_AUTH_URL=http://$HOST_NAME:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

    source /etc/keystone/admin-openrc.sh 2>/dev/null || echo "警告: 加载 admin-openrc 失败"
    
    if yum install -y python3-openstackclient; then
        openstack project create --domain default --description "Service Project" service 2>/dev/null || echo "警告: 创建 service 项目失败"
        openstack token issue 2>/dev/null || echo "警告: 获取 token 失败"
    else
        echo "警告: python3-openstackclient 安装失败"
    fi
else
    echo "警告: keystone 相关软件包安装失败"
fi

# 安装glance服务
echo "安装glance服务..."

# 检查数据库是否可用
if command -v mysql &> /dev/null; then
    # glance mysql
    mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS glance ;" 2>/dev/null || echo "警告: 创建 glance 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS' ;" 2>/dev/null || echo "警告: 授权 glance 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS' ;" 2>/dev/null || echo "警告: 授权 glance 数据库失败"
else
    echo "警告: 数据库不可用，跳过 glance 数据库配置"
fi

if command -v openstack &> /dev/null; then
    openstack user create --domain $DOMAIN_NAME --password $GLANCE_PASS glance 2>/dev/null || echo "警告: 创建 glance 用户失败"
    openstack role add --project service --user glance admin 2>/dev/null || echo "警告: 添加 glance 角色失败"
    openstack service create --name glance --description "OpenStack Image" image 2>/dev/null || echo "警告: 创建 glance 服务失败"
    openstack endpoint create --region RegionOne image public http://$HOST_NAME:9292 2>/dev/null || echo "警告: 创建 glance public 端点失败"
    openstack endpoint create --region RegionOne image internal http://$HOST_NAME:9292 2>/dev/null || echo "警告: 创建 glance internal 端点失败"
    openstack endpoint create --region RegionOne image admin http://$HOST_NAME:9292 2>/dev/null || echo "警告: 创建 glance admin 端点失败"
else
    echo "警告: openstack 命令未找到，跳过 glance 用户和端点配置"
fi

if yum install -y openstack-glance; then
    if [ -f /etc/glance/glance-api.conf ]; then
        cp /etc/glance/glance-api.conf{,.bak}
    fi

    cat > /etc/glance/glance-api.conf << eof
[DEFAULT]
[cinder]
[cors]
[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@$HOST_NAME/glance
[file]
[glance.store.http.store]
[glance.store.rbd.store]
[glance.store.sheepdog.store]
[glance.store.swift.store]
[glance.store.vmware_datastore.store]
[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
[image_format]
disk_formats = ami,ari,aki,vhd,vhdx,vmdk,raw,qcow2,vdi,iso,ploop.root-tar
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
[oslo_concurrency]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[paste_deploy]
flavor = keystone
[profiler]
[store_type_location_strategy]
[task]
[taskflow_executor]
eof

    if command -v glance-manage &> /dev/null; then
        su -s /bin/sh -c "glance-manage db_sync" glance 2>/dev/null || echo "警告: glance 数据库同步失败"
    else
        echo "警告: glance-manage 命令未找到"
    fi
    
    systemctl enable --now openstack-glance-api.service 2>/dev/null || echo "警告: glance-api 服务启动失败"
    systemctl restart openstack-glance-api 2>/dev/null || echo "警告: glance-api 服务重启失败"
else
    echo "警告: glance 相关软件包安装失败"
fi

# 安装placement服务
echo "安装placement服务..."

# 检查数据库是否可用
if command -v mysql &> /dev/null; then
    # placement mysql
    mysql -uroot -p$DB_PASS -e "CREATE DATABASE placement;" 2>/dev/null || echo "警告: 创建 placement 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_DBPASS';" 2>/dev/null || echo "警告: 授权 placement 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_DBPASS';" 2>/dev/null || echo "警告: 授权 placement 数据库失败"
else
    echo "警告: 数据库不可用，跳过 placement 数据库配置"
fi

if command -v openstack &> /dev/null; then
    openstack user create --domain $DOMAIN_NAME --password $PLACEMENT_PASS placement 2>/dev/null || echo "警告: 创建 placement 用户失败"
    openstack role add --project service --user placement admin 2>/dev/null || echo "警告: 添加 placement 角色失败"
    openstack service create --name placement --description "Placement API" placement 2>/dev/null || echo "警告: 创建 placement 服务失败"
    openstack endpoint create --region RegionOne placement public http://$HOST_NAME:8778 2>/dev/null || echo "警告: 创建 placement public 端点失败"
    openstack endpoint create --region RegionOne placement internal http://$HOST_NAME:8778 2>/dev/null || echo "警告: 创建 placement internal 端点失败"
    openstack endpoint create --region RegionOne placement admin http://$HOST_NAME:8778 2>/dev/null || echo "警告: 创建 placement admin 端点失败"
else
    echo "警告: openstack 命令未找到，跳过 placement 用户和端点配置"
fi

if yum install -y openstack-placement-api; then
    if [ -f /etc/placement/placement.conf ]; then
        cp /etc/placement/placement.conf{,.bak}
    fi
    
    cat > /etc/placement/placement.conf << eof
[DEFAULT]
[api]
auth_strategy = keystone
[cors]
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
eof

    if command -v placement-manage &> /dev/null; then
        su -s /bin/sh -c "placement-manage db sync" placement 2>/dev/null || echo "警告: placement 数据库同步失败"
    else
        echo "警告: placement-manage 命令未找到"
    fi
    
    systemctl restart httpd 2>/dev/null || echo "警告: httpd 服务重启失败"
    
    if command -v placement-status &> /dev/null; then
        placement-status upgrade check 2>/dev/null || echo "警告: placement 状态检查失败"
    else
        echo "警告: placement-status 命令未找到"
    fi

    # 下面配置可选
    if yum install -y python3-osc-placement; then
        # 会列出所有可用的资源类型（Resource Classes），并按名称排序。资源类型是指如VCPU、内存、磁盘空间等各种计算资源。
        openstack --os-placement-api-version 1.2 resource class list --sort-column name 2>/dev/null || echo "警告: 列出资源类失败"
        # 会列出所有定义的特性（Traits），并按名称排序。特性是一些标识，用来描述资源的某些能力或属性，例如是否支持SSD，是否有GPU等。
        openstack --os-placement-api-version 1.6 trait list --sort-column name 2>/dev/null || echo "警告: 列出特性失败"
    else
        echo "警告: python3-osc-placement 安装失败"
    fi
else
    echo "警告: placement 相关软件包安装失败"
fi

# 安装nova服务
echo "安装nova服务..."

# 检查数据库是否可用
if command -v mysql &> /dev/null; then
    mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS nova ;" 2>/dev/null || echo "警告: 创建 nova 数据库失败"
    mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS nova_api ;" 2>/dev/null || echo "警告: 创建 nova_api 数据库失败"
    mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS nova_cell0 ;" 2>/dev/null || echo "警告: 创建 nova_cell0 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS' ;" 2>/dev/null || echo "警告: 授权 nova 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS' ;" 2>/dev/null || echo "警告: 授权 nova 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS' ;" 2>/dev/null || echo "警告: 授权 nova_api 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS' ;" 2>/dev/null || echo "警告: 授权 nova_api 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS' ;" 2>/dev/null || echo "警告: 授权 nova_cell0 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS' ;" 2>/dev/null || echo "警告: 授权 nova_cell0 数据库失败"
else
    echo "警告: 数据库不可用，跳过 nova 数据库配置"
fi

if command -v openstack &> /dev/null; then
    openstack user create --domain $DOMAIN_NAME --password $NOVA_PASS nova 2>/dev/null || echo "警告: 创建 nova 用户失败"
    openstack role add --project service --user nova admin 2>/dev/null || echo "警告: 添加 nova 角色失败"
    openstack service create --name nova --description "OpenStack Compute" compute 2>/dev/null || echo "警告: 创建 nova 服务失败"
    openstack endpoint create --region RegionOne compute public http://$HOST_NAME:8774/v2.1 2>/dev/null || echo "警告: 创建 nova public 端点失败"
    openstack endpoint create --region RegionOne compute internal http://$HOST_NAME:8774/v2.1 2>/dev/null || echo "警告: 创建 nova internal 端点失败"
    openstack endpoint create --region RegionOne compute admin http://$HOST_NAME:8774/v2.1 2>/dev/null || echo "警告: 创建 nova admin 端点失败"
else
    echo "警告: openstack 命令未找到，跳过 nova 用户和端点配置"
fi

if yum install -y openstack-nova-api openstack-nova-conductor openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-compute; then
    if [ -f /etc/nova/nova.conf ]; then
        cp /etc/nova/nova.conf{,.bak}
    fi
    
    cat > /etc/nova/nova.conf << eof
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
[barbican]
[cache]
[cinder]
[compute]
[conductor]
[console]
[consoleauth]
[cors]
[database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@$HOST_NAME/nova
[devices]
[ephemeral_storage_encryption]
[filter_scheduler]
[glance]
api_servers = http://$HOST_NAME:9292
[guestfs]
[healthcheck]
[hyperv]
[ironic]
[key_manager]
[keystone]
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
[libvirt]
[metrics]
[mks]
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
[notifications]
[osapi_v21]
[oslo_concurrency]
lock_path = /var/lib/nova/tmp   
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[pci]
[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://$HOST_NAME:5000/v3
username = placement
password = $PLACEMENT_PASS
[powervm]
[privsep]
[profiler]
[quota]
[rdp]
[remote_debug]
[scheduler]
[serial_console]
[service_user]
[spice]
[upgrade_levels]
[vault]
[vendordata_dynamic_auth]
[vmware]
[vnc]
enabled = true
server_listen = $HOST_IP
server_proxyclient_address = $HOST_IP
novncproxy_base_url = http://$HOST_IP:6080/vnc_auto.html
[workarounds]
[wsgi]
[xenserver]
[xvp]
[zvm]
eof

    if command -v nova-manage &> /dev/null; then
        su -s /bin/sh -c "nova-manage api_db sync" nova 2>/dev/null || echo "警告: nova api 数据库同步失败"
        su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova 2>/dev/null || echo "警告: nova map_cell0 失败"
        su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova 2>/dev/null || echo "警告: nova create_cell 失败"
        su -s /bin/sh -c "nova-manage db sync" nova 2>/dev/null || echo "警告: nova 数据库同步失败"
        su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova 2>/dev/null || echo "警告: nova list_cells 失败"
    else
        echo "警告: nova-manage 命令未找到"
    fi

    systemctl enable --now openstack-nova-api.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service 2>/dev/null || echo "警告: nova 核心服务启动失败"
    systemctl enable --now libvirtd.service openstack-nova-compute.service 2>/dev/null || echo "警告: nova 计算服务启动失败"
    systemctl restart libvirtd.service 2>/dev/null || echo "警告: libvirtd 服务重启失败"

    cat > /root/nova-service-restart.sh <<EOF 
#!/bin/bash
# 处理api服务
systemctl restart openstack-nova-api 2>/dev/null || echo "警告: openstack-nova-api 重启失败"
# 处理资源调度服务
systemctl restart openstack-nova-scheduler 2>/dev/null || echo "警告: openstack-nova-scheduler 重启失败"
# 处理数据库服务
systemctl restart openstack-nova-conductor 2>/dev/null || echo "警告: openstack-nova-conductor 重启失败"
# 处理vnc远程窗口服务
systemctl restart openstack-nova-novncproxy 2>/dev/null || echo "警告: openstack-nova-novncproxy 重启失败"
# 处理nova-compute服务
systemctl restart openstack-nova-compute 2>/dev/null || echo "警告: openstack-nova-compute 重启失败"
EOF

    if command -v nova-manage &> /dev/null; then
        nova-manage cell_v2 discover_hosts 2>/dev/null || echo "警告: nova discover_hosts 失败"
        nova-manage cell_v2 map_cell_and_hosts 2>/dev/null || echo "警告: nova map_cell_and_hosts 失败"
        su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova 2>/dev/null || echo "警告: nova discover_hosts --verbose 失败"
    else
        echo "警告: nova-manage 命令未找到，跳过 cell 管理"
    fi
    
    bash /root/nova-service-restart.sh 2>/dev/null || echo "警告: nova 服务重启脚本执行失败"
else
    echo "警告: nova 相关软件包安装失败"
fi

# 安装neutron服务
echo "安装neutron服务..."

# 检查数据库是否可用
if command -v mysql &> /dev/null; then
    # neutron mysql
    mysql -uroot -p$DB_PASS -e "create database IF NOT EXISTS neutron ;" 2>/dev/null || echo "警告: 创建 neutron 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS' ;" 2>/dev/null || echo "警告: 授权 neutron 数据库失败"
    mysql -uroot -p$DB_PASS -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS' ;" 2>/dev/null || echo "警告: 授权 neutron 数据库失败"
else
    echo "警告: 数据库不可用，跳过 neutron 数据库配置"
fi

if command -v openstack &> /dev/null; then
    # neutron user role service endpoint 
    openstack user create --domain $DOMAIN_NAME --password $NEUTRON_PASS neutron 2>/dev/null || echo "警告: 创建 neutron 用户失败"
    openstack role add --project service --user neutron admin 2>/dev/null || echo "警告: 添加 neutron 角色失败"
    openstack service create --name neutron --description "OpenStack Networking" network 2>/dev/null || echo "警告: 创建 neutron 服务失败"
    openstack endpoint create --region RegionOne network public http://$HOST_NAME:9696 2>/dev/null || echo "警告: 创建 neutron public 端点失败"
    openstack endpoint create --region RegionOne network internal http://$HOST_NAME:9696 2>/dev/null || echo "警告: 创建 neutron internal 端点失败"
    openstack endpoint create --region RegionOne network admin http://$HOST_NAME:9696 2>/dev/null || echo "警告: 创建 neutron admin 端点失败"
else
    echo "警告: openstack 命令未找到，跳过 neutron 用户和端点配置"
fi

# neutron install
if yum install -y openstack-neutron openstack-neutron-linuxbridge ebtables ipset openstack-neutron-ml2; then
    # network
    INTERFACE_IP=$(ip addr show $INTERFACE_NAME 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    if [[ `ip a 2>/dev/null |grep -w $INTERFACE_IP |grep -w $INTERFACE_NAME` = '' ]] 2>/dev/null; then 
        cat > /etc/sysconfig/network-scripts/ifcfg-$INTERFACE_NAME <<EOF
DEVICE=$INTERFACE_NAME
TYPE=Ethernet
BOOTPROTO=none
ONBOOT=yes
EOF
        systemctl restart NetworkManager 2>/dev/null || echo "警告: NetworkManager 重启失败"
    fi

    # /etc/neutron/neutron.conf
    if [ -f /etc/neutron/neutron.conf ]; then
        cp /etc/neutron/neutron.conf{,.bak}
    fi
    
    cat > /etc/neutron/neutron.conf << eof
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
auth_strategy = keystone
state_path = /var/lib/neutron
dhcp_agent_notification = true
allow_overlapping_ips = true
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
transport_url = rabbit://$RABBIT_USER:$RABBIT_PASS@$HOST_NAME
api_workers = 3  
[cors]
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
[oslo_concurrency]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[privsep]
[ssl]
eof

    # /etc/neutron/plugins/ml2/ml2_conf.ini
    if [ -f /etc/neutron/plugins/ml2/ml2_conf.ini ]; then
        cp /etc/neutron/plugins/ml2/ml2_conf.ini{,.bak}
    fi
    
    cat >  /etc/neutron/plugins/ml2/ml2_conf.ini << eof
[DEFAULT]
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
eof

    if [ -f /etc/neutron/plugins/ml2/linuxbridge_agent.ini ]; then
        cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini{,.bak}
    fi
    
    cat >  /etc/neutron/plugins/ml2/linuxbridge_agent.ini << eof
[DEFAULT]
[linux_bridge]
physical_interface_mappings = $Physical_NAME:$INTERFACE_NAME
[vxlan]
enable_vxlan = true
local_ip = $HOST_IP
l2_population = true
[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
eof

    if [ -f /etc/neutron/l3_agent.ini ]; then
        cp /etc/neutron/l3_agent.ini{,.bak}
    fi
    
    cat >  /etc/neutron/l3_agent.ini << eof
[DEFAULT]
interface_driver = linuxbridge
eof

    if [ -f /etc/neutron/dhcp_agent.ini ]; then
        cp /etc/neutron/dhcp_agent.ini{,.bak}
    fi
    
    cat >  /etc/neutron/dhcp_agent.ini << eof
[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
eof

    if [ -f /etc/neutron/metadata_agent.ini ]; then
        cp /etc/neutron/metadata_agent.ini{,.bak}
    fi
    
    cat >  /etc/neutron/metadata_agent.ini << eof
[DEFAULT]
nova_metadata_host = $HOST_IP
metadata_proxy_shared_secret = $METADATA_SECRET
[cache]
eof

    # br_netfilter
    modprobe br_netfilter 2>/dev/null || echo "警告: 加载 br_netfilter 模块失败"
    echo 'net.ipv4.conf.all.rp_filter=0' >> /etc/sysctl.conf 2>/dev/null || echo "警告: 修改 sysctl.conf 失败"
    echo 'net.ipv4.conf.default.rp_filter=0' >> /etc/sysctl.conf 2>/dev/null || echo "警告: 修改 sysctl.conf 失败"
    echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf 2>/dev/null || echo "警告: 修改 sysctl.conf 失败"
    echo 'net.bridge.bridge-nf-call-ip6tables = 1' >> /etc/sysctl.conf 2>/dev/null || echo "警告: 修改 sysctl.conf 失败"
    sysctl -p 2>/dev/null || echo "警告: 应用 sysctl 设置失败"

    # su neutron mysql
    ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini 2>/dev/null || echo "警告: 创建符号链接失败"
    
    if command -v neutron-db-manage &> /dev/null; then
        su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron 2>/dev/null || echo "警告: neutron 数据库同步失败"
    else
        echo "警告: neutron-db-manage 命令未找到"
    fi

    systemctl restart openstack-nova-api.service 2>/dev/null || echo "警告: openstack-nova-api 服务重启失败"
    systemctl enable --now neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service 2>/dev/null || echo "警告: neutron 服务启动失败"

    cat > /root/neutron-service-restart.sh << eof
#!/bin/bash
systemctl restart neutron-server.service neutron-linuxbridge-agent.service neutron-dhcp-agent.service neutron-metadata-agent.service neutron-l3-agent.service 2>/dev/null || echo "警告: neutron 服务重启失败"
eof

    bash /root/neutron-service-restart.sh 2>/dev/null || echo "警告: neutron 服务重启脚本执行失败"
else
    echo "警告: neutron 相关软件包安装失败"
fi

# 安装dashboard服务
echo "安装dashboard服务..."

if yum install -y openstack-dashboard; then
    if [ -f /etc/openstack-dashboard/local_settings ]; then
        cp /etc/openstack-dashboard/local_settings{,.bak}
    fi
    
    sed -i '/^OPENSTACK_HOST/s#127.0.0.1#'$HOST_NAME'#' /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 修改 OPENSTACK_HOST 失败"
    sed -i "/^ALLOWED_HOSTS/s#\[.*\]#['*']#" /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 修改 ALLOWED_HOSTS 失败"
    sed -i '104s/.*/SESSION_ENGINE = '\''django.contrib.sessions.backends.cache'\''/' /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 修改 SESSION_ENGINE 失败"
    echo "OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True" >> /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 添加 KEYSTONE_MULTIDOMAIN_SUPPORT 失败"
    echo "OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = \"Default\"" >> /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 添加 KEYSTONE_DEFAULT_DOMAIN 失败"
    echo 'OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"' >> /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 添加 KEYSTONE_DEFAULT_ROLE 失败"

    echo "OPENSTACK_API_VERSIONS = {
    \"identity\": 3,
    \"image\": 2,
    \"volume\": 3,
}" >> /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 添加 API_VERSIONS 失败"

    echo "CACHES = {
'default': {
     'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
     'LOCATION': 'controller:11211',
    }
}" >> /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 添加 CACHES 失败"

    sed -i '147s/.*/TIME_ZONE = "Asia\/Shanghai"/' /etc/openstack-dashboard/local_settings 2>/dev/null || echo "警告: 修改 TIME_ZONE 失败"
    systemctl restart httpd.service memcached.service 2>/dev/null || echo "警告: httpd 或 memcached 服务重启失败"
else
    echo "警告: openstack-dashboard 安装失败"
fi

# 自动修复Dashboard配置问题
echo "自动修复Dashboard配置问题..."

# 1. 修复Dashboard配置文件
echo "修复local_settings配置..."
cat > /etc/openstack-dashboard/local_settings << 'EOF'
import os

from django.utils.translation import gettext_lazy as _

DEBUG = False

# 主机设置
OPENSTACK_HOST = "controller"
OPENSTACK_KEYSTONE_URL = "http://%s:5000/v3" % OPENSTACK_HOST

# 允许的主机
ALLOWED_HOSTS = ['*', 'localhost', '127.0.0.1', '$HOST_IP', 'controller']

# 会话设置
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'
SESSION_COOKIE_HTTPONLY = True
SESSION_EXPIRE_AT_BROWSER_CLOSE = True
SESSION_COOKIE_SECURE = False

# 缓存配置
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
        'LOCATION': 'controller:11211',
    }
}

# 密钥
SECRET_KEY = 'openstack-dashboard-secret-key'

# 认证配置
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "Default"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"

# API版本
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}

# 时区设置
TIME_ZONE = "Asia/Shanghai"

# 安全设置
SECURE_PROXY_SSL_HEADER = None
CSRF_COOKIE_SECURE = False
CSRF_COOKIE_HTTPONLY = False

# 站点URL
SITE_URL = '/dashboard/'
LOGIN_URL = '/dashboard/auth/login/'
LOGOUT_URL = '/dashboard/auth/logout/'
LOGIN_REDIRECT_URL = '/dashboard/'

# 静态文件设置
STATIC_URL = '/dashboard/static/'
MEDIA_URL = '/dashboard/media/'

# 禁用压缩以简化调试
COMPRESS_ENABLED = False
COMPRESS_OFFLINE = False

# 其他设置
HORIZON_CONFIG = {
    "user_home": 'openstack_dashboard.views.get_user_home',
    "ajax_queue_limit": 10,
    "auto_fade_alerts": {
        'delay': 3000,
        'fade_duration': 1500,
        'types': ['alert-success', 'alert-info']
    },
    "help_url": "http://docs.openstack.org/",
    "exceptions": {'recoverable': [], 'not_found': [], 'unauthorized': []},
}
EOF

# 2. 修复Apache配置
echo "修复Apache配置..."
cat > /etc/httpd/conf.d/openstack-dashboard.conf << 'EOF'
# 全局WSGI配置
WSGIDaemonProcess dashboard group=apache processes=3 threads=10 user=apache
WSGIProcessGroup dashboard
WSGISocketPrefix /var/run/httpd/wsgi

# Dashboard配置
<VirtualHost *:80>
    ServerName controller

    # 启用重写引擎并配置关键路径重写
    RewriteEngine On
    RewriteRule ^/api/(.*)$ /dashboard/api/$1 [L,PT]
    RewriteRule ^/header/(.*)$ /dashboard/header/$1 [L,PT]
    RewriteRule ^/settings/(.*)$ /dashboard/settings/$1 [L,PT]

    # 设置WSGIScriptAlias
    WSGIScriptAlias /dashboard /usr/share/openstack-dashboard/openstack_dashboard/wsgi.py

    # 确保/dashboard重定向到/dashboard/
    RedirectMatch 301 ^/dashboard$ /dashboard/

    # 静态文件配置
    Alias /dashboard/static /usr/share/openstack-dashboard/static
    
    <Directory /usr/share/openstack-dashboard/openstack_dashboard>
        Require all granted
        Options None
        AllowOverride None
        Header set X-Frame-Options SAMEORIGIN
        WSGIApplicationGroup %{GLOBAL}
    </Directory>
    
    <Directory /usr/share/openstack-dashboard/static>
        Require all granted
        Options None
        AllowOverride None
    </Directory>
    
    # 媒体文件
    Alias /dashboard/media /usr/share/openstack-dashboard/openstack_dashboard/media
    
    <Directory /usr/share/openstack-dashboard/openstack_dashboard/media>
        Require all granted
        Options None
        AllowOverride None
    </Directory>
    
    # 错误日志
    ErrorLog /var/log/httpd/dashboard_error.log
    CustomLog /var/log/httpd/dashboard_access.log combined
    LogLevel warn
</VirtualHost>
EOF

# 3. 清理重定向冲突
echo "清理重定向冲突..."
if [ -f /etc/httpd/conf.d/openstack-dashboard.conf ]; then
    # 删除可能导致冲突的重定向行
    sed -i '/Redirect \/dashboard \/dashboard/d' /etc/httpd/conf.d/openstack-dashboard.conf
fi

# 4. 设置正确的文件权限
echo "设置文件权限..."
chown -R root:apache /usr/share/openstack-dashboard/
chmod -R 755 /usr/share/openstack-dashboard/

# 特别设置静态文件目录权限
if [ -d /usr/share/openstack-dashboard/static ]; then
    chown -R apache:apache /usr/share/openstack-dashboard/static
    chmod -R 755 /usr/share/openstack-dashboard/static
fi

# 设置配置文件权限
chown -R apache:apache /etc/openstack-dashboard/
chmod -R 755 /etc/openstack-dashboard/

# 设置WSGI文件权限
if [ -f /usr/share/openstack-dashboard/openstack_dashboard/wsgi.py ]; then
    chown apache:apache /usr/share/openstack-dashboard/openstack_dashboard/wsgi.py
    chmod 644 /usr/share/openstack-dashboard/openstack_dashboard/wsgi.py
fi

# 5. 设置SELinux上下文（如果系统支持）
echo "设置SELinux上下文..."
if command -v setsebool &> /dev/null && command -v semanage &> /dev/null && command -v restorecon &> /dev/null; then
    setsebool -P httpd_can_network_connect on 2>/dev/null || echo "警告: 无法设置httpd_can_network_connect SELinux布尔值"
    setsebool -P httpd_execmem on 2>/dev/null || echo "警告: 无法设置httpd_execmem SELinux布尔值"
    
    if command -v semanage &> /dev/null; then
        semanage fcontext -a -t httpd_sys_content_t "/usr/share/openstack-dashboard(/.*)?" 2>/dev/null || echo "警告: 无法设置httpd_sys_content_t上下文"
        semanage fcontext -a -t httpd_sys_rw_content_t "/usr/share/openstack-dashboard/static(/.*)?" 2>/dev/null || echo "警告: 无法设置httpd_sys_rw_content_t上下文"
        restorecon -R -v /usr/share/openstack-dashboard/ 2>/dev/null || echo "警告: 无法恢复SELinux上下文"
    fi
else
    echo "SELinux工具未安装或不可用，跳过SELinux配置"
fi

# 6. 重新收集静态文件
echo "重新收集静态文件..."
if [ -d "/usr/share/openstack-dashboard/static" ]; then
    # 先清理旧的静态文件
    rm -rf /usr/share/openstack-dashboard/static/*
fi

# 运行collectstatic命令
if command -v python3 &> /dev/null && [ -f "/usr/share/openstack-dashboard/manage.py" ]; then
    python3 /usr/share/openstack-dashboard/manage.py collectstatic --noinput --clear 2>/dev/null || echo "警告: 静态文件收集失败"
else
    echo "警告: 无法找到python3或manage.py，跳过静态文件收集"
fi

# 7. 重启服务
echo "重启相关服务..."
systemctl restart memcached 2>/dev/null || echo "警告: memcached重启失败"
systemctl restart httpd 2>/dev/null || echo "警告: httpd重启失败"

# 8. 验证服务状态
echo "验证服务状态..."
if systemctl is-active --quiet httpd; then
    echo "HTTPD服务运行正常"
else
    echo "警告: HTTPD服务未运行"
fi

if systemctl is-active --quiet memcached; then
    echo "Memcached服务运行正常"
else
    echo "警告: Memcached服务未运行"
fi

# 9. 创建修复脚本供后续使用
cat > /root/fix-dashboard.sh << 'EOF'
#!/bin/bash
# OpenStack Dashboard修复脚本

# 设置中文环境
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# 错误处理函数
handle_error() {
    echo -e "\033[31m错误: $1\033[0m"
    exit 1
}

check_result() {
    if [ $? -ne 0 ]; then
        handle_error "$1"
    fi
}

echo "开始修复OpenStack Dashboard..."

# 重启服务
echo "正在重启服务..."
systemctl restart memcached
systemctl restart httpd
check_result "服务重启失败，请检查httpd和memcached状态"

# 检查服务状态
echo "检查服务状态..."
if systemctl is-active --quiet httpd; then
    echo "✓ Apache服务运行正常"
else
    echo -e "\033[31m✗ Apache服务未运行，请检查httpd服务状态\033[0m"
fi

if systemctl is-active --quiet memcached; then
    echo "✓ Memcached服务运行正常"
else
    echo -e "\033[31m✗ Memcached服务未运行，请检查memcached服务状态\033[0m"
fi

# 测试Dashboard访问
echo "测试Dashboard访问..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/dashboard/)
echo "HTTP状态码: $HTTP_CODE"
if [ "$HTTP_CODE" != "200" ]; then
    echo -e "\033[31m无法访问Dashboard，请检查服务是否正常运行（状态码: $HTTP_CODE）\033[0m"
else
    echo "✓ Dashboard访问正常"
fi

echo "修复完成！请清除浏览器缓存后访问 http://$HOST_IP/dashboard"
EOF

chmod +x /root/fix-dashboard.sh

echo "OpenStack安装和配置修复完成！"
echo "可以通过 http://$HOST_IP/dashboard 访问Dashboard"
echo "用户名: admin"
echo "密码: $ADMIN_PASS"
echo "作者： ZJT8848,链接： https://github.com/ZJT8848/openStack-in-openEuler"
echo "部分教程来源作者： huhy,链接： https://www.cnblogs.com/hoyeong/p/18793119"
echo "如果仍然遇到问题，请运行: bash /root/fix-dashboard.sh"