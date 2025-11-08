🚀 OpenStack-in-openEuler：一键部署 OpenStack 的终极脚本
 
 为 openEuler 量身定制，全自动部署 OpenStack Train 版本
 
 🔧 极简安装 · ⚡ 极速部署 

<div align="center">
  <img src="https://img.shields.io/badge/OpenStack-Train-7710F1?logo=openstack&logoColor=white" />
  <img src="https://img.shields.io/badge/openEuler-22.03_LTS_SP4-0070B0?logo=redhat&logoColor=white" />
  <img src="https://img.shields.io/badge/Shell-Bash-4B8BBE?logo=gnubash&logoColor=white" />
  <img src="https://img.shields.io/badge/License-BY--NC--SA_4.0-FF69B4" />
  <img src="https://img.shields.io/badge/Status-Stable-brightgreen" />
</div>

<div align="center">
  <h3>✨ 一键部署 · 三分钟上线 · 开箱即用</h3>
</div>


🎯 项目简介

这是一个为 **openEuler** 深度优化的 **OpenStack 自动化部署脚本**，支持：

 ✅ openEuler 22.03 LTS SP4（实测）
 ✅ OpenStack Train 版本（稳定版）
 ✅ 全组件一键安装：Keystone, Glance, Nova, Neutron, Cinder, Horizon
 ✅ 支持 **卷服务（Cinder）**（Bata版）
 ✅ 图形化 Web 控制台（Horizon）

💡 无需手动配置，无需网络依赖，一键搞定！

🚀 一键部署（两种方式）

 方式一：Git 克隆安装（推荐）

yum install -y git && git clone https://github.com/ZJT8848/openStack-in-openEuler.git /tmp/openstack && bash /tmp/openstack/t_openstack.sh
⚠️ 注意：若出现 【处理 delta 中: 100% (2/2), 完成.】卡死，请按一次 回车 Enter 继续！

方式二：Curl 直接执行（无 Git 环境）
curl -sSL https://raw.githubusercontent.com/ZJT8848/openStack-in-openEuler/main/t_openstack.sh | bash
⚡ 更轻量，适合快速测试！

🧪 标准测试环境
项目	配置
虚拟化平台	VMware ESXi 7.9 (VMware Workstation 12.5)
操作系统	openEuler 22.03 LTS SP4（最小化安装）
CPU	4 核
内存	8 GB
硬盘	100GB（单盘）
网卡	ens33，静态 IP 192.168.1.204
✅ 标准版：仅需单盘，支持实例创建

💾 Bata版（卷服务）：需额外添加 50GB 硬盘（用于 Cinder 存储卷）

⚠️ 注意事项
🌙 夜间 21:00 - 03:00 为网络高延迟期，可能导致 yum 下载失败，请尽量避开！
🖥️ 建议使用 静态 IP，避免 DHCP 导致网络配置错误
🔌 确保虚拟机有足够资源（CPU、内存、磁盘）
🔐 脚本会自动关闭 SELinux 和 firewalld
🎨 安装完成后
访问 Web 控制台：
http://<你的IP>/dashboard
登录信息	内容
用户名	admin
密码	000000
🎉 恭喜！你的私有云已上线！

📄 许可协议
本项目采用 CC BY-NC-SA 4.0 许可协议。

📢 转载请注明出处。
🔗 协议详情：https://creativecommons.org/licenses/by-nc-sa/4.0/

🤝 贡献与反馈
欢迎提交 Issue 或 Pull Request！

🐞 发现 Bug？提个 Issue
💡 有优化建议？欢迎 Fork & PR！
📧 联系作者：ZJT8848（GitHub @ZJT8848）
📦 致谢
部分代码参考：huhy
OpenStack 官方文档
openEuler 社区
🌟 让 OpenStack 在 openEuler 上飞起来！

—— 由 ZJT8848 倾情打造，献给每一个热爱开源的你。
