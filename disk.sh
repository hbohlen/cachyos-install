#!/bin/bash
#
# CachyOS Disk Partitioning Script (disk.sh)
# For ASUS ROG Zephyrus M16 GU603ZW
# 1TB System Drive + 2TB Crucial P310 Plus Development Drive
# Version: 3.0 (Production Ready)
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Global variables
SYSTEM_DRIVE=""
DEV_DRIVE=""
USERNAME=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${RED}[ERROR]${NC} Script failed at line $1"
        echo -e "${YELLOW}[CLEANUP]${NC} Unmounting any mounted filesystems..."
        umount -R /mnt 2>/dev/null || true
        umount /mnt/system-top 2>/dev/null || true
        umount /mnt/dev-top 2>/dev/null || true
    fi
}

trap 'cleanup $LINENO' ERR

# Progress spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Print functions
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  CachyOS Disk Partitioning Script v3.0                      ║"
    echo "║  Optimized for ASUS ROG Zephyrus M16 GU603ZW                ║"
    echo "║  1TB System + 2TB Crucial P310 Plus Development             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

print_step() { echo -e "\n${BLUE}[STEP $1/9]${NC} $2"; }
print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_progress() { echo -e "${MAGENTA}[▶]${NC} $1"; }

# Validate running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

# Check required tools
print_info "Checking required tools..."
for tool in sgdisk mkfs.btrfs mkfs.fat blkid; do
    if ! command -v $tool &> /dev/null; then
        print_error "Required tool '$tool' not found!"
        exit 1
    fi
done
print_success "All required tools present"

print_header

# ==================== STEP 1: Detect Drives ====================
print_step 1 9 "Detecting NVMe drives..."

echo "Available NVMe drives:"
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep nvme || {
    print_error "No NVMe drives detected!"
    exit 1
}
echo ""

# Auto-detect drives by size
for drive in /dev/nvme[0-9]n[0-9]; do
    if [ -b "$drive" ]; then
        # Get size in GB
        SIZE_BYTES=$(lsblk -d -n -b -o SIZE "$drive")
        SIZE_GB=$((SIZE_BYTES / 1000000000))
        MODEL=$(lsblk -d -n -o MODEL "$drive" 2>/dev/null || echo "Unknown")
        
        print_info "Checking $drive: ${SIZE_GB}GB ($MODEL)"
        
        # Detect 2TB drive (1800-2200GB range for safety)
        if [ "$SIZE_GB" -ge 1800 ] && [ "$SIZE_GB" -le 2200 ]; then
            DEV_DRIVE="$drive"
            print_success "Identified 2TB development drive: $drive"
            if echo "$MODEL" | grep -iq "crucial\|p310"; then
                print_success "  → Confirmed as Crucial P310 Plus"
            fi
        # Detect 1TB drive (900-1200GB range)
        elif [ "$SIZE_GB" -ge 900 ] && [ "$SIZE_GB" -le 1200 ]; then
            SYSTEM_DRIVE="$drive"
            print_success "Identified 1TB system drive: $drive"
        fi
    fi
done

# Fallback to manual input if auto-detection fails
if [ -z "$SYSTEM_DRIVE" ] || [ -z "$DEV_DRIVE" ]; then
    print_warning "Auto-detection incomplete!"
    echo ""
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep nvme
    echo ""
    
    if [ -z "$SYSTEM_DRIVE" ]; then
        read -p "Enter path to 1TB system drive (e.g., /dev/nvme1n1): " SYSTEM_DRIVE
    fi
    
    if [ -z "$DEV_DRIVE" ]; then
        read -p "Enter path to 2TB development drive (e.g., /dev/nvme0n1): " DEV_DRIVE
    fi
fi

# Validate drives exist
if [ ! -b "$SYSTEM_DRIVE" ]; then
    print_error "System drive $SYSTEM_DRIVE does not exist!"
    exit 1
fi

if [ ! -b "$DEV_DRIVE" ]; then
    print_error "Development drive $DEV_DRIVE does not exist!"
    exit 1
fi

# Validate drives are different
if [ "$SYSTEM_DRIVE" == "$DEV_DRIVE" ]; then
    print_error "System and development drives cannot be the same!"
    exit 1
fi

print_success "Drive detection complete"

# ==================== STEP 2: User Confirmation ====================
print_step 2 9 "Configuration confirmation..."

echo ""
print_warning "Selected configuration:"
echo "  1TB System Drive:      $SYSTEM_DRIVE"
echo "  2TB Development Drive: $DEV_DRIVE (Crucial P310 Plus)"
echo ""
print_error "⚠️  ALL DATA ON BOTH DRIVES WILL BE PERMANENTLY DESTROYED! ⚠️"
echo ""

read -p "Type 'YES' in all capitals to continue: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    print_info "Installation cancelled by user"
    exit 0
fi

# Get username
echo ""
read -p "Enter username for CachyOS installation: " USERNAME
while [ -z "$USERNAME" ]; do
    print_error "Username cannot be empty!"
    read -p "Enter username: " USERNAME
done

# Validate username (basic check)
if ! echo "$USERNAME" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
    print_error "Invalid username format (use lowercase, numbers, underscore, hyphen)"
    exit 1
fi

print_success "Username: $USERNAME"

# ==================== STEP 3: Partition 1TB System Drive ====================
print_step 3 9 "Partitioning 1TB system drive ($SYSTEM_DRIVE)..."

print_progress "Unmounting any existing partitions..."
umount ${SYSTEM_DRIVE}* 2>/dev/null || true

print_progress "Wiping existing partition table..."
sgdisk --zap-all "$SYSTEM_DRIVE" > /dev/null 2>&1 &
spinner $!
partprobe "$SYSTEM_DRIVE"
sleep 2

print_progress "Creating 1GB ESP partition..."
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System Partition" "$SYSTEM_DRIVE" > /dev/null 2>&1 &
spinner $!

print_progress "Creating system Btrfs partition (remaining space)..."
sgdisk -n 2:0:0 -t 2:8300 -c 2:"CachyOS System" "$SYSTEM_DRIVE" > /dev/null 2>&1 &
spinner $!

print_progress "Setting boot flags..."
sgdisk -A 1:set:2 "$SYSTEM_DRIVE" > /dev/null 2>&1 &
spinner $!
partprobe "$SYSTEM_DRIVE"
sleep 2

# Verify partitions created
if [ ! -b "${SYSTEM_DRIVE}p1" ] || [ ! -b "${SYSTEM_DRIVE}p2" ]; then
    print_error "Failed to create partitions on $SYSTEM_DRIVE"
    exit 1
fi

print_success "1TB drive partitioned successfully"

# ==================== STEP 4: Partition 2TB Development Drive ====================
print_step 4 9 "Partitioning 2TB development drive ($DEV_DRIVE)..."

print_progress "Unmounting any existing partitions..."
umount ${DEV_DRIVE}* 2>/dev/null || true

print_progress "Wiping existing partition table..."
sgdisk --zap-all "$DEV_DRIVE" > /dev/null 2>&1 &
spinner $!
partprobe "$DEV_DRIVE"
sleep 2

print_progress "Creating full-drive Btrfs partition..."
sgdisk -n 1:0:0 -t 1:8300 -c 1:"Development Data" "$DEV_DRIVE" > /dev/null 2>&1 &
spinner $!
partprobe "$DEV_DRIVE"
sleep 2

# Verify partition created
if [ ! -b "${DEV_DRIVE}p1" ]; then
    print_error "Failed to create partition on $DEV_DRIVE"
    exit 1
fi

print_success "2TB drive partitioned successfully"

# ==================== STEP 5: Format Filesystems ====================
print_step 5 9 "Formatting filesystems..."

print_progress "Formatting ESP as FAT32..."
mkfs.fat -F32 -n "ESP" "${SYSTEM_DRIVE}p1" > /dev/null 2>&1 &
spinner $!

print_progress "Formatting 1TB system Btrfs..."
mkfs.btrfs -f -L "cachyos-system" "${SYSTEM_DRIVE}p2" > /dev/null 2>&1 &
spinner $!

print_progress "Formatting 2TB development Btrfs (optimized for P310 Plus)..."
mkfs.btrfs -f -L "cachyos-dev" "${DEV_DRIVE}p1" > /dev/null 2>&1 &
spinner $!

# Verify filesystems
if ! blkid "${SYSTEM_DRIVE}p1" | grep -q "vfat"; then
    print_error "ESP filesystem creation failed"
    exit 1
fi

if ! blkid "${SYSTEM_DRIVE}p2" | grep -q "btrfs"; then
    print_error "System Btrfs creation failed"
    exit 1
fi

if ! blkid "${DEV_DRIVE}p1" | grep -q "btrfs"; then
    print_error "Development Btrfs creation failed"
    exit 1
fi

print_success "All filesystems created successfully"

# ==================== STEP 6: Create Btrfs Subvolumes ====================
print_step 6 9 "Creating Btrfs subvolumes..."

# Create temporary mount points
mkdir -p /mnt/system-top /mnt/dev-top

print_progress "Mounting top-level Btrfs volumes..."
mount -o subvolid=5 "${SYSTEM_DRIVE}p2" /mnt/system-top
mount -o subvolid=5 "${DEV_DRIVE}p1" /mnt/dev-top

# Create system subvolumes
print_progress "Creating system subvolumes (6 total)..."
cd /mnt/system-top
for subvol in @ @snapshots @home @var-log @tmp @cache-system; do
    btrfs subvolume create "$subvol" > /dev/null 2>&1
    print_info "  Created: $subvol"
done

# Create development subvolumes
print_progress "Creating development subvolumes (11 total)..."
cd /mnt/dev-top
for subvol in @dev @nix @containers @cache-dev @cargo @rustup @go @local-share @nvm @bun @claude-cache; do
    btrfs subvolume create "$subvol" > /dev/null 2>&1
    print_info "  Created: $subvol"
done

# Verify subvolume count
SYSTEM_SUBVOL_COUNT=$(btrfs subvolume list /mnt/system-top | wc -l)
DEV_SUBVOL_COUNT=$(btrfs subvolume list /mnt/dev-top | wc -l)

if [ "$SYSTEM_SUBVOL_COUNT" -ne 6 ]; then
    print_error "Expected 6 system subvolumes, found $SYSTEM_SUBVOL_COUNT"
    exit 1
fi

if [ "$DEV_SUBVOL_COUNT" -ne 11 ]; then
    print_error "Expected 11 development subvolumes, found $DEV_SUBVOL_COUNT"
    exit 1
fi

print_success "All 17 subvolumes created successfully"

# Unmount top-level
cd /
umount /mnt/system-top
umount /mnt/dev-top

# ==================== STEP 7: Mount All Subvolumes to /mnt ====================
print_step 7 9 "Mounting all subvolumes to /mnt (ready for installation)..."

# Clean /mnt
umount -R /mnt 2>/dev/null || true
rm -rf /mnt/*

# Mount root
print_progress "Mounting root filesystem..."
mount -o subvol=@,compress=zstd:3,noatime,space_cache=v2,discard=async,ssd "${SYSTEM_DRIVE}p2" /mnt

# Create directory structure
print_progress "Creating directory structure..."
mkdir -p /mnt/{boot/efi,home,nix,var/lib/containers,.snapshots,var/log,tmp}
mkdir -p /mnt/home/$USERNAME/{dev,.cache,.cargo,.rustup,go,.local/share,.nvm,.bun,.claude}

# Mount ESP
print_progress "Mounting ESP..."
mount "${SYSTEM_DRIVE}p1" /mnt/boot/efi

# Mount system subvolumes
print_progress "Mounting system subvolumes..."
mount -o subvol=@snapshots,compress=zstd:3,noatime,space_cache=v2,discard=async,ssd "${SYSTEM_DRIVE}p2" /mnt/.snapshots
mount -o subvol=@home,compress=zstd:3,noatime,space_cache=v2,discard=async,ssd "${SYSTEM_DRIVE}p2" /mnt/home
mount -o subvol=@var-log,compress=zstd:3,noatime,space_cache=v2,discard=async,ssd "${SYSTEM_DRIVE}p2" /mnt/var/log
mount -o subvol=@tmp,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${SYSTEM_DRIVE}p2" /mnt/tmp

# Mount development subvolumes (P310 Plus)
print_progress "Mounting development subvolumes (P310 Plus optimization)..."
mount -o subvol=@dev,compress=zstd:1,noatime,nodatacow,space_cache=v2,discard=async,ssd,autodefrag "${DEV_DRIVE}p1" /mnt/home/$USERNAME/dev
mount -o subvol=@nix,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/nix
mount -o subvol=@containers,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/var/lib/containers
mount -o subvol=@cache-dev,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.cache
mount -o subvol=@cargo,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.cargo
mount -o subvol=@rustup,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.rustup
mount -o subvol=@go,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/home/$USERNAME/go
mount -o subvol=@local-share,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.local/share
mount -o subvol=@nvm,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.nvm
mount -o subvol=@bun,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.bun
mount -o subvol=@claude-cache,compress=zstd:1,noatime,space_cache=v2,discard=async,ssd "${DEV_DRIVE}p1" /mnt/home/$USERNAME/.claude

# Verify all mounts
MOUNT_COUNT=$(mount | grep -c "/mnt" || echo "0")
if [ "$MOUNT_COUNT" -lt 17 ]; then
    print_error "Not all filesystems mounted correctly (found $MOUNT_COUNT, expected 17+)"
    mount | grep /mnt
    exit 1
fi

print_success "All filesystems mounted to /mnt"

# ==================== STEP 8: Generate Configuration ====================
print_step 8 9 "Generating configuration files..."

# Get UUIDs
UUID_ESP=$(blkid -s UUID -o value "${SYSTEM_DRIVE}p1")
UUID_SYSTEM=$(blkid -s UUID -o value "${SYSTEM_DRIVE}p2")
UUID_DEV=$(blkid -s UUID -o value "${DEV_DRIVE}p1")

# Save config for install.sh
CONFIG_FILE="/tmp/cachyos-disk-config.env"
cat > "$CONFIG_FILE" << EOF
# CachyOS Disk Configuration
# Generated: $(date)
SYSTEM_DRIVE="$SYSTEM_DRIVE"
DEV_DRIVE="$DEV_DRIVE"
USERNAME="$USERNAME"
UUID_ESP="$UUID_ESP"
UUID_SYSTEM="$UUID_SYSTEM"
UUID_DEV="$UUID_DEV"
EOF

print_success "Configuration saved to $CONFIG_FILE"

# Generate fstab for reference
FSTAB_FILE="/tmp/cachyos-fstab-$USERNAME.txt"
cat > "$FSTAB_FILE" << EOF
# CachyOS fstab - Generated $(date)
# Username: $USERNAME
# System: 1TB on $SYSTEM_DRIVE, Dev: 2TB P310 Plus on $DEV_DRIVE

# ESP
UUID=$UUID_ESP  /boot/efi  vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro  0 2

# System Drive (1TB on $SYSTEM_DRIVE)
UUID=$UUID_SYSTEM  /  btrfs  rw,noatime,compress=zstd:3,space_cache=v2,discard=async,ssd,subvol=@  0 0
UUID=$UUID_SYSTEM  /.snapshots  btrfs  rw,noatime,compress=zstd:3,space_cache=v2,discard=async,ssd,subvol=@snapshots  0 0
UUID=$UUID_SYSTEM  /home  btrfs  rw,noatime,compress=zstd:3,space_cache=v2,discard=async,ssd,subvol=@home  0 0
UUID=$UUID_SYSTEM  /var/log  btrfs  rw,noatime,compress=zstd:3,space_cache=v2,discard=async,ssd,subvol=@var-log  0 0
UUID=$UUID_SYSTEM  /tmp  btrfs  rw,noatime,compress=zstd:1,space_cache=v2,discard=async,ssd,subvol=@tmp  0 0

# Development Drive (2TB Crucial P310 Plus on $DEV_DRIVE)
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

print_success "fstab template saved to $FSTAB_FILE"

# ==================== STEP 9: Summary ====================
print_step 9 9 "Disk preparation complete!"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           DISK PARTITIONING SUCCESSFUL!                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

print_info "Summary:"
echo "  ✓ Partitioned: $SYSTEM_DRIVE (1TB system)"
echo "  ✓ Partitioned: $DEV_DRIVE (2TB P310 Plus dev)"
echo "  ✓ Created 17 Btrfs subvolumes"
echo "  ✓ All filesystems mounted to /mnt"
echo "  ✓ Ready for install.sh"
echo ""

print_info "Mount verification:"
df -h | grep /mnt | head -10
echo "  ... ($(mount | grep -c /mnt) total mounts)"
echo ""

print_info "Configuration files:"
echo "  Config: $CONFIG_FILE"
echo "  fstab:  $FSTAB_FILE"
echo ""

# Auto-trigger install.sh if present
if [ -f "$SCRIPT_DIR/install.sh" ]; then
    echo ""
    print_warning "Ready to proceed with installation"
    read -p "Run install.sh now? (Y/n): " RUN_INSTALL
    RUN_INSTALL=${RUN_INSTALL:-Y}
    
    if [[ "$RUN_INSTALL" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Launching install.sh..."
        sleep 2
        exec "$SCRIPT_DIR/install.sh"
    else
        print_info "Run manually when ready: sudo $SCRIPT_DIR/install.sh"
    fi
else
    print_warning "install.sh not found in $SCRIPT_DIR"
    print_info "Download and run: sudo ./install.sh"
fi

echo ""
print_success "disk.sh completed successfully!"
