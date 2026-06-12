#!/usr/bin/env bash
set -euo pipefail

# 必须以 root 用户直接运行，拒绝通过 sudo 提权运行
if [ "$EUID" -ne 0 ] || [ -n "${SUDO_USER-}" ] || [ -n "${SUDO_UID-}" ]; then
  echo "错误：请以 root 身份直接登录后运行此脚本（不要使用 sudo）。"
  echo "如果需要切换到 root，请使用：su - 或 sudo su - 然后再运行脚本。"
  exit 1
fi


# 读取系统信息并换源
. /etc/os-release

if [ "${ID}" != "debian" ]; then
  echo "错误：此脚本仅支持 Debian。"
  exit 1
fi

echo "请选择您要使用的软件源："
echo "1) 默认源 (deb.debian.org)"
echo "2) 南科大源 (mirrors.sustech.edu.cn)"
read -r -p "请输入选择 (1 或 2): " source_choice

case "$source_choice" in
  1)
    echo "选择了默认源"
    DEBIAN_MIRROR="http://deb.debian.org/debian"
    SECURITY_MIRROR="http://deb.debian.org/debian-security"
    ;;
  2)
    echo "选择了南科大源"
    DEBIAN_MIRROR="https://mirrors.sustech.edu.cn/debian"
    SECURITY_MIRROR="https://mirrors.sustech.edu.cn/debian-security"
    ;;
  *)
    echo "无效选择，使用默认源"
    DEBIAN_MIRROR="http://deb.debian.org/debian"
    SECURITY_MIRROR="http://deb.debian.org/debian-security"
    ;;
esac

# 备份旧 sources.list，避免重复源
if [ -f /etc/apt/sources.list ]; then
  mv /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)"
fi

# 写入 Debian 13 推荐的 deb822 源格式
cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: ${DEBIAN_MIRROR}
Suites: ${VERSION_CODENAME} ${VERSION_CODENAME}-updates ${VERSION_CODENAME}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${SECURITY_MIRROR}
Suites: ${VERSION_CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF


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

# 安装 cockpit
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
wget https://github.com/cockpit-project/cockpit-files/releases/download/41/cockpit-files-41.tar.xz # 文件管理器
wget https://github.com/Jerremiz/cockpit-docker/releases/download/17/cockpit-docker-17.tar.xz # docker面板

tar -xf cockpit-files-41.tar.xz
tar -xf cockpit-docker-17.tar.xz

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
read -r -p "请输入选择 (1 或 2): " docker_choice

if [ "$docker_choice" == "1" ]; then
  echo "清理可能冲突的旧 Docker 相关包"
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt remove -y "$pkg" 2>/dev/null || true
  done

  echo "请选择 Docker CE 软件源："
  echo "1) 官方源 (download.docker.com)"
  echo "2) 南科大源 (mirrors.sustech.edu.cn)"
  read -r -p "请输入选择 (1 或 2): " docker_source_choice

  case "$docker_source_choice" in
    1)
      echo "选择了 Docker 官方源"
      DOCKER_MIRROR="https://download.docker.com/linux/debian"
      ;;
    2)
      echo "选择了 Docker 南科大源"
      DOCKER_MIRROR="https://mirrors.sustech.edu.cn/docker-ce/linux/debian"
      ;;
    *)
      echo "无效选择，使用 Docker 官方源"
      DOCKER_MIRROR="https://download.docker.com/linux/debian"
      ;;
  esac

  echo "正在配置 Docker CE 软件源"

  apt install ca-certificates curl -y
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: ${DOCKER_MIRROR}
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt update
  apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
  systemctl enable --now docker

else
  echo "跳过安装 Docker"
fi

echo "所有步骤已完成"
echo "记得配置防火墙ip白名单"
echo "记得手动注释 /etc/network/interfaces 中的 auto 和 iface 行"
