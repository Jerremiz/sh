#!/usr/bin/env bash

set -euo pipefail

# 必须以 root 用户直接运行，拒绝通过 sudo 提权运行
if [ "$EUID" -ne 0 ] || [ -n "${SUDO_USER-}" ] || [ -n "${SUDO_UID-}" ]; then
    echo "错误：请以 root 身份直接登录后运行此脚本（不要使用 sudo）。"
    echo "如果需要切换到 root，请使用：su - 然后再运行脚本。"
    exit 1
fi

# 读取系统信息
. /etc/os-release

if [ "${ID}" != "debian" ]; then
    echo "错误：此脚本仅支持 Debian。"
    exit 1
fi

# 检查根分区文件系统
ROOT_FSTYPE="$(findmnt -no FSTYPE /)"
if [ "$ROOT_FSTYPE" != "ext4" ]; then
    echo "错误：当前根分区文件系统是 ${ROOT_FSTYPE}，此脚本仅适用于 ext4。"
    echo "如果是 btrfs，需要使用 btrfs 专用 swapfile 创建方式。"
    exit 1
fi

# 显示当前内存和 swap 状态
echo "当前内存状态："
free -h

echo
echo "当前 swap 状态："
swapon --show || true

SWAPFILE="/swapfile"
SWAP_ALREADY_ON=0

# 检查 /swapfile 是否已经启用
if swapon --show=NAME --noheadings | grep -Fxq "$SWAPFILE"; then
    echo
    echo "检测到 ${SWAPFILE} 已经启用，将跳过创建步骤，仅检查持久化配置。"
    SWAP_ALREADY_ON=1
fi

# 如果 /swapfile 已存在但没有启用，停止，避免误覆盖
if [ "$SWAP_ALREADY_ON" -eq 0 ]; then
    if [ -e "$SWAPFILE" ] || [ -L "$SWAPFILE" ]; then
        echo
        echo "错误：${SWAPFILE} 已存在，但当前没有启用。"
        echo "请手动检查该文件后再继续，避免误覆盖重要文件。"
        exit 1
    fi
fi

# 清理未成功启用的半成品 swapfile
cleanup_swapfile() {
    if [ -e "$SWAPFILE" ] && ! swapon --show=NAME --noheadings | grep -Fxq "$SWAPFILE"; then
        echo
        echo "检测到 swap 创建失败，正在清理半成品文件：${SWAPFILE}"
        rm -f "$SWAPFILE"
    fi
}

# 校验 swap 大小格式
validate_swap_size() {
    local size="$1"

    if [[ "$size" =~ ^[1-9][0-9]*[MmGg]$ ]]; then
        return 0
    fi

    return 1
}

# 创建 swap 文件
if [ "$SWAP_ALREADY_ON" -eq 0 ]; then
    echo
    echo "请选择要创建的 swap 大小："
    echo "1) 1G"
    echo "2) 2G"
    echo "3) 自定义"

    read -r -p "请输入选择 (1、2 或 3): " swap_choice

    case "$swap_choice" in
        1)
            SWAPSIZE="1G"
            ;;
        2)
            SWAPSIZE="2G"
            ;;
        3)
            read -r -p "请输入 swap 大小，例如 512M、1G、2G: " SWAPSIZE

            if ! validate_swap_size "$SWAPSIZE"; then
                echo "错误：swap 大小格式无效。"
                echo "请使用类似 512M、1G、2G 这样的格式。"
                exit 1
            fi
            ;;
        *)
            echo "无效选择，使用默认 1G"
            SWAPSIZE="1G"
            ;;
    esac

    echo
    echo "将创建 ${SWAPSIZE} swap 文件：${SWAPFILE}"

    trap cleanup_swapfile ERR

    echo "正在创建 swap 文件"
    install -m 600 /dev/null "$SWAPFILE"
    fallocate -l "$SWAPSIZE" "$SWAPFILE"

    echo "正在初始化 swap"
    mkswap "$SWAPFILE"

    echo "正在启用 swap"
    swapon "$SWAPFILE"

    trap - ERR
fi

# 备份 fstab
echo
echo "备份 /etc/fstab"

cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"

# 写入 fstab，避免重复添加
# systemd 会在启动或 daemon-reload 时把 /etc/fstab 中的 swap 转换成原生 swap unit。
if ! grep -qE '^[[:space:]]*/swapfile[[:space:]]+none[[:space:]]+swap[[:space:]]+' /etc/fstab; then
    echo '/swapfile none swap defaults,nofail 0 0' >> /etc/fstab
    echo "已写入 /etc/fstab"
else
    echo "/etc/fstab 中已存在 ${SWAPFILE} 配置，跳过写入"
fi

systemctl daemon-reload

# 设置 swappiness
echo
echo "是否设置 vm.swappiness？"
echo "1) 是，设置为 10"
echo "2) 否，保持系统默认或当前配置"

read -r -p "请输入选择 (1 或 2): " swappiness_choice

case "$swappiness_choice" in
    1)
        cat > /etc/sysctl.d/99-swappiness.conf <<EOF
vm.swappiness=10
EOF

        sysctl --system
        ;;
    2)
        echo "跳过设置 swappiness"
        ;;
    *)
        echo "无效选择，跳过设置 swappiness"
        ;;
esac

# 输出最终状态
echo
echo "swap 配置完成"

echo
echo "当前 swap 状态："
swapon --show

echo
echo "当前内存状态："
free -h

echo
echo "当前 swappiness："
cat /proc/sys/vm/swappiness

echo
echo "所有步骤已完成"