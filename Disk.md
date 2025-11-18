split each like into separate code blocks

Got it! Here's every command split into its own individual code block:

***

## Set Variables

```bash
SYSTEM_DRIVE="/dev/nvme1n1"
```

```bash
DEV_DRIVE="/dev/nvme0n1"
```

```bash
USERNAME="hbohlen"
```

***

## Partition 1TB System Drive

```bash
sudo sgdisk --zap-all "$SYSTEM_DRIVE"
```

```bash
sudo partprobe "$SYSTEM_DRIVE"
```

```bash
sudo sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System Partition" "$SYSTEM_DRIVE"
```

```bash
sudo sgdisk -n 2:0:0 -t 2:8300 -c 2:"CachyOS System" "$SYSTEM_DRIVE"
```

```bash
sudo sgdisk -A 1:set:2 "$SYSTEM_DRIVE"
```

```bash
sudo partprobe "$SYSTEM_DRIVE"
```

***

## Partition 2TB Development Drive

```bash
sudo sgdisk --zap-all "$DEV_DRIVE"
```

```bash
sudo partprobe "$DEV_DRIVE"
```

```bash
sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:"Development Data" "$DEV_DRIVE"
```

```bash
sudo partprobe "$DEV_DRIVE"
```

***

## Format Filesystems

```bash
sudo mkfs.fat -F32 -n "ESP" "${SYSTEM_DRIVE}p1"
```

```bash
sudo mkfs.btrfs -f -L "cachyos-system" "${SYSTEM_DRIVE}p2"
```

```bash
sudo mkfs.btrfs -f -L "cachyos-dev" "${DEV_DRIVE}p1"
```

***

## Mount Top-Level Btrfs Volumes

```bash
sudo mkdir -p /mnt/system-top
```

```bash
sudo mkdir -p /mnt/dev-top
```

```bash
sudo mount -o subvolid=5 "${SYSTEM_DRIVE}p2" /mnt/system-top
```

```bash
sudo mount -o subvolid=5 "${DEV_DRIVE}p1" /mnt/dev-top
```

***

## Create System Subvolumes

```bash
cd /mnt/system-top
```

```bash
sudo btrfs subvolume create @
```

```bash
sudo btrfs subvolume create @snapshots
```

```bash
sudo btrfs subvolume create @home
```

```bash
sudo btrfs subvolume create @var-log
```

```bash
sudo btrfs subvolume create @tmp
```

```bash
sudo btrfs subvolume create @cache-system
```

***

## Create Development Subvolumes

```bash
cd /mnt/dev-top
```

```bash
sudo btrfs subvolume create @dev
```

```bash
sudo btrfs subvolume create @nix
```

```bash
sudo btrfs subvolume create @containers
```

```bash
sudo btrfs subvolume create @cache-dev
```

```bash
sudo btrfs subvolume create @cargo
```

```bash
sudo btrfs subvolume create @rustup
```

```bash
sudo btrfs subvolume create @go
```

```bash
sudo btrfs subvolume create @local-share
```

```bash
sudo btrfs subvolume create @nvm
```

```bash
sudo btrfs subvolume create @bun
```

```bash
sudo btrfs subvolume create @claude-cache
```

***

## Unmount Top-Level

```bash
cd /
```

```bash
sudo umount /mnt/system-top
```

```bash
sudo umount /mnt/dev-top
```

```bash
sudo rmdir /mnt/system-top
```

```bash
sudo rmdir /mnt/dev-top
```

***

## Mount Root Filesystem

```bash
sudo mount -o subvol=@ "${SYSTEM_DRIVE}p2" /mnt
```

***

## Create Directory Structure

```bash
sudo mkdir -p /mnt/boot/efi
```

```bash
sudo mkdir -p /mnt/home
```

```bash
sudo mkdir -p /mnt/nix
```

```bash
sudo mkdir -p /mnt/var/lib/containers
```

```bash
sudo mkdir -p /mnt/.snapshots
```

```bash
sudo mkdir -p /mnt/var/log
```

```bash
sudo mkdir -p /mnt/tmp
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/dev
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/.cache
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/.cargo
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/.rustup
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/go
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/.local/share
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/.nvm
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/.bun
```

```bash
sudo mkdir -p /mnt/home/$USERNAME/.claude
```

***

## Mount ESP

```bash
sudo mount "${SYSTEM_DRIVE}p1" /mnt/boot/efi
```

***

## Mount System Subvolumes

```bash
sudo mount -o subvol=@snapshots "${SYSTEM_DRIVE}p2" /mnt/.snapshots
```

```bash
sudo mount -o subvol=@home "${SYSTEM_DRIVE}p2" /mnt/home
```

```bash
sudo mount -o subvol=@var-log "${SYSTEM_DRIVE}p2" /mnt/var/log
```

```bash
sudo mount -o subvol=@tmp "${SYSTEM_DRIVE}p2" /mnt/tmp
```

***

## Mount Development Subvolumes

```bash
sudo mount -o subvol=@dev "${DEV_DRIVE}p1" /mnt/home/$USERNAME/dev
```

```bash
sudo mount -o subvol=@nix "${DEV_DRIVE}p1" /mnt/nix
```

```bash
sudo mount -o subvol=@containers "${DEV_DRIVE}p1" /mnt/var/lib/containers
```

```bash
sudo mount -o subvol=@cache-dev "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.cache
```

```bash
sudo mount -o subvol=@cargo "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.cargo
```

```bash
sudo mount -o subvol=@rustup "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.rustup
```

```bash
sudo mount -o subvol=@go "${DEV_DRIVE}p1" /mnt/home/$USERNAME/go
```

```bash
sudo mount -o subvol=@local-share "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.local/share
```

```bash
sudo mount -o subvol=@nvm "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.nvm
```

```bash
sudo mount -o subvol=@bun "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.bun
```

```bash
sudo mount -o subvol=@claude-cache "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.claude
```

***

## Verify Mounts

```bash
df -h | grep -E "/mnt|nvme"
```

***

## Disable COW on ~/dev

```bash
sudo chattr +C /mnt/home/$USERNAME/dev
```

***

## Launch Calamares

```bash
sudo calamares
```

***

**Each command is now in its own code block for easy copy-paste execution!** Run them one at a time, verify each step, then proceed with Calamares when all mounts are confirmed.

