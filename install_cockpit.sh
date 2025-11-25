#!/usr/bin/env bash
set -euo pipefail

# 必须以 root 用户直接运行，拒绝通过 sudo 提权运行
if [ "$EUID" -ne 0 ] || [ -n "${SUDO_USER-}" ] || [ -n "${SUDO_UID-}" ]; then
  echo "错误：请以 root 身份直接登录后运行此脚本（不要使用 sudo）。"
  echo "如果需要切换到 root，请使用：su - 或 sudo su - 然后再运行脚本。"
  exit 1
fi

# 更新系统并安装常用包
echo "更新系统并安装常用包"
apt update
apt install sudo vim lastlog2 curl wget build-essential gettext -y

# 安装并配置网络管理器
echo "安装并配置网络管理器"
apt install network-manager -y
systemctl disable --now systemd-networkd.socket
systemctl disable --now systemd-networkd
systemctl enable --now NetworkManager

# 为 Debian 系统添加 backports 源并安装 cockpit
echo "请选择您要使用的软件源："
echo "1) 默认源 (deb.debian.org)"
echo "2) 南科大源 (mirrors.sustech.edu.cn)"
read -p "请输入选择 (1 或 2): " source_choice

. /etc/os-release

if [ "$source_choice" == "1" ]; then
    echo "选择了默认源"
    echo "deb http://deb.debian.org/debian ${VERSION_CODENAME}-backports main" > /etc/apt/sources.list.d/backports.list
elif [ "$source_choice" == "2" ]; then
    echo "选择了南科大源"
    echo "deb http://mirrors.sustech.edu.cn/debian ${VERSION_CODENAME}-backports main" > /etc/apt/sources.list.d/backports.list
else
    echo "无效的选择，使用默认源"
    echo "deb http://deb.debian.org/debian ${VERSION_CODENAME}-backports main" > /etc/apt/sources.list.d/backports.list
fi

apt install -t ${VERSION_CODENAME}-backports cockpit -y

# 安装并启用 firewalld
echo "安装并启用 firewalld"
apt install firewalld -y
systemctl stop firewalld

# 创建下载目录并安装相关工具
echo "创建下载目录并安装工具"
mkdir -p ~/Downloads
cd ~/Downloads

# 下载并解压 cockpit 插件
echo "下载并解压 cockpit 插件"
wget https://github.com/cockpit-project/cockpit-files/releases/download/27/cockpit-files-27.tar.xz
wget https://github.com/chabad360/cockpit-docker/releases/download/16/cockpit-docker-16.tar.xz

tar -xf cockpit-files-27.tar.xz
tar -xf cockpit-docker-16.tar.xz

# 安装 cockpit 插件
echo "安装 cockpit 插件"
cd ~/Downloads/cockpit-files
make install

cd ~/Downloads/cockpit-docker
make install

# 安装 Docker
echo "是否安装 Docker？"
echo "1) 是"
echo "2) 否"
read -p "请输入选择 (1 或 2): " docker_choice

if [ "$docker_choice" == "1" ]; then
    echo "正在安装 Docker"
    curl -fsSL https://get.docker.com | sh
else
    echo "跳过安装 Docker"
fi

echo "所有步骤已完成"
echo "记得配置防火墙ip白名单"
echo "记得手动注释 /etc/network/interfaces 中的 auto 和 iface 行"
