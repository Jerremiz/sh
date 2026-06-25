#!/usr/bin/env bash

set -euo pipefail

# 必须以 root 用户直接运行，拒绝通过 sudo 提权运行
if [ "$EUID" -ne 0 ] || [ -n "${SUDO_USER-}" ] || [ -n "${SUDO_UID-}" ]; then
  echo "错误：请以 root 身份直接登录后运行此脚本（不要使用 sudo）。"
  echo "如果需要切换到 root，请使用：su - 或 sudo su - 然后再运行脚本。"
  exit 1
fi

echo "Debian 13 重装脚本"
echo "警告：此操作会清空主硬盘所有数据，包括所有分区！"
echo

# 安装 curl
echo "安装 curl"
apt update
apt install -y curl ca-certificates

# 选择下载源
echo
echo "请选择 reinstall.sh 下载源："
echo "1) GitHub 源"
echo "2) CNB 源"
echo

read -r -p "请输入选项 [1/2]，默认 1：" SOURCE_CHOICE
SOURCE_CHOICE="${SOURCE_CHOICE:-1}"

case "$SOURCE_CHOICE" in
  1)
    REINSTALL_URL="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
    ;;
  2)
    REINSTALL_URL="https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"
    ;;
  *)
    echo "错误：无效选项，只能输入 1 或 2。"
    exit 1
    ;;
esac

# 输入新系统用户名
echo
read -r -p "请输入新系统用户名，默认 root：" NEW_USERNAME
NEW_USERNAME="${NEW_USERNAME:-root}"

if [ -z "$NEW_USERNAME" ]; then
  echo "错误：用户名不能为空。"
  exit 1
fi

# 输入 SSH 公钥
echo
echo "请输入 SSH 公钥，直接粘贴 .pub 文件里的整行内容即可。"
read -r -p "SSH 公钥：" SSH_KEY

if [ -z "$SSH_KEY" ]; then
  echo "错误：SSH 公钥不能为空。"
  exit 1
fi

# 简单检查 SSH 公钥格式
case "$SSH_KEY" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *)
    ;;
  *)
    echo "错误：SSH 公钥格式看起来不正确。"
    echo "请确认你粘贴的是 .pub 公钥内容，而不是私钥。"
    exit 1
    ;;
esac

echo
echo "即将执行："
echo "系统：Debian 13"
echo "用户名：${NEW_USERNAME}"
echo "下载源：${REINSTALL_URL}"
echo "SSH 公钥：${SSH_KEY}"
echo

read -r -p "确认继续请输入 yes：" CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "已取消。"
  exit 0
fi

# 下载 reinstall.sh
echo
echo "下载 reinstall.sh"

REINSTALL_SCRIPT="reinstall.sh"
curl -fsSL -o "$REINSTALL_SCRIPT" "$REINSTALL_URL"

# 执行 Debian 13 重装配置
echo
echo "执行 Debian 13 重装配置"

bash "$REINSTALL_SCRIPT" debian 13 \
  --username "$NEW_USERNAME" \
  --ssh-key "$SSH_KEY"

echo
echo "重装配置已写入。"
echo "确认无误后，手动执行以下命令开始重装："
echo
echo "  reboot"
echo
echo "如果想在重启前取消重装，执行："
echo
echo "  sh reinstall.sh reset"