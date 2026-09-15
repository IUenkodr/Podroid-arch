#!/bin/bash
# Podroid Arch Linux Master Bootstrap

echo "Podroid Arch Linux Bootstrapping..." > /dev/console

# 1. Sync Clock
PODROID_EPOCH=$(sed -n 's/.*podroid\.epoch=\([0-9]*\).*/\1/p' /proc/cmdline)
if [ -n "$PODROID_EPOCH" ] && [ "$PODROID_EPOCH" -gt 0 ] 2>/dev/null; then
    date -s "@$PODROID_EPOCH" >/dev/null 2>&1
fi

# 2. Base Mounts & Devpts
mount --make-rshared / 2>/dev/null
mkdir -p /dev/pts /dev/shm /dev/mqueue /sys/kernel/config
mountpoint -q /dev/pts    || mount -t devpts devpts /dev/pts -o gid=5,mode=0620,ptmxmode=0666,noexec,nosuid
mountpoint -q /dev/shm    || mount -t tmpfs tmpfs /dev/shm -o noexec,nosuid,nodev,size=64m
mountpoint -q /dev/mqueue || mount -t mqueue mqueue /dev/mqueue -o noexec,nosuid,nodev
mountpoint -q /sys/kernel/config || mount -t configfs -o nosuid,nodev,noexec configfs /sys/kernel/config

# 3. Networking
ip link set lo up 2>/dev/null
NETIF=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(lo|dummy|veth|podman|cni|docker|lxcbr|br-)' | head -1)

if [ -z "$NETIF" ]; then
    echo "Network Interface not found!" > /dev/console
else
    ip link set "$NETIF" up
    if grep -q 'podroid\.backend=avf' /proc/cmdline 2>/dev/null; then
        udhcpc -i "$NETIF" -q -f -n 2>/dev/null || true
    else
        ip addr add 10.0.2.15/24 dev "$NETIF" 2>/dev/null
        ip route add default via 10.0.2.2 dev "$NETIF" 2>/dev/null
        DNS_RAW=$(sed -n 's/.*podroid\.dns=\([0-9.,]*\).*/\1/p' /proc/cmdline 2>/dev/null)
        if [ -n "$DNS_RAW" ]; then
            printf "nameserver %s\nnameserver 8.8.8.8\n" "$DNS_RAW" > /etc/resolv.conf
        else
            printf "nameserver 10.0.2.3\nnameserver 8.8.8.8\n" > /etc/resolv.conf
        fi
    fi
fi

# 4. Container Storage Bind-Mounts
mkdir -p /mnt/persist/docker /var/lib/docker
mountpoint -q /var/lib/docker || mount --bind /mnt/persist/docker /var/lib/docker
mkdir -p /mnt/persist/containers /var/lib/containers/storage
mountpoint -q /var/lib/containers/storage || mount --bind /mnt/persist/containers /var/lib/containers/storage

# 5. ZRAM Setup
if [ -b /dev/zram0 ]; then
    _mem_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null
    echo $((_mem_kb * 1536)) > /sys/block/zram0/disksize 2>/dev/null
    mkswap /dev/zram0 >/dev/null 2>&1 && swapon -p 100 /dev/zram0 2>/dev/null
fi

# 6. Sysctl
sysctl -w net.ipv4.ip_forward=1
sysctl -w vm.overcommit_memory=1
