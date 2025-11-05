一键部署yum install -y git && git clone https://github.com/ZJT8848/openStack-in-openEuler.git /tmp/openstack && bash /tmp/openstack/openstack.sh
或者curl -sSL https://raw.githubusercontent.com/ZJT8848/openStack-in-openEuler/main/openstack.sh | bash
国内推荐yum install -y unzip && curl -L https://ghproxy.com/https://github.com/ZJT8848/openStack-in-openEuler/archive/refs/heads/main.zip -o /tmp/openstack.zip && unzip /tmp/openstack.zip -d /tmp/openstack && bash /tmp/openstack/openStack-in-openEuler-main/openstack.sh
或者yum install -y unzip wget && wget https://ghproxy.com/https://github.com/ZJT8848/openStack-in-openEuler/archive/refs/heads/main.zip -O /tmp/openstack.zip && unzip /tmp/openstack.zip -d /tmp/openstack && bash /tmp/openstack/openStack-in-openEuler-main/openstack.sh
这是一个实现openeuler一键部署openstack的脚本
