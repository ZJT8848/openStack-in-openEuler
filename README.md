这是一个实现openeuler一键部署openstack的脚本


一键部署yum install -y git && git clone https://github.com/ZJT8848/openStack-in-openEuler.git /tmp/openstack && bash /tmp/openstack/t_openstack.sh



出现【处理 delta 中: 100% (2/2), 完成.】卡死，请按回车Enter。



或者curl -sSL https://raw.githubusercontent.com/ZJT8848/openStack-in-openEuler/main/t_openstack.sh | bash

采用 BY-NC-SA 许可协议。转载请注明出处！https://creativecommons.org/licenses/by-nc-sa/4.0/

测试基于ESXI7.9虚拟机，单网卡ens33，IP192.168.1.204，最小化安装，OpenEuler22.03 LST SP4

已知BUG：网络检测还在调
