```
# Set your variables
SYSTEM_DRIVE="/dev/nvme1n1"
DEV_DRIVE="/dev/nvme0n1"
USERNAME="hbohlen"

# Step 1: Partition 1TB system drive
sudo sgdisk --zap-all "$SYSTEM_DRIVE"
sudo sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System Partition" "$SYSTEM_DRIVE"
sudo sgdisk -n 2:0:0 -t 2:8300 -c 2:"CachyOS System" "$SYSTEM_DRIVE"
sudo sgdisk -A 1:set:2 "$SYSTEM_DRIVE"
sudo partprobe "$SYSTEM_DRIVE"

# Step 2: Partition 2TB development drive
sudo sgdisk --zap-all "$DEV_DRIVE"
sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:"Development Data" "$DEV_DRIVE"
sudo partprobe "$DEV_DRIVE"

# Step 3: Format filesystems
sudo mkfs.fat -F32 -n "ESP" "${SYSTEM_DRIVE}p1"
sudo mkfs.btrfs -f -L "cachyos-system" "${SYSTEM_DRIVE}p2"
sudo mkfs.btrfs -f -L "cachyos-dev" "${DEV_DRIVE}p1"

# Step 4: Create temporary mount points and mount top-level
sudo mkdir -p /mnt/system-top /mnt/dev-top
sudo mount -o subvolid=5 "${SYSTEM_DRIVE}p2" /mnt/system-top
sudo mount -o subvolid=5 "${DEV_DRIVE}p1" /mnt/dev-top

# Step 5: Create system subvolumes
cd /mnt/system-top
sudo btrfs subvolume create @
sudo btrfs subvolume create @snapshots
sudo btrfs subvolume create @home
sudo btrfs subvolume create @var-log
sudo btrfs subvolume create @tmp
sudo btrfs subvolume create @cache-system

# Step 6: Create development subvolumes
cd /mnt/dev-top
sudo btrfs subvolume create @dev
sudo btrfs subvolume create @nix
sudo btrfs subvolume create @containers
sudo btrfs subvolume create @cache-dev
sudo btrfs subvolume create @cargo
sudo btrfs subvolume create @rustup
sudo btrfs subvolume create @go
sudo btrfs subvolume create @local-share
sudo btrfs subvolume create @nvm
sudo btrfs subvolume create @bun
sudo btrfs subvolume create @claude-cache

# Step 7: Unmount top-level
cd /
sudo umount /mnt/system-top
sudo umount /mnt/dev-top

# Step 8: Mount everything to /mnt (ready for Calamares)
sudo mount -o subvol=@ "${SYSTEM_DRIVE}p2" /mnt
sudo mkdir -p /mnt/{boot/efi,home,nix,var/lib/containers,.snapshots,var/log,tmp}
sudo mkdir -p /mnt/home/$USERNAME/{dev,.cache,.cargo,.rustup,go,.local/share,.nvm,.bun,.claude}

sudo mount "${SYSTEM_DRIVE}p1" /mnt/boot/efi
sudo mount -o subvol=@snapshots "${SYSTEM_DRIVE}p2" /mnt/.snapshots
sudo mount -o subvol=@home "${SYSTEM_DRIVE}p2" /mnt/home
sudo mount -o subvol=@var-log "${SYSTEM_DRIVE}p2" /mnt/var/log
sudo mount -o subvol=@tmp "${SYSTEM_DRIVE}p2" /mnt/tmp

sudo mount -o subvol=@dev "${DEV_DRIVE}p1" /mnt/home/$USERNAME/dev
sudo mount -o subvol=@nix "${DEV_DRIVE}p1" /mnt/nix
sudo mount -o subvol=@containers "${DEV_DRIVE}p1" /mnt/var/lib/containers
sudo mount -o subvol=@cache-dev "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.cache
sudo mount -o subvol=@cargo "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.cargo
sudo mount -o subvol=@rustup "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.rustup
sudo mount -o subvol=@go "${DEV_DRIVE}p1" /mnt/home/$USERNAME/go
sudo mount -o subvol=@local-share "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.local/share
sudo mount -o subvol=@nvm "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.nvm
sudo mount -o subvol=@bun "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.bun
sudo mount -o subvol=@claude-cache "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.claude

# Step 9: Verify mounts
echo "Mount verification:"
df -h | grep -E "nvme|/mnt" | head -15

# Step 10: Disable COW for ~/dev
sudo chattr +C /mnt/home/$USERNAME/dev

# Step 11: Create fstab for reference
UUID_SYSTEM=$(sudo blkid -s UUID -o value "${SYSTEM_DRIVE}p2")
UUID_DEV=$(sudo blkid -s UUID -o value "${DEV_DRIVE}p1")

sudo cat > /tmp/fstab-reference.txt << EOF
# Reference fstab for Calamares
UUID=$UUID_SYSTEM  /  btrfs  subvol=@,compress=zstd:3,noatime  0 0
UUID=$UUID_SYSTEM  /home  btrfs  subvol=@home,compress=zstd:3,noatime  0 0
UUID=$UUID_DEV  /home/$USERNAME/dev  btrfs  subvol=@dev,compress=zstd:1,noatime,nodatacow  0 0
EOF

echo ""
echo "✓ Partitioning complete!"
echo "✓ All filesystems mounted to /mnt"
echo "✓ Ready for Calamares"
echo ""
echo "Next: sudo calamares"
echo "     Select 'Manual Partitioning'"
echo "     Mount points are already set, just verify and install"
```
