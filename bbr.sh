#!/usr/bin/env bash

set -euo pipefail

# 必须以 root 用户直接运行，拒绝通过 sudo 提权运行
if [ "$EUID" -ne 0 ] || [ -n "${SUDO_USER-}" ] || [ -n "${SUDO_UID-}" ]; then
  echo "错误：请以 root 身份直接登录后运行此脚本（不要使用 sudo）。"
  echo "如果需要切换到 root，请使用：su - 或 sudo su - 然后再运行脚本。"
  exit 1
fi

. /etc/os-release

echo "当前系统：${PRETTY_NAME}"
echo "当前内核：$(uname -r)"

# 加载 BBR 内核模块
echo "加载 BBR 内核模块"
modprobe tcp_bbr

# 检查当前内核是否支持 BBR
echo "检查 BBR 支持状态"
available_cc="$(sysctl -n net.ipv4.tcp_available_congestion_control)"

if ! echo "$available_cc" | grep -qw bbr; then
  echo "错误：当前内核未检测到 BBR 支持。"
  echo "当前可用算法：${available_cc}"
  echo "请检查是否为容器环境，或当前内核是否包含 tcp_bbr 模块。"
  exit 1
fi

# 写入 BBR 配置
echo "写入 BBR 配置"

cat > /etc/sysctl.d/99-bbr.conf <<'EOF'
# 使用 fq 队列算法
# BBR 推荐搭配 fq，可以更稳定地控制发包节奏
net.core.default_qdisc=fq

# 使用 BBR 作为 TCP 拥塞控制算法
net.ipv4.tcp_congestion_control=bbr
EOF

# 设置开机自动加载 BBR 模块
echo "设置开机自动加载 BBR 模块"
echo tcp_bbr > /etc/modules-load.d/tcp_bbr.conf

# 立即应用 BBR 配置
echo "应用 BBR 配置"
sysctl -p /etc/sysctl.d/99-bbr.conf

# 验证 BBR 是否开启成功
echo "验证 BBR 状态"

current_cc="$(sysctl -n net.ipv4.tcp_congestion_control)"
current_qdisc="$(sysctl -n net.core.default_qdisc)"
echo "当前 TCP 拥塞控制算法：${current_cc}"
echo "当前默认队列算法：${current_qdisc}"

if [ "$current_cc" != "bbr" ] || [ "$current_qdisc" != "fq" ]; then
  echo "错误：BBR 未成功开启。"
  exit 1
fi

echo "BBR 开启成功"