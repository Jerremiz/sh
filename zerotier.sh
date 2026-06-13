#!/usr/bin/env bash

set -euo pipefail

# 必须以 root 用户直接运行，拒绝通过 sudo 提权运行
if [ "$EUID" -ne 0 ] || [ -n "${SUDO_USER-}" ] || [ -n "${SUDO_UID-}" ]; then
  echo "错误：请以 root 身份直接登录后运行此脚本（不要使用 sudo）。"
  echo "如果需要切换到 root，请使用：su - 或 sudo su - 然后再运行脚本。"
  exit 1
fi

echo "ZeroTier 全隧道出口节点安装脚本"
echo

read -p "请输入 ZeroTier 网络 ID: " ZT_NETWORK_ID
read -p "请输入公网出口网卡名称，例如 eth0 / ens3: " WAN_IF
read -p "请输入 ZeroTier 网卡名称，例如 ztabcdefg: " ZT_IF

echo
echo "ZeroTier 网络 ID: $ZT_NETWORK_ID"
echo "公网出口网卡: $WAN_IF"
echo "ZeroTier 网卡: $ZT_IF"
echo

read -p "确认继续安装并配置？[y/N]: " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
 echo "已取消"
 exit 0
fi

# 安装依赖
apt update
apt install curl iptables-persistent -y

# 安装 ZeroTier
echo
echo "安装 ZeroTier"

if command -v zerotier-cli >/dev/null 2>&1; then
 echo "ZeroTier 已安装，跳过安装"
else
 curl -s https://install.zerotier.com | bash
fi

# 启动 ZeroTier 服务
echo
echo "启动 ZeroTier 服务"

systemctl enable --now zerotier-one

# 加入 ZeroTier 网络
echo
echo "加入 ZeroTier 网络"

zerotier-cli join "$ZT_NETWORK_ID" || true

echo
echo "请现在到 ZeroTier Central 后台授权这台设备"
echo "授权后，确认这台服务器已经获得 ZeroTier IP"
echo

read -p "授权完成后按回车继续..."

# 开启 IPv4 转发
echo
echo "开启 IPv4 转发"

cat > /etc/sysctl.d/99-zerotier-exit-node.conf <<EOF
net.ipv4.ip_forward = 1
EOF

sysctl -p /etc/sysctl.d/99-zerotier-exit-node.conf

# 配置 iptables NAT
echo
echo "配置 iptables 转发规则"

iptables -t nat -C POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
iptables -C FORWARD -i "$ZT_IF" -o "$WAN_IF" -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$ZT_IF" -o "$WAN_IF" -j ACCEPT
iptables -C FORWARD -i "$WAN_IF" -o "$ZT_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$WAN_IF" -o "$ZT_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT

# 保存 iptables 规则
echo
echo "保存 iptables 规则"

netfilter-persistent save

echo
echo "ZeroTier 出口节点配置完成"
echo
echo "接下来还需要到 ZeroTier Central 后台手动添加默认路由："
echo
echo "0.0.0.0/0 via 这台服务器的 ZeroTier IP"
echo
echo "然后在需要走全隧道的客户端上启用 Allow Default"
echo
echo "Linux 客户端命令："
echo "zerotier-cli set $ZT_NETWORK_ID allowDefault=1"