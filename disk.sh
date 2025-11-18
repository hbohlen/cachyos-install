#!/bin/bash
#
# CachyOS Dual-SSD Auto-Partitioner for ASUS ROG Zephyrus M16 GU603ZW
# Optimized for: 1TB system drive + 2TB Crucial P310 Plus development drive
# Version: 2.0
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Progress indicators
SPINNER_PID=""
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  CachyOS Dual-SSD Auto-Partitioner for Zephyrus M16         ║"
    echo "║  Optimized for Maximum Development Performance               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() { echo -e "${BLUE}[STEP $1/$2]${NC} $3"; }
print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_progress() { echo -e "${MAGENTA}[▶]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo $0"
    exit 1
fi

print_header

# Step 1: Detect drives
print_step 1 6 "Detecting NVMe drives..."
lsblk -d -o NAME,SIZE,MODEL | grep nvme

DRIVE_1TB=""
DRIVE_2TB=""

for drive in /dev/nvme[0-9]n[0-9]; do
    if [ -b "$drive" ]; then
        SIZE_GB=$(lsblk -d -n -o SIZE "$drive" | grep -oE '[0-9]+' | head -1)
        MODEL=$(lsblk -d -n -o MODEL "$drive" 2>/dev/null || echo "Unknown")

        if [ "$SIZE_GB" -ge 1800 ] && [ "$SIZE_GB" -le 2100 ]; then
            DRIVE_2TB="$drive"
            print_info "Found 2TB drive: $drive ($MODEL) - ${SIZE_GB}GB"
            if echo "$MODEL" | grep -iq "crucial\|p310"; then
                print_success "Confirmed as Crucial P310 Plus (high-performance)"
            fi
        elif [ "$SIZE_GB" -ge 900 ] && [ "$SIZE_GB" -le 1100 ]; then
            DRIVE_1TB="$drive"
            print_info "Found 1TB drive: $drive ($MODEL) - ${SIZE_GB}GB"
        fi
    fi
done

if [ -z "$DRIVE_1TB" ] || [ -z "$DRIVE_2TB" ]; then
    print_error "Could not auto-detect both drives!"
    echo ""
    lsblk -d -o NAME,SIZE,MODEL
    echo ""
    read -p "Enter 1TB system drive path (e.g., /dev/nvme0n1): " DRIVE_1TB
    read -p "Enter 2TB development drive path (e.g., /dev/nvme1n1): " DRIVE_2TB
fi

# Validate drives
if [ ! -b "$DRIVE_1TB" ] || [ ! -b "$DRIVE_2TB" ]; then
    print_error "Invalid drive paths!"
    exit 1
fi

print_success "Drive detection complete"
echo ""
print_warning "Selected configuration:"
echo "  System Drive (1TB):      $DRIVE_1TB"
echo "  Development Drive (2TB): $DRIVE_2TB (Crucial P310 Plus)"
echo ""
print_error "⚠️  ALL DATA ON THESE DRIVES WILL BE PERMANENTLY DESTROYED! ⚠️"
echo ""
read -p "Type 'YES' in all capitals to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    print_info "Installation cancelled by user"
    exit 0
fi

# Step 2: Get user information
print_step 2 6 "Gathering user information..."

read -p "Enter username for installation: " USERNAME
while [ -z "$USERNAME" ]; do
    print_error "Username cannot be empty!"
    read -p "Enter username: " USERNAME
done

print_success "Username set to: $USERNAME"
echo ""

# Step 3: Partition 1TB system drive
print_step 3 6 "Partitioning 1TB system drive..."

print_progress "Unmounting existing partitions..."
umount ${DRIVE_1TB}* 2>/dev/null || true

print_progress "Wiping partition table..."
(sgdisk --zap-all "$DRIVE_1TB" && partprobe "$DRIVE_1TB") &
spinner $!
sleep 2

print_progress "Creating ESP partition (1GB)..."
(sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System Partition" "$DRIVE_1TB") &
spinner $!

print_progress "Creating system Btrfs partition..."
(sgdisk -n 2:0:0 -t 2:8300 -c 2:"CachyOS System" "$DRIVE_1TB") &
spinner $!

print_progress "Setting boot flags..."
(sgdisk -A 1:set:2 "$DRIVE_1TB" && partprobe "$DRIVE_1TB") &
spinner $!
sleep 2

print_success "1TB drive partitioned"

# Step 4: Partition 2TB development drive
print_step 4 6 "Partitioning 2TB development drive (Crucial P310 Plus)..."

print_progress "Unmounting existing partitions..."
umount ${DRIVE_2TB}* 2>/dev/null || true

print_progress "Wiping partition table..."
(sgdisk --zap-all "$DRIVE_2TB" && partprobe "$DRIVE_2TB") &
spinner $!
sleep 2

print_progress "Creating development Btrfs partition (full drive)..."
(sgdisk -n 1:0:0 -t 1:8300 -c 1:"Development Data" "$DRIVE_2TB" && partprobe "$DRIVE_2TB") &
spinner $!
sleep 2

print_success "2TB drive partitioned"

# Step 5: Format filesystems
print_step 5 6 "Creating filesystems..."

print_progress "Formatting ESP as FAT32..."
(mkfs.fat -F32 -n "ESP" "${DRIVE_1TB}p1") &
spinner $!

print_progress "Formatting 1TB system Btrfs..."
(mkfs.btrfs -f -L "cachyos-system" "${DRIVE_1TB}p2") &
spinner $!

print_progress "Formatting 2TB development Btrfs (optimized for P310 Plus)..."
(mkfs.btrfs -f -L "cachyos-dev" "${DRIVE_2TB}p1") &
spinner $!

print_success "Filesystems created"

# Step 6: Create Btrfs subvolumes
print_step 6 6 "Creating optimized Btrfs subvolumes..."

mkdir -p /mnt/{system-top,dev-top}

print_progress "Mounting top-level volumes..."
mount -o subvolid=5 "${DRIVE_1TB}p2" /mnt/system-top
mount -o subvolid=5 "${DRIVE_2TB}p1" /mnt/dev-top

print_progress "Creating system subvolumes..."
cd /mnt/system-top
for subvol in @ @snapshots @home @var-log @tmp @cache-system; do
    btrfs subvolume create $subvol >/dev/null 2>&1
done

print_progress "Creating development subvolumes (optimized for AI agents)..."
cd /mnt/dev-top
for subvol in @dev @nix @containers @cache-dev @cargo @rustup @go @local-share @nvm @bun @claude-cache; do
    btrfs subvolume create $subvol >/dev/null 2>&1
done

print_success "All subvolumes created"

# Generate fstab
UUID_ESP=$(blkid -s UUID -o value "${DRIVE_1TB}p1")
UUID_SYSTEM=$(blkid -s UUID -o value "${DRIVE_1TB}p2")
UUID_DEV=$(blkid -s UUID -o value "${DRIVE_2TB}p1")

FSTAB_FILE="/tmp/cachyos-fstab-$USERNAME.txt"

cat > "$FSTAB_FILE" << EOF
# CachyOS Dual-SSD fstab - Generated $(date)
# Username: $USERNAME
# Optimized for ASUS ROG Zephyrus M16 GU603ZW with Crucial P310 Plus

# ESP
UUID=$UUID_ESP  /boot/efi  vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro  0 2

# System Drive (1TB)
UUID=$UUID_SYSTEM  /  btrfs  rw,noatime,compress=zstd:3,space_cache=v2,discard=async,ssd,subvol=@  0 0
UUID=$UUID_SYSTEM  /.snapshots  btrfs  rw,noatime,compress=zstd:3,space_cache=v2,discard=async,ssd,subvol=@snapshots  0 0
UUID=$UUID_SYSTEM  /home  btrfs  rw,noatime,compress=zstd:3,space_cache=v2,discard=async,ssd,subvol=@home  0 0
UUID=$UUID_SYSTEM  /var/log  btrfs  rw,noatime,compress=zstd:3,space_cache=v2,discard=async,ssd,subvol=@var-log  0 0
UUID=$UUID_SYSTEM  /tmp  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@tmp  0 0

# Development Drive (2TB Crucial P310 Plus - Optimized for 1M IOPS)
UUID=$UUID_DEV  /home/$USERNAME/dev  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,autodefrag,nodatacow,subvol=@dev  0 0
UUID=$UUID_DEV  /nix  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@nix  0 0
UUID=$UUID_DEV  /var/lib/containers  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@containers  0 0
UUID=$UUID_DEV  /home/$USERNAME/.cache  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@cache-dev  0 0
UUID=$UUID_DEV  /home/$USERNAME/.cargo  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@cargo  0 0
UUID=$UUID_DEV  /home/$USERNAME/.rustup  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@rustup  0 0
UUID=$UUID_DEV  /home/$USERNAME/go  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@go  0 0
UUID=$UUID_DEV  /home/$USERNAME/.local/share  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@local-share  0 0
UUID=$UUID_DEV  /home/$USERNAME/.nvm  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@nvm  0 0
UUID=$UUID_DEV  /home/$USERNAME/.bun  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@bun  0 0
UUID=$UUID_DEV  /home/$USERNAME/.claude  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@claude-cache  0 0
EOF

# Cleanup
cd /
umount /mnt/system-top
umount /mnt/dev-top
rmdir /mnt/system-top /mnt/dev-top

# Save configuration for install script
cat > "/tmp/cachyos-config.env" << EOF
DRIVE_1TB="$DRIVE_1TB"
DRIVE_2TB="$DRIVE_2TB"
USERNAME="$USERNAME"
FSTAB_FILE="$FSTAB_FILE"
UUID_ESP="$UUID_ESP"
UUID_SYSTEM="$UUID_SYSTEM"
UUID_DEV="$UUID_DEV"
EOF

print_success "Partitioning complete!"
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              DISK PARTITIONING SUCCESSFUL!                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_info "Configuration saved:"
echo "  - fstab: $FSTAB_FILE"
echo "  - config: /tmp/cachyos-config.env"
echo ""
print_warning "NEXT STEP: Run ./install.sh to complete installation"
echo ""
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT

# Success message
print_success "Partitioning complete!"

# Next, offer to auto-run install.sh
if [ -f "./install.sh" ]; then
    echo -e "\n${BLUE}[ACTION]${NC} Would you like to run install.sh now? (y/N)"
    read -r TRIGGER_INSTALL
    if [[ "$TRIGGER_INSTALL" =~ ^[Yy]$ ]]; then
        sudo ./install.sh
    else
        print_info "You can manually run: sudo ./install.sh"
    fi
else
    print_warning "install.sh not found in current directory. Please run it manually when ready."
fi
