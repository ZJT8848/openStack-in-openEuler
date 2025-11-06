#!/bin/bash

# OpenStack环境初始化和安装脚本（单机版）
# 专为单机部署设计，移除了多机部署相关功能
# 定义是否为单机部署模式
SINGLE_NODE_DEPLOYMENT=true
# 定义当前节点的密码（默认密码）
HOST_PASS="000000"
# 定义中文错误处理函数
handle_error() {
    local error_msg="$1"
    local step="$2"
    echo -e "\033[31m错误: [$step] $error_msg\033[0m"
    echo -e "\033[31m详细错误位置: 在安装 $step 步骤时发生了 $error_msg 错误\033[0m"
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
# 获取本机IP地址（严格遵循Shell函数设计安全规范）
get_host_ip() {
    # 检查是否为交互式终端
    local is_interactive=0
    if [ -t 0 ]; then
        is_interactive=1
    fi

    # 获取ip命令的路径（避免PATH问题）
    local IP_CMD=$(command -v ip || echo "/sbin/ip" || echo "/usr/sbin/ip")
    if [ ! -x "$IP_CMD" ]; then
        echo "ip命令未找到，请安装iproute2工具包" >&2
        return 1
    fi
    # 获取所有非回环IPv4地址（精确过滤回环地址）
    local ips=($($IP_CMD -4 addr show 2>/dev/null | grep -E 'inet\s' | grep -v "127\\.0\\.0\\.1" | awk '{print $2}' | cut -d/ -f1))
    local count=${#ips[@]}
    if [ $count -eq 0 ]; then
        echo "未检测到有效IPv4地址" >&2
        return 1
    fi
    if [ $count -eq 1 ]; then
        printf '%s' "${ips[0]}"
        return 0
    else
        # 非交互式环境自动选择第一个IP
        if [ $is_interactive -eq 0 ]; then
            printf '%s' "${ips[0]}"
            return 0
        fi

        # 交互式环境才提示用户选择
        echo -e "\\n检测到多个网络接口，请选择要使用的IP地址：" >&2
        for i in "${!ips[@]}"; do
            echo "  [$i] ${ips[$i]}" >&2
        done
        read -p "请输入序号: " index
        if [[ $index =~ ^[0-9]+$ ]] && [ $index -lt $count ]; then
            printf '%s' "${ips[$index]}"
            return 0
        else
            echo "无效的序号选择" >&2
            return 1
        fi
    fi
}
# 安全调用IP检测函数（限制错误消息长度）
if ! HOST_IP=$(get_host_ip 2>&1); then
    # 限制错误消息长度为100字符，避免'文件过长'问题
    error_msg=$(echo "$HOST_IP" | tr -d '\n\r' | tr -cd '[:print:]' | cut -c1-100)
    handle_error "IP检测失败: $error_msg" "IP检测"
fi
# 双重清理确保HOST_IP纯净（仅清理换行符和回车符）
HOST_IP=$(echo "$HOST_IP" | tr -d '\n\r')
# 验证HOST_IP是否为有效IP格式
if ! [[ "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # 添加十六进制转储诊断（帮助识别隐藏字符）
    hex_dump=$(echo -n "$HOST_IP" | xxd -p 2>/dev/null || echo "无法生成十六进制转储")
    echo -e "\033[33m调试信息：HOST_IP的十六进制转储：$hex_dump\033[0m" >&2
    echo -e "\033[33m当前检测到的IP原始内容：'$HOST_IP'\033[0m" >&2
    handle_error "检测到的IP格式无效: $HOST_IP" "IP验证"
fi
# 附加验证：确保IP不是全0或回环地址
if [[ "$HOST_IP" =~ ^127\.0\.0\.1$ || "$HOST_IP" =~ ^0\.0\.0\.0$ ]]; then
    echo -e "\033[31m错误：检测到回环地址或无效地址: $HOST_IP\033[0m" >&2
    handle_error "IP地址无效（回环或全0）: $HOST_IP" "IP验证"
fi
# 根据主机IP自动推导网络段
NETWORK=$(echo $HOST_IP | awk -F. '{print $1"."$2"."$3".0/24"}')
# 创建中文欢迎界面
cat > /etc/motd <<EOF 
 ################################
 #     欢迎使用 OpenStack      #
 ################################
EOF
if [[ "$HOST_IP" =~ ^127\.0\.0\.1$ || "$HOST_IP" =~ ^0\.0\.0\.0$ ]]; then
    echo -e "\033[31m错误：检测到回环地址或无效地址: $HOST_IP\033[0m" >&2
    handle_error "IP地址无效（回环或全0）: $HOST_IP" "IP验证"
fi
if ! [[ "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "\033[31m错误详情：检测到的IP格式无效: '$HOST_IP'\033[0m"
    echo -e "\033[33m当前IP检测输出：\033[0m"
    ip -4 addr show
    handle_error "IP格式验证失败" "IP验证"
fi
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
sed -i 's/SELINUX=.*/SELINUX=permissive/g' /etc/selinux/config
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
  ip=$(echo "$node" | awk '{print $1}' | tr -d '\\n\\r')
  hostname=$(echo "$node" | awk '{print $2}' | tr -d '\\n\\r')

  # 检查 hosts 文件中是否已存在相应的解析
  if grep -Fq "$ip $hostname" /etc/hosts; then
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
# 检查是否为单机部署模式
if [[ "$SINGLE_NODE_DEPLOYMENT" == true ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 检测到单机部署模式，跳过SSH密钥分发流程" >> "$LOG_FILE"
    echo -e "\033[32m✓ 单机部署模式：跳过SSH密钥分发流程\033[0m"
else
    # 在多机部署环境中，不需要分发SSH密钥到其他节点
    echo "$(date '+%Y-%m-%d %H:%M:%S') - 非单机部署模式：开始SSH密钥分发流程" >> "$LOG_FILE"
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
            # 提取IP和主机名
            ip=$(echo "$node" | awk '{print $1}' | tr -d '\n\r')
            hostname=$(echo "$node" | awk '{print $2}' | tr -d '\n\r')
            
            # 验证IP地址格式
            if ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo -e "\033[31m错误详情：无效的IP地址格式 '$ip'\\033[0m"
                handle_error "无效的IP地址格式: $ip" "SSH密钥分发"
            fi
            echo "$(date '+%Y-%m-%d %H:%M:%S') - 复制SSH密钥到节点 $hostname ($ip)" >> "$LOG_FILE"
            # 主机名格式验证
            if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]]; then
                echo -e "\\033[31m错误详情：无效的主机名格式 '$hostname'，应为字母数字和点连字符组合\\033[0m"
                echo -e "\\033[33m当前HOST_IP值: '$HOST_IP'\\033[0m"
                echo -e "\\033[33m当前节点信息: '$node'\\033[0m"
                handle_error "无效的主机名格式: $hostname" "SSH密钥分发"
            fi
            # 在尝试SSH连接前先测试网络连通性
            if ! ping -c 3 "$ip" >/dev/null 2>&1; then
                echo -e "\\033[31m错误详情：无法ping通目标主机 $hostname ($ip)，请检查网络连接\\033[0m"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 无法ping通节点 $hostname ($ip)" >> "$LOG_FILE"
                continue
            fi
        
            # 测试SSH端口连通性
            if ! timeout 10 bash -c "echo >/dev/tcp/$ip/22" 2>/dev/null; then
                echo -e "\\033[31m错误详情：无法连接到 $hostname ($ip) 的SSH端口，请检查防火墙和服务状态\\033[0m"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 无法连接到节点 $hostname ($ip) 的SSH端口" >> "$LOG_FILE"
                continue
            fi
            # 使用IP地址作为主机标识进行SSH密钥分发
            if sshpass -p "$HOST_PASS" ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i /root/.ssh/id_rsa.pub "root@$ip" 2>/dev/null; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 成功复制SSH密钥到节点 $hostname ($ip)" >> "$LOG_FILE"
            else
                echo -e "\\033[31m错误详情：SSH密钥复制到 $hostname ($ip) 失败，请检查网络连接和密码\\033[0m"
                echo -e "\\033[33m提示：请确认密码 '$HOST_PASS' 是否正确，以及目标主机SSH服务是否正常运行\\033[0m"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - 复制SSH密钥到节点 $hostname ($ip) 失败" >> "$LOG_FILE"
            fi
        done
    fi
fi
# 时间同步（单机部署模式）
echo "$(date '+%Y-%m-%d %H:%M:%S') - 配置单机时间同步" >> "$LOG_FILE"
name=$(hostname)
# 在单机部署模式下，将当前节点配置为时间同步源
sed -i '3,4s/^/#/g' /etc/chrony.conf
sed -i "7s/^/server $HOST_IP iburst/g" /etc/chrony.conf
echo "allow $NETWORK" >> /etc/chrony.conf
echo "local stratum 10" >> /etc/chrony.conf
# 重启并启用 chrony 服务
systemctl restart chronyd 2>/dev/null || echo "警告: chronyd 服务重启失败"
systemctl enable chronyd >> /dev/null 2>&1
echo -e "\033[32m✓ 配置单机时间同步完成\033[0m"
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
# 修复数据库初始化函数
setup_database() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    echo "配置数据库: $db_name"
    # 检查MariaDB服务状态
    if ! systemctl is-active --quiet mariadb; then
        echo -e "\033[33m警告: MariaDB服务未运行，正在启动...\033[0m"
        systemctl start mariadb
        sleep 5  # 增加等待时间
        if ! systemctl is-active --quiet mariadb; then
            # 检查端口状态
            if ! ss -tuln | grep ':3306' > /dev/null; then
                echo -e "\033[31m错误: MariaDB服务启动失败，3306端口未监听\033[0m"
            fi
            # 检查错误日志
            if [ -f /var/log/mariadb/mariadb.log ]; then
                echo -e "\033[31mMariaDB最近10行错误日志：\033[0m"
                tail -n 10 /var/log/mariadb/mariadb.log
            fi
            handle_error "MariaDB服务启动失败，请检查数据库服务状态" "数据库服务"
        fi
    fi
    # 检查是否已存在数据库
    if mysql -u root -e "SHOW DATABASES LIKE '$db_name';" 2>/dev/null | grep -q "$db_name"; then
        echo "数据库 $db_name 已存在，跳过创建"
    else
        # 创建数据库
        if ! mysql -u root -e "CREATE DATABASE $db_name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
            echo -e "\033[31m错误详情：MariaDB创建数据库失败，请检查权限\033[0m"
            handle_error "创建 $db_name 数据库失败，请检查MariaDB服务状态" "数据库创建"
        fi
    fi
    # 检查用户是否存在
    if mysql -u root -e "SELECT User FROM mysql.user WHERE User='$db_user';" 2>/dev/null | grep -q "$db_user"; then
        echo "数据库用户 $db_user 已存在，更新密码..."
        mysql -u root -e "ALTER USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"
        mysql -u root -e "ALTER USER '$db_user'@'%' IDENTIFIED BY '$db_pass';"
    else
        # 创建用户并授权
        if ! mysql -u root -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';"; then
            echo -e "\033[31m错误详情：本地用户创建失败，请检查数据库权限\033[0m"
            handle_error "本地用户创建失败" "数据库授权"
        fi
        if ! mysql -u root -e "CREATE USER '$db_user'@'%' IDENTIFIED BY '$db_pass';"; then
            echo -e "\033[31m错误详情：远程用户创建失败，请检查数据库权限\033[0m"
            handle_error "远程用户创建失败" "数据库授权"
        fi
        # 授权
        if ! mysql -u root -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"; then
            echo -e "\033[31m错误详情：本地用户授权失败，请检查数据库权限\033[0m"
            handle_error "本地用户授权失败" "数据库授权"
        fi
        if ! mysql -u root -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'%';"; then
            echo -e "\033[31m错误详情：远程用户授权失败，请检查数据库权限\033[0m"
            handle_error "远程用户授权失败" "数据库授权"
        fi
    fi
    echo "✓ 数据库 $db_name 配置成功"
}
# 使用增强版函数
setup_database keystone keystone $KEYSTONE_DBPASS
if yum install -y openstack-keystone httpd mod_wsgi; then
    if [ -f /etc/keystone/keystone.conf ]; then
        cp /etc/keystone/keystone.conf{,.bak}
    fi
    # 确保keystone日志目录存在且权限正确
    mkdir -p /var/log/keystone
    chown -R keystone:keystone /var/log/keystone
    chmod 750 /var/log/keystone
    # 确保keystone配置目录权限正确
    mkdir -p /etc/keystone/fernet-keys /etc/keystone/credential-keys
    chown -R keystone:keystone /etc/keystone/fernet-keys /etc/keystone/credential-keys
    chmod 700 /etc/keystone/fernet-keys /etc/keystone/credential-keys
    # 创建httpd日志目录（如果不存在）
    mkdir -p /var/log/httpd
    touch /var/log/httpd/keystone.log /var/log/httpd/keystone_access.log
    chown keystone:keystone /var/log/httpd/keystone.log /var/log/httpd/keystone_access.log
    chmod 644 /var/log/httpd/keystone.log /var/log/httpd/keystone_access.log
    # 强化变量清理 - 严格过滤非可打印字符，特别是IP地址
    HOST_IP=$(echo "$HOST_IP" | tr -d '\n\r' | tr -cd '0-9.')
    KEYSTONE_DBPASS=$(echo "$KEYSTONE_DBPASS" | tr -d '\n\r' | tr -cd '[:print:]')
    # 验证IP地址格式
    if ! [[ "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        handle_error "无效的HOST_IP地址格式: $HOST_IP" "配置生成"
    fi
    sudo yum reinstall openstack-keystone python3-keystone
#    [auth]
#methods = password,token
#password = keystone.auth.plugins.password.Password  # 替换<PASSWORD>
#token = keystone.auth.plugins.token.Token          # 替换<TOKEN>
    cat > /etc/keystone/keystone.conf << EOF
[DEFAULT]
log_dir = /var/log/keystone
log_file = keystone.log
debug = True
verbose = True
[database]
connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@$HOST_IP/keystone
[token]
provider = fernet
[fernet_tokens]
key_repository = /etc/keystone/fernet-keys/
[credential]
key_repository = /etc/keystone/credential-keys/
[auth]
methods = password,token
password = password
token = token
[endpoint_filter]
driver = sql
[identity]
driver = sql
[resource]
driver = sql
[assignment]
driver = sql
[role]
driver = sql
[policy]
driver = sql
[application_credential]
driver = sql
[wsgi]
application = keystone.server.wsgi_app:init_application
# 显式禁用LDAP配置以防止驱动加载错误
[ldap]
[identity_mapping]
[cache]
EOF

    # 验证配置文件格式完整性
    if ! grep -q "connection = mysql+pymysql://keystone:[^@]*@$HOST_IP/keystone" /etc/keystone/keystone.conf; then
        echo -e "\\033[31m错误: keystone.conf配置文件生成失败，内容不完整\\033[0m"
        echo "生成的配置文件内容："
        cat /etc/keystone/keystone.conf
        handle_error "keystone.conf配置文件生成失败" "配置生成"
    fi

    if command -v keystone-manage &> /dev/null; then
        # 确保数据库服务已启动
        if ! systemctl is-active --quiet mariadb; then
            echo -e "\033[33m警告: MariaDB服务未运行，正在启动...\033[0m"
            systemctl start mariadb
            sleep 5
            if ! systemctl is-active --quiet mariadb; then
                handle_error "MariaDB服务启动失败，请检查数据库服务状态" "数据库服务"
            fi
        fi

        echo "正在同步keystone数据库..."
        if ! su -s /bin/sh -c "keystone-manage db_sync" keystone; then
            echo -e "\033[31m错误详情：$(mysql -u root -e \"SHOW ERRORS;\" 2>/dev/null)\033[0m"
            handle_error "keystone数据库同步失败，请检查数据库连接和权限" "keystone数据库同步"
        fi

        keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone || \
            handle_error "keystone fernet 设置失败" "keystone初始化"
    else
        handle_error "keystone-manage 命令未找到" "keystone安装"
    fi
    
    # 确保httpd配置中的ServerName使用IP地址
    if grep -q "ServerName" /etc/httpd/conf/httpd.conf; then
        sed -i "s/ServerName.*/ServerName $HOST_IP/" /etc/httpd/conf/httpd.conf
    else
        echo "ServerName $HOST_IP" >> /etc/httpd/conf/httpd.conf
    fi
    
    # 添加额外的ServerName配置以避免Apache警告
    if ! grep -q "ServerName controller" /etc/httpd/conf/httpd.conf; then
        echo "ServerName controller" >> /etc/httpd/conf/httpd.conf
    fi
    
    # 创建自定义keystone WSGI配置文件
    cat > /etc/httpd/conf.d/wsgi-keystone.conf << EOF
Listen 5000
<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    LimitRequestBody 114688
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/httpd/keystone.log
    CustomLog /var/log/httpd/keystone_access.log combined
    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>
Alias /identity /usr/bin/keystone-wsgi-public
<Location /identity>
    SetHandler wsgi-script
    Options +ExecCGI
    WSGIProcessGroup keystone-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
</Location>
EOF

    # 确保日志文件存在且权限正确
    mkdir -p /var/log/httpd
    touch /var/log/httpd/keystone.log /var/log/httpd/keystone_access.log
    chown keystone:keystone /var/log/httpd/keystone.log /var/log/httpd/keystone_access.log
    chmod 644 /var/log/httpd/keystone.log /var/log/httpd/keystone_access.log

    systemctl enable --now httpd 2>/dev/null || echo "警告: httpd 服务启动失败"
    systemctl restart httpd 2>/dev/null || echo "警告: httpd 服务重启失败"
    
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone || \
            handle_error "keystone credential 设置失败" "keystone初始化"

        # 确保httpd服务启动
        MAX_RETRIES=3
        WAIT_TIME=5
        for ((i=1; i<=MAX_RETRIES; i++)); do
            # 检查并杀死占用5000端口的进程
            if ss -tuln | grep ':5000' > /dev/null; then
                echo -e "\\033[33m警告: 端口5000已被占用，正在清理...\\033[0m"
                fuser -k 5000/tcp 2>/dev/null
                sleep 2
            fi
            
            systemctl enable httpd 2>/dev/null || echo "警告: httpd 服务启用失败"
            systemctl start httpd 2>/dev/null || echo "警告: httpd 服务启动失败"
            
            if systemctl is-active --quiet httpd; then
                echo -e "\\033[32m✓ httpd 服务已启动\\033[0m"
                break
            else
                echo -e "\\033[33m警告: httpd 服务未运行 (尝试 $i/$MAX_RETRIES)，等待 $WAIT_TIME 秒后重试...\\033[0m"
                sleep $WAIT_TIME
                
                # 检查httpd错误日志
                if [ -f /var/log/httpd/error_log ]; then
                    echo -e "\\033[31mhttpd 最近10行错误日志：\\033[0m"
                    tail -n 10 /var/log/httpd/error_log
                fi
            fi
        done

        # 如果最终服务仍未运行
        if ! systemctl is-active --quiet httpd; then
            # 检查错误日志
            if [ -f /var/log/httpd/error_log ]; then
                echo -e "\\033[31mhttpd 详细错误日志：\\033[0m"
                tail -n 20 /var/log/httpd/error_log
            fi
            handle_error "httpd 服务无法启动，请检查Apache配置和日志" "服务启动"
        fi

        # 增强bootstrap错误处理
        echo "正在执行keystone bootstrap..."
        # 清理ADMIN_PASS变量，确保不含特殊字符
        ADMIN_PASS=$(echo "$ADMIN_PASS" | tr -d '\n\r' | tr -cd '[:print:]')
#  --bootstrap-password 000000 \
#  --bootstrap-admin-url http://192.168.1.204:5000/v3/ \
#  --bootstrap-internal-url http://192.168.1.204:5000/v3/ \
#  --bootstrap-public-url http://192.168.1.204:5000/v3/ \
#  --bootstrap-region-id RegionOne \
#  --debug
        
        for i in {1..3}; do
            if keystone-manage bootstrap \
                --bootstrap-password $ADMIN_PASS \
                --bootstrap-admin-url http://$HOST_IP:5000/v3/ \
                --bootstrap-internal-url http://$HOST_IP:5000/v3/ \
                --bootstrap-public-url http://$HOST_IP:5000/v3/ \
                --bootstrap-region-id RegionOne
                --debug; then
                echo -e "\\033[32m✓ keystone bootstrap 成功\\033[0m"
                break
            else
                echo -e "\\033[33m警告: keystone bootstrap 尝试 $i 失败，3秒后重试...\\033[0m"
                sleep 3
                
                # 检查并自动清理占用5000端口的进程
                if ss -tuln | grep ':5000' > /dev/null; then
                    echo -e "\\033[33m警告: 端口5000已被占用，正在清理...\\033[0m"
                    fuser -k 5000/tcp 2>/dev/null
                    sleep 2
                fi
                
                # 检查keystone日志
                if [ -f /var/log/keystone/keystone.log ]; then
                    echo -e "\\033[31m最近5行错误日志：\\033[0m"
                    grep -i 'error\|exception' /var/log/keystone/keystone.log | tail -n 5
                fi
                
                # 检查httpd错误日志
                if [ -f /var/log/httpd/error_log ]; then
                    echo -e "\\033[31mhttpd错误日志：\\033[0m"
                    grep -i 'error\|keystone' /var/log/httpd/error_log | tail -n 10
                fi
            fi
        done
    fi

    # 删除重复的httpd启动代码，避免冲突
    # 已在前面配置了httpd服务，此处不再重复启动

    # 增强服务验证机制
echo "正在验证keystone服务可用性..."
MAX_RETRIES=10
WAIT_TIME=10
for ((i=1; i<=MAX_RETRIES; i++)); do
    # 确保httpd服务已运行
    if ! systemctl is-active --quiet httpd; then
        echo -e "\033[31m错误: httpd 服务未运行，请检查Apache状态\033[0m"
        # 尝试重新启动httpd
        systemctl restart httpd 2>/dev/null || echo "警告: httpd 服务重启失败"
        sleep 3
    fi
    
    # 检查5000端口是否监听
    if ! ss -tuln | grep ':5000' > /dev/null; then
        echo -e "\033[31m错误: 5000端口未监听，请检查Apache配置\033[0m"
    fi
    
    # 检查keystone服务API是否可达
    if curl -s -o /dev/null -w "%{http_code}" http://$HOST_IP:5000/v3 > /dev/null; then
        echo -e "\033[32m✓ keystone API 可达\033[0m"
    else
        echo -e "\033[31m错误: keystone API 不可达\033[0m"
    fi

    if openstack token issue &> /dev/null; then
        echo -e "\033[32m✓ keystone服务验证成功\033[0m"
        break
    else
        echo -e "\033[33m警告: keystone服务验证失败 (尝试 $i/$MAX_RETRIES)，等待 $WAIT_TIME 秒后重试...\033[0m"
        sleep $WAIT_TIME
        
        # 检查服务状态
        if ! systemctl is-active --quiet httpd; then
            echo -e "\\033[31m错误: httpd 服务未运行，请检查Apache状态\\033[0m"
        fi
        
        # 检查keystone日志
        if [ -f /var/log/keystone/keystone.log ]; then
            echo -e "\\033[31m最近5行错误日志：\\033[0m"
            grep -i 'error' /var/log/keystone/keystone.log | tail -n 5
        fi
        
        # 检查httpd错误日志
        if [ -f /var/log/httpd/error_log ]; then
            echo -e "\\033[31mhttpd最近5行错误日志：\\033[0m"
            grep -i 'error' /var/log/httpd/error_log | tail -n 5
        fi
    fi
    
    # 如果是最后一次尝试，显示更多诊断信息
    if [ $i -eq $MAX_RETRIES ]; then
        echo -e "\\033[31m达到最大重试次数，显示详细诊断信息:\\033[0m"
        echo "检查端口监听状态:"
        ss -tuln | grep 5000 || echo "端口5000未监听"
        # 显示占用5000端口的进程信息
        if ss -tuln | grep ':5000' > /dev/null; then
            echo "当前占用5000端口的进程:"
            lsof -i :5000 2>/dev/null || netstat -tlnp | grep :5000
        fi
        
        echo "检查httpd配置:"
        httpd -t 2>&1 || echo "httpd配置检查失败"
        
        if [ -f /etc/keystone/keystone.conf ]; then
            echo "检查keystone配置文件关键内容:"
            grep -E "(^connection|^provider)" /etc/keystone/keystone.conf
        fi
    fi
done

# 如果最终验证失败
if ! openstack token issue &> /dev/null; then
    echo -e "\\033[31m详细错误日志：\\033[0m"
    if [ -f /var/log/keystone/keystone.log ]; then
        tail -n 20 /var/log/keystone/keystone.log
    else
        echo "无法找到keystone日志文件"
    fi
    # 添加端口诊断信息
    echo -e "\\033[31m当前端口状态：\\033[0m"
    ss -tuln | grep ':5000' || echo "端口5000未被监听"
    handle_error "keystone bootstrap 失败，请检查/var/log/keystone/keystone.log" "keystone初始化"
fi
    else
        handle_error "keystone-manage 命令未找到" "keystone安装"
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
export OS_AUTH_URL=http://$HOST_IP:5000/v3
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
    mysql -uroot -e "create database IF NOT EXISTS glance ;" 2>/dev/null || echo "警告: 创建 glance 数据库失败"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS' ;" 2>/dev/null || echo "警告: 授权 glance 数据库失败"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS' ;" 2>/dev/null || echo "警告: 授权 glance 数据库失败"
else
    echo "警告: 数据库不可用，跳过 glance 数据库配置"
fi

# 增强服务验证机制
echo "正在验证keystone服务可用性..."
MAX_RETRIES=5
WAIT_TIME=5
for ((i=1; i<=MAX_RETRIES; i++)); do
    if openstack token issue &> /dev/null; then
        echo -e "\033[32m✓ keystone服务验证成功\033[0m"
        break
    else
        echo -e "\033[33m警告: keystone服务验证失败 (尝试 $i/$MAX_RETRIES)，等待 $WAIT_TIME 秒后重试...\033[0m"
        sleep $WAIT_TIME
        
        # 检查服务状态
        if ! systemctl is-active --quiet httpd; then
            echo -e "\033[31m错误: httpd 服务未运行，请检查Apache状态\033[0m"
        fi
        
        # 检查keystone日志
        if [ -f /var/log/keystone/keystone.log ]; then
            echo -e "\033[31m最近5行错误日志：\033[0m"
            grep -i 'error' /var/log/keystone/keystone.log | tail -n 5
        fi
    fi
done

if ! openstack token issue &> /dev/null; then
    echo -e "\033[31m详细错误日志：\033[0m"
    if [ -f /var/log/keystone/keystone.log ]; then
        tail -n 20 /var/log/keystone/keystone.log
    else
        echo "无法找到keystone日志文件"
    fi
    handle_error "glance服务依赖的keystone服务未就绪" "服务依赖检查"
fi

if command -v openstack &> /dev/null; then
    echo "创建glance用户..."
    if ! openstack user create --domain $DOMAIN_NAME --password $GLANCE_PASS glance; then
        echo -e "\033[31m错误详情：检查keystone服务状态\033[0m"
        handle_error "创建 glance 用户失败，请检查keystone服务状态" "glance初始化"
    fi
    
    echo "添加glance角色..."
    if ! openstack role add --project service --user glance admin; then
        handle_error "添加 glance 角色失败" "glance初始化"
    fi
    
    echo "创建glance服务..."
    if ! openstack service create --name glance --description "OpenStack Image" image; then
        handle_error "创建 glance 服务失败" "glance初始化"
    fi
    
    echo "创建glance public端点..."
    if ! openstack endpoint create --region RegionOne image public http://$HOST_IP:9292; then
        handle_error "创建 glance public 端点失败" "glance初始化"
    fi
    
    echo "创建glance internal端点..."
    if ! openstack endpoint create --region RegionOne image internal http://$HOST_IP:9292; then
        handle_error "创建 glance internal 端点失败" "glance初始化"
    fi
    
    echo "创建glance admin端点..."
    if ! openstack endpoint create --region RegionOne image admin http://$HOST_IP:9292; then
        handle_error "创建 glance admin 端点失败" "glance初始化"
    fi
else
    handle_error "openstack 命令未找到，无法配置glance服务" "glance安装"
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
connection = mysql+pymysql://glance:$GLANCE_DBPASS@$HOST_IP/glance
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
        echo "正在同步glance数据库..."
        if ! su -s /bin/sh -c "glance-manage db_sync" glance; then
            echo -e "\033[31m错误详情：检查/var/log/glance/api.log中的错误\033[0m"
            handle_error "glance数据库同步失败，请检查keystone服务状态和数据库配置" "glance初始化"
        fi
    else
        handle_error "glance-manage 命令未找到" "glance安装"
    fi
    
    systemctl enable --now openstack-glance-api.service 2>/dev/null || \
        handle_error "glance-api 服务启动失败" "glance服务"
    systemctl restart openstack-glance-api 2>/dev/null || \
        handle_error "glance-api 服务重启失败" "glance服务"
else
    handle_error "glance 相关软件包安装失败" "glance安装"
fi

# 安装placement服务
echo "安装placement服务..."

# 检查数据库是否可用
if command -v mysql &> /dev/null; then
    # placement mysql
    mysql -uroot -e "CREATE DATABASE placement;" 2>/dev/null || \
        echo "警告: 创建 placement 数据库失败"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_DBPASS';" 2>/dev/null || \
        echo "警告: 授权 placement 数据库失败"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_DBPASS';" 2>/dev/null || \
        echo "警告: 授权 placement 数据库失败"
else
    echo "警告: 数据库不可用，跳过 placement 数据库配置"
fi

# 增强服务验证机制
echo "正在验证keystone服务可用性..."
MAX_RETRIES=5
WAIT_TIME=5
for ((i=1; i<=MAX_RETRIES; i++)); do
    if openstack token issue &> /dev/null; then
        echo -e "\033[32m✓ keystone服务验证成功\033[0m"
        break
    else
        echo -e "\033[33m警告: keystone服务验证失败 (尝试 $i/$MAX_RETRIES)，等待 $WAIT_TIME 秒后重试...\033[0m"
        sleep $WAIT_TIME
        
        # 检查服务状态
        if ! systemctl is-active --quiet httpd; then
            echo -e "\033[31m错误: httpd 服务未运行，请检查Apache状态\033[0m"
        fi
        
        # 检查keystone日志
        if [ -f /var/log/keystone/keystone.log ]; then
            echo -e "\033[31m最近5行错误日志：\033[0m"
            grep -i 'error' /var/log/keystone/keystone.log | tail -n 5
        fi
    fi
done

if ! openstack token issue &> /dev/null; then
    echo -e "\033[31m详细错误日志：\033[0m"
    if [ -f /var/log/keystone/keystone.log ]; then
        tail -n 20 /var/log/keystone/keystone.log
    else
        echo "无法找到keystone日志文件"
    fi
    handle_error "placement服务依赖的keystone服务未就绪" "服务依赖检查"
fi

if command -v openstack &> /dev/null; then
    echo "创建placement用户..."
    if ! openstack user create --domain $DOMAIN_NAME --password $PLACEMENT_PASS placement; then
        echo -e "\033[31m错误详情：检查keystone服务状态\033[0m"
        handle_error "创建 placement 用户失败，请检查keystone服务状态" "placement初始化"
    fi
    
    echo "添加placement角色..."
    if ! openstack role add --project service --user placement admin; then
        handle_error "添加 placement 角色失败" "placement初始化"
    fi
    
    echo "创建placement服务..."
    if ! openstack service create --name placement --description "Placement API" placement; then
        handle_error "创建 placement 服务失败" "placement初始化"
    fi
    
    echo "创建placement public端点..."
    if ! openstack endpoint create --region RegionOne placement public http://$HOST_NAME:8778; then
        handle_error "创建 placement public 端点失败" "placement初始化"
    fi
    
    echo "创建placement internal端点..."
    if ! openstack endpoint create --region RegionOne placement internal http://$HOST_NAME:8778; then
        handle_error "创建 placement internal 端点失败" "placement初始化"
    fi
    
    echo "创建placement admin端点..."
    if ! openstack endpoint create --region RegionOne placement admin http://$HOST_NAME:8778; then
        handle_error "创建 placement admin 端点失败" "placement初始化"
    fi
else
    handle_error "openstack 命令未找到，无法配置placement服务" "placement安装"
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
connection = mysql+pymysql://placement:$PLACEMENT_DBPASS@$HOST_IP/placement
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

# 增强服务依赖检查
echo "正在验证keystone服务可用性..."
MAX_RETRIES=5
WAIT_TIME=5
for ((i=1; i<=MAX_RETRIES; i++)); do
    if openstack token issue &> /dev/null; then
        echo -e "\033[32m✓ keystone服务验证成功\033[0m"
        break
    else
        echo -e "\033[33m警告: keystone服务验证失败 (尝试 $i/$MAX_RETRIES)，等待 $WAIT_TIME 秒后重试...\033[0m"
        sleep $WAIT_TIME
        
        # 检查服务状态
        if ! systemctl is-active --quiet httpd; then
            echo -e "\033[31m错误: httpd 服务未运行，请检查Apache状态\033[0m"
        fi
        
        # 检查keystone日志
        if [ -f /var/log/keystone/keystone.log ]; then
            echo -e "\033[31m最近5行错误日志：\033[0m"
            grep -i 'error' /var/log/keystone/keystone.log | tail -n 5
        fi
    fi
done

if ! openstack token issue &> /dev/null; then
    echo -e "\033[31m详细错误日志：\033[0m"
    if [ -f /var/log/keystone/keystone.log ]; then
        tail -n 20 /var/log/keystone/keystone.log
    else
        echo "无法找到keystone日志文件"
    fi
    handle_error "nova服务依赖的keystone服务未就绪" "服务依赖检查"
fi

# 检查数据库是否可用
if command -v mysql &> /dev/null; then
    # 确保数据库服务已启动
    if ! systemctl is-active --quiet mariadb; then
        echo -e "\033[33m警告: MariaDB服务未运行，正在启动...\033[0m"
        systemctl start mariadb
        sleep 5
        if ! systemctl is-active --quiet mariadb; then
            handle_error "MariaDB服务启动失败，请检查数据库服务状态" "数据库服务"
        fi
    fi

    # nova mysql
    echo "创建nova数据库..."
    mysql -uroot -e "create database IF NOT EXISTS nova;" || \
        handle_error "创建 nova 数据库失败，请检查MariaDB服务状态" "数据库创建"
    mysql -uroot -e "create database IF NOT EXISTS nova_api;" || \
        handle_error "创建 nova_api 数据库失败" "数据库创建"
    mysql -uroot -e "create database IF NOT EXISTS nova_cell0;" || \
        handle_error "创建 nova_cell0 数据库失败" "数据库创建"

    echo "授权nova数据库..."
    mysql -uroot -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';" || \
        handle_error "本地授权 nova 数据库失败" "数据库授权"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';" || \
        handle_error "远程授权 nova 数据库失败" "数据库授权"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';" || \
        handle_error "本地授权 nova_api 数据库失败" "数据库授权"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';" || \
        handle_error "远程授权 nova_api 数据库失败" "数据库授权"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';" || \
        handle_error "本地授权 nova_cell0 数据库失败" "数据库授权"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';" || \
        handle_error "远程授权 nova_cell0 数据库失败" "数据库授权"
else
    handle_error "数据库客户端不可用，无法配置nova数据库" "数据库依赖"
fi

if command -v openstack &> /dev/null; then
    echo "创建nova用户..."
    if ! openstack user create --domain $DOMAIN_NAME --password $NOVA_PASS nova; then
        echo -e "\033[31m错误详情：检查keystone服务状态\033[0m"
        handle_error "创建 nova 用户失败，请检查keystone服务状态" "nova初始化"
    fi
    
    echo "添加nova角色..."
    if ! openstack role add --project service --user nova admin; then
        handle_error "添加 nova 角色失败" "nova初始化"
    fi
    
    echo "创建nova服务..."
    if ! openstack service create --name nova --description "OpenStack Compute" compute; then
        handle_error "创建 nova 服务失败" "nova初始化"
    fi
    
    echo "创建nova public端点..."
    if ! openstack endpoint create --region RegionOne compute public http://$HOST_NAME:8774/v2.1; then
        handle_error "创建 nova public 端点失败" "nova初始化"
    fi
    
    echo "创建nova internal端点..."
    if ! openstack endpoint create --region RegionOne compute internal http://$HOST_NAME:8774/v2.1; then
        handle_error "创建 nova internal 端点失败" "nova初始化"
    fi
    
    echo "创建nova admin端点..."
    if ! openstack endpoint create --region RegionOne compute admin http://$HOST_NAME:8774/v2.1; then
        handle_error "创建 nova admin 端点失败" "nova初始化"
    fi
else
    handle_error "openstack 命令未找到，无法配置nova服务" "nova安装"
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
connection = mysql+pymysql://nova:$NOVA_DBPASS@$HOST_IP/nova_api
[barbican]
[cache]
[cinder]
[compute]
[conductor]
[console]
[consoleauth]
[cors]
[database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@$HOST_IP/nova
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

    echo "同步nova数据库..."
    if command -v nova-manage &> /dev/null; then
        su -s /bin/sh -c "nova-manage api_db sync" nova || \
            handle_error "nova api 数据库同步失败" "数据库同步"
        su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova || \
            handle_error "nova map_cell0 失败" "cell管理"
        su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova || \
            handle_error "nova create_cell 失败" "cell管理"
        su -s /bin/sh -c "nova-manage db sync" nova || \
            handle_error "nova 数据库同步失败" "数据库同步"
        su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova || \
            handle_error "nova list_cells 失败" "cell管理"
    else
        handle_error "nova-manage 命令未找到" "nova安装"
    fi

    echo "启动nova服务..."
    systemctl enable --now openstack-nova-api.service openstack-nova-scheduler.service openstack-nova-conductor.service openstack-nova-novncproxy.service || \
        handle_error "nova 核心服务启动失败" "服务启动"
    systemctl enable --now libvirtd.service openstack-nova-compute.service || \
        handle_error "nova 计算服务启动失败" "服务启动"
    systemctl restart libvirtd.service || \
        handle_error "libvirtd 服务重启失败" "服务启动"

    # 增强服务状态检查
    echo "正在检查nova服务状态..."
    REQUIRED_SERVICES=(
        "openstack-nova-api"
        "openstack-nova-scheduler"
        "openstack-nova-conductor"
        "openstack-nova-novncproxy"
        "libvirtd"
        "openstack-nova-compute"
    )

    for service in "${REQUIRED_SERVICES[@]}"; do
        echo "检查 $service 服务状态..."
        if ! systemctl is-active --quiet "$service"; then
            echo -e "\033[31m错误: $service 服务未运行，尝试重启...\033[0m"
            
            # 尝试重启服务
            systemctl restart "$service" || echo -e "\033[33m警告: 无法重启 $service 服务\033[0m"
            
            # 检查服务状态
            sleep 3
            if ! systemctl is-active --quiet "$service"; then
                echo -e "\033[31m严重错误: $service 服务重启失败\033[0m"
                
                # 检查服务日志
                if [ -f "/var/log/nova/$(basename "$service").log" ]; then
                    echo -e "\033[31m$service 最近10行错误日志：\033[0m"
                    grep -i 'error' "/var/log/nova/$(basename "$service").log" | tail -n 10
                else
                    echo -e "\033[31m无法找到 $service 日志文件\033[0m"
                fi
                
                # 检查数据库连接
                if [[ "$service" == *"nova"* ]]; then
                    echo -e "\033[31m检查数据库连接状态...\033[0m"
                    mysql -h $HOST_IP -u nova -p$NOVA_DBPASS -e "SHOW DATABASES;" 2>/dev/null || \
                        echo -e "\033[31m数据库连接失败，请检查数据库服务状态\033[0m"
                fi
                
                handle_error "$service 服务无法启动，请检查日志" "服务状态检查"
            else
                echo -e "\033[32m✓ $service 服务已成功启动\033[0m"
            fi
        else
            echo -e "\033[32m✓ $service 服务运行正常\033[0m"
        fi
    done

    echo "发现nova主机..."
    if command -v nova-manage &> /dev/null; then
        # 添加超时和重试机制
        MAX_RETRIES=3
        WAIT_TIME=10
        for ((i=1; i<=MAX_RETRIES; i++)); do
            echo "执行 cell_v2 discover_hosts (尝试 $i/$MAX_RETRIES)..."
            if su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova; then
                echo -e "\033[32m✓ nova discover_hosts 成功\033[0m"
                break
            else
                echo -e "\033[33m警告: nova discover_hosts 尝试 $i/$MAX_RETRIES 失败，等待 $WAIT_TIME 秒后重试...\033[0m"
                sleep $WAIT_TIME
            fi
        done
        
        if ! su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova; then
            echo -e "\033[31m错误详情：检查/var/log/nova/nova-manage.log中的错误\033[0m"
            handle_error "nova discover_hosts 失败" "cell管理"
        fi
    else
        handle_error "nova-manage 命令未找到" "nova安装"
    fi

    echo "重启nova服务..."
    bash /root/nova-service-restart.sh || \
        echo -e "\033[33m警告: nova 服务重启脚本执行失败，建议手动重启\033[0m"

    # 增强最终验证
    echo "执行最终服务验证..."
    if ! openstack compute service list; then
        echo -e "\033[31m错误详情：nova服务状态异常，请检查compute服务\033[0m"
        handle_error "nova服务验证失败" "服务验证"
    fi
    
    if ! openstack hypervisor list; then
        echo -e "\033[31m错误详情：计算节点未注册，请检查hypervisor状态\033[0m"
        handle_error "计算节点注册失败" "服务验证"
    fi

else
    handle_error "nova 相关软件包安装失败" "nova安装"
fi

# 安装neutron服务
echo "安装neutron服务..."

# 检查数据库是否可用
if command -v mysql &> /dev/null; then
    # neutron mysql
    mysql -uroot -e "create database IF NOT EXISTS neutron ;" 2>/dev/null || echo "警告: 创建 neutron 数据库失败"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS' ;" 2>/dev/null || echo "警告: 授权 neutron 数据库失败"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS' ;" 2>/dev/null || echo "警告: 授权 neutron 数据库失败"
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
connection = mysql+pymysql://neutron:$NEUTRON_DBPASS@$HOST_IP/neutron
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