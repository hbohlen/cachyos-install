#!/bin/bash
#
# CachyOS System Installation Script (install.sh)
# For ASUS ROG Zephyrus M16 GU603ZW
# Installs complete CachyOS base system with Niri, development tools, and WiFi
# Version: 3.0 (Production Ready)
#

set -euo pipefail

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
UUID_ESP=""
UUID_SYSTEM=""
UUID_DEV=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${RED}[ERROR]${NC} Script failed at line $1"
        echo -e "${YELLOW}[INFO]${NC} Filesystems remain mounted at /mnt for debugging"
        echo -e "${YELLOW}[INFO]${NC} To clean up: sudo umount -R /mnt"
    fi
}

trap 'cleanup $LINENO' ERR

# Print functions
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  CachyOS System Installation Script v3.0                    ║"
    echo "║  Complete Base System + Niri + Development Tools + WiFi     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

print_step() { echo -e "\n${BLUE}[STEP $1/15]${NC} $2"; }
print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_progress() { echo -e "${MAGENTA}[▶]${NC} $1"; }

# Validate root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

print_header

# ==================== STEP 1: Load Configuration ====================
print_step 1 15 "Loading configuration from disk.sh..."

CONFIG_FILE="/tmp/cachyos-disk-config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    print_error "You must run disk.sh first!"
    exit 1
fi

source "$CONFIG_FILE"

# Validate required variables
for var in SYSTEM_DRIVE DEV_DRIVE USERNAME UUID_ESP UUID_SYSTEM UUID_DEV; do
    if [ -z "${!var}" ]; then
        print_error "Missing required variable: $var"
        exit 1
    fi
done

print_success "Configuration loaded"
echo "  System Drive: $SYSTEM_DRIVE"
echo "  Dev Drive:    $DEV_DRIVE"
echo "  Username:     $USERNAME"

# ==================== STEP 2: Verify Mounts ====================
print_step 2 15 "Verifying filesystems are mounted..."

if ! mountpoint -q /mnt; then
    print_error "/mnt is not a mount point!"
    print_error "disk.sh may not have completed successfully"
    exit 1
fi

MOUNT_COUNT=$(mount | grep -c "/mnt" || echo "0")
if [ "$MOUNT_COUNT" -lt 15 ]; then
    print_error "Insufficient mounts found (expected 17+, found $MOUNT_COUNT)"
    mount | grep /mnt
    exit 1
fi

print_success "All filesystems verified mounted ($MOUNT_COUNT mounts)"

# ==================== STEP 3: Test Internet Connectivity ====================
print_step 3 15 "Testing internet connectivity..."

if ! ping -c 3 archlinux.org > /dev/null 2>&1; then
    print_error "No internet connectivity!"
    print_warning "Please connect to WiFi in the live environment:"
    print_info "  1. Run: nmtui"
    print_info "  2. Select 'Activate a connection'"
    print_info "  3. Connect to your network"
    print_info "  4. Re-run this script"
    exit 1
fi

print_success "Internet connectivity confirmed"

# ==================== STEP 4: Configure Fastest Mirrors ====================
print_step 4 15 "Configuring fastest package mirrors..."

print_progress "Running reflector to find optimal mirrors..."
if command -v reflector &> /dev/null; then
    reflector --country US --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>&1 | tail -5
    print_success "Mirrors configured"
else
    print_warning "Reflector not available, using default mirrors"
fi

# ==================== STEP 5: Get User Passwords ====================
print_step 5 15 "User account configuration..."

echo ""
read -p "Enter hostname (default: zephyrus-cachyos): " HOSTNAME
HOSTNAME=${HOSTNAME:-zephyrus-cachyos}

read -p "Enter timezone (default: America/Chicago): " TIMEZONE
TIMEZONE=${TIMEZONE:-America/Chicago}

read -sp "Enter root password: " ROOT_PASSWORD
echo ""
read -sp "Confirm root password: " ROOT_PASSWORD_CONFIRM
echo ""

if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
    print_error "Root passwords don't match!"
    exit 1
fi

read -sp "Enter password for user $USERNAME: " USER_PASSWORD
echo ""
read -sp "Confirm password for $USERNAME: " USER_PASSWORD_CONFIRM
echo ""

if [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
    print_error "User passwords don't match!"
    exit 1
fi

print_success "User configuration collected"

# ==================== STEP 6: Install Base System ====================
print_step 6 15 "Installing base CachyOS system (this will take 5-10 minutes)..."

print_progress "Running pacstrap..."

pacstrap -K /mnt \
    base \
    base-devel \
    linux-firmware \
    linux-cachyos \
    linux-cachyos-headers \
    btrfs-progs \
    networkmanager \
    network-manager-applet \
    iwd \
    nano \
    vim \
    neovim \
    git \
    wget \
    curl \
    fish \
    sudo \
    2>&1 | grep -E "installing|upgrading" | tail -20

print_success "Base system installed"

# ==================== STEP 7: Generate fstab ====================
print_step 7 15 "Generating filesystem table..."

genfstab -U /mnt > /mnt/etc/fstab

# Verify fstab
if ! grep -q "$UUID_SYSTEM" /mnt/etc/fstab; then
    print_error "fstab generation failed!"
    exit 1
fi

print_success "fstab generated"

# ==================== STEP 8: Configure Base System ====================
print_step 8 15 "Configuring base system..."

cat > /mnt/root/configure-base.sh << 'CHROOT_BASE'
#!/bin/bash
set -e

USERNAME="$1"
USER_PASSWORD="$2"
ROOT_PASSWORD="$3"
HOSTNAME="$4"
TIMEZONE="$5"

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Generate locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Configure hosts
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
useradd -m -G wheel,storage,power,audio,video,input,network -s /bin/fish $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Enable sudo for wheel group
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Enable essential services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
systemctl enable fstrim.timer

echo "Base configuration complete"
CHROOT_BASE

chmod +x /mnt/root/configure-base.sh
arch-chroot /mnt /root/configure-base.sh "$USERNAME" "$USER_PASSWORD" "$ROOT_PASSWORD" "$HOSTNAME" "$TIMEZONE"

print_success "Base system configured"

# ==================== STEP 9: Add CachyOS Repositories ====================
print_step 9 15 "Adding CachyOS repositories..."

cat > /mnt/root/add-cachyos-repos.sh << 'CHROOT_REPOS'
#!/bin/bash
set -e

# Import CachyOS keys
pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com 2>/dev/null || true
pacman-key --lsign-key F3B607488DB35A47 2>/dev/null || true

# Install CachyOS keyring and mirrorlist
pacman --noconfirm -U \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-18-1-any.pkg.tar.zst' \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-18-1-any.pkg.tar.zst' \
    2>/dev/null || echo "CachyOS packages already installed"

# Add repos to pacman.conf if not present
if ! grep -q "\[cachyos\]" /etc/pacman.conf; then
    cat >> /etc/pacman.conf << 'EOF'

# CachyOS repositories
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
fi

# Update package databases
pacman -Syy

echo "CachyOS repositories configured"
CHROOT_REPOS

chmod +x /mnt/root/add-cachyos-repos.sh
arch-chroot /mnt /root/add-cachyos-repos.sh

print_success "CachyOS repositories added"

# ==================== STEP 10: Install Desktop and Development Tools ====================
print_step 10 15 "Installing desktop environment and development tools..."

cat > /mnt/root/install-packages.sh << 'CHROOT_PACKAGES'
#!/bin/bash
set -e

USERNAME="$1"

# Update system
pacman -Syu --noconfirm

# Install Niri and Wayland tools
pacman -S --noconfirm \
    niri \
    waybar \
    fuzzel \
    mako \
    alacritty \
    foot \
    swaybg \
    swaylock \
    wl-clipboard \
    cliphist \
    brightnessctl \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-gtk \
    qt6-wayland \
    qt5-wayland \
    polkit-qt6 \
    mate-polkit \
    accountsservice \
    qt6-multimedia

# Install Fish shell configuration
pacman -S --noconfirm cachyos-fish-config

# Install development tools
pacman -S --noconfirm \
    podman \
    podman-compose \
    podman-docker \
    docker-compose \
    go \
    rust \
    rustup \
    nodejs \
    npm \
    python \
    python-pip \
    uv \
    chezmoi \
    zed \
    github-cli \
    lazygit \
    ripgrep \
    fd \
    bat \
    eza \
    zoxide \
    fzf \
    btop \
    htop \
    starship \
    nix

# Install system utilities
pacman -S --noconfirm \
    thermald \
    power-profiles-daemon \
    cpupower

echo "All packages installed"
CHROOT_PACKAGES

chmod +x /mnt/root/install-packages.sh
arch-chroot /mnt /root/install-packages.sh "$USERNAME"

print_success "Desktop and development tools installed"

# ==================== STEP 11: Configure Fish Shell ====================
print_step 11 15 "Configuring Fish shell environment..."

mkdir -p /mnt/home/$USERNAME/.config/fish

cat > /mnt/home/$USERNAME/.config/fish/config.fish << 'FISH_CONFIG'
# CachyOS Development Environment Configuration

# XDG Base Directories
set -x XDG_CACHE_HOME "$HOME/.cache"
set -x XDG_DATA_HOME "$HOME/.local/share"
set -x XDG_CONFIG_HOME "$HOME/.config"

# Development paths (all on Crucial P310 Plus)
set -x CARGO_HOME "$HOME/.cargo"
set -x RUSTUP_HOME "$HOME/.rustup"
set -x GOPATH "$HOME/go"
set -x NVM_DIR "$HOME/.nvm"
set -x BUN_INSTALL "$HOME/.bun"
set -x UV_CACHE_DIR "$HOME/.cache/uv"
set -x CLAUDE_HOME "$HOME/.claude"

# Terminal and editor
set -x TERMINAL ghostty
set -x EDITOR nvim
set -x VISUAL zed

# PATH additions
fish_add_path $HOME/.cargo/bin
fish_add_path $HOME/.local/bin
fish_add_path $HOME/.bun/bin
fish_add_path $GOPATH/bin
fish_add_path $HOME/.nix-profile/bin

# Zoxide (smart cd)
if type -q zoxide
    zoxide init fish | source
end

# Starship prompt
if type -q starship
    starship init fish | source
end

# Development aliases
alias gst='git status'
alias gco='git checkout'
alias dc='docker-compose'
alias pc='podman-compose'
alias pps='podman ps'
alias ls='eza --icons'
alias ll='eza -l --icons'
alias la='eza -la --icons'
alias cat='bat'
alias vim='nvim'

# Welcome message
if status is-interactive
    echo "CachyOS Development Environment Ready"
    echo "Run 'post-install' to install AUR packages (Ghostty, Claude, OpenCode, Zen Browser, DMS)"
end
FISH_CONFIG

print_success "Fish shell configured"

# ==================== STEP 12: Configure Niri ====================
print_step 12 15 "Configuring Niri compositor..."

mkdir -p /mnt/home/$USERNAME/.config/niri

cat > /mnt/home/$USERNAME/.config/niri/config.kdl << 'NIRI_CONFIG'
// Niri configuration for CachyOS (basic setup for DMS later)

layout {
    gaps 8
    struts {
        left 0
        right 0
        top 0
        bottom 0
    }
}

spawn-at-startup "mate-polkit"
spawn-at-startup "bash" "-c" "wl-paste --watch cliphist store"

binds {
    // Terminal
    Mod+Return { spawn "alacritty"; }
    Mod+T { spawn "alacritty"; }
    
    // Window management
    Mod+Q { close-window; }
    Mod+Alt+Q { quit; }
    
    // Focus
    Mod+Left { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Up { focus-window-up; }
    Mod+Down { focus-window-down; }
    
    // Move windows
    Mod+Shift+Left { move-column-left; }
    Mod+Shift+Right { move-column-right; }
    Mod+Shift+Up { move-window-up; }
    Mod+Shift+Down { move-window-down; }
    
    // Workspaces
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    
    // Brightness
    XF86MonBrightnessUp { spawn "brightnessctl" "set" "10%+"; }
    XF86MonBrightnessDown { spawn "brightnessctl" "set" "10%-"; }
}
NIRI_CONFIG

print_success "Niri configured"

# ==================== STEP 13: Install Bootloader ====================
print_step 13 15 "Installing systemd-boot bootloader..."

cat > /mnt/root/install-bootloader.sh << CHROOT_BOOT
#!/bin/bash
set -e

# Install systemd-boot
bootctl install

# Create loader configuration
cat > /boot/loader/loader.conf << 'EOF'
default cachyos.conf
timeout 3
console-mode max
editor no
EOF

# Create CachyOS boot entry
cat > /boot/loader/entries/cachyos.conf << 'EOF'
title   CachyOS
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options root=UUID=$UUID_SYSTEM rootflags=subvol=@ rw quiet splash loglevel=3
EOF

# Create fallback entry
cat > /boot/loader/entries/cachyos-fallback.conf << 'EOF'
title   CachyOS (Fallback)
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos-fallback.img
options root=UUID=$UUID_SYSTEM rootflags=subvol=@ rw
EOF

echo "Bootloader installed"
CHROOT_BOOT

chmod +x /mnt/root/install-bootloader.sh
arch-chroot /mnt /root/install-bootloader.sh

print_success "Bootloader installed"

# ==================== STEP 14: Apply Kernel Optimizations ====================
print_step 14 15 "Applying kernel performance tuning for Zephyrus M16..."

cat > /mnt/etc/sysctl.d/99-cachyos-zephyrus.conf << 'SYSCTL_EOF'
# CachyOS Kernel Tuning for ASUS ROG Zephyrus M16
# Optimized for development and performance

# Memory management
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=20
vm.dirty_background_ratio=10
vm.dirty_writeback_centisecs=100

# Network tuning
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=10000 65535
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

# File descriptor limits
fs.file-max=2097152
fs.inotify.max_user_watches=524288
SYSCTL_EOF

# Enable thermald for thermal management
arch-chroot /mnt systemctl enable thermald

# Enable power-profiles-daemon
arch-chroot /mnt systemctl enable power-profiles-daemon

print_success "Kernel optimizations applied"

# ==================== STEP 15: Finalize Installation ====================
print_step 15 15 "Finalizing installation..."

# Set ownership of home directory
print_progress "Setting file ownership..."
arch-chroot /mnt chown -R $USERNAME:$USERNAME /home/$USERNAME

# Disable COW for ~/dev (critical for AI agent performance)
print_progress "Disabling copy-on-write for ~/dev..."
chattr +C /mnt/home/$USERNAME/dev 2>/dev/null || print_warning "COW disable may need to be done after reboot"

# Create WiFi helper script
cat > /mnt/usr/local/bin/wifi-connect << 'WIFI_EOF'
#!/bin/bash
echo "Available WiFi networks:"
nmcli device wifi list
echo ""
read -p "Enter network SSID: " SSID
read -sp "Enter password: " PASS
echo ""
nmcli device wifi connect "$SSID" password "$PASS"
WIFI_EOF

chmod +x /mnt/usr/local/bin/wifi-connect

# Create post-install script for AUR packages
cat > /mnt/home/$USERNAME/post-install.sh << 'POST_INSTALL_EOF'
#!/bin/bash
#
# Post-Installation Script - Run after first boot
# Installs AUR packages: paru, Ghostty, Zen Browser, Claude Code, OpenCode, DMS
#

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  CachyOS Post-Installation - AUR Packages                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Install paru AUR helper
echo "[1/6] Installing paru AUR helper..."
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm
cd ..
rm -rf paru

# Install Ghostty terminal
echo "[2/6] Installing Ghostty terminal..."
paru -S --noconfirm ghostty-bin || paru -S --noconfirm ghostty

# Install Zen Browser
echo "[3/6] Installing Zen Browser..."
paru -S --noconfirm zen-browser-bin || paru -S --noconfirm zen-browser

# Install Claude Desktop
echo "[4/6] Installing Claude Desktop..."
cd /tmp
wget -q https://storage.googleapis.com/claude-release/claude_installer_latest.tar.gz
tar -xzf claude_installer_latest.tar.gz
./claude-installer/install.sh
rm -rf claude_installer_latest.tar.gz claude-installer

# Install OpenCode
echo "[5/6] Installing OpenCode AI CLI..."
paru -S --noconfirm opencode-bin || paru -S --noconfirm opencode

# Install DMS (Dank Material Shell)
echo "[6/6] Installing DMS (Dank Material Shell)..."
paru -S --noconfirm dms-shell-bin matugen-bin dgop || echo "DMS install may require manual setup"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Post-Installation Complete!                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Configure DMS: Press Mod+Comma in Niri"
echo "  2. Setup 1Password: Install from AUR if needed"
echo "  3. Setup Nix: sh <(curl -L https://nixos.org/nix/install) --daemon"
echo "  4. Setup Chezmoi: chezmoi init --apply"
echo ""
POST_INSTALL_EOF

chmod +x /mnt/home/$USERNAME/post-install.sh
arch-chroot /mnt chown $USERNAME:$USERNAME /home/$USERNAME/post-install.sh

# Create convenience command
cat > /mnt/usr/local/bin/post-install << POST_CMD
#!/bin/bash
exec /home/$USERNAME/post-install.sh
POST_CMD

chmod +x /mnt/usr/local/bin/post-install

# Cleanup chroot scripts
rm -f /mnt/root/*.sh

# Sync
sync

print_success "Installation finalized"

# ==================== Summary and Reboot ====================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         CACHYOS INSTALLATION COMPLETED SUCCESSFULLY!         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

print_info "Installation Summary:"
echo "  ✓ Base CachyOS system installed"
echo "  ✓ CachyOS repositories configured"
echo "  ✓ Niri compositor installed"
echo "  ✓ Fish shell configured with dev environment"
echo "  ✓ Development tools: Podman, Rust, Go, Node, Python/UV"
echo "  ✓ WiFi configured (NetworkManager enabled)"
echo "  ✓ systemd-boot bootloader installed"
echo "  ✓ Kernel optimized for Zephyrus M16"
echo "  ✓ User '$USERNAME' created"
echo ""

print_info "After reboot:"
echo "  • Connect to WiFi: Run 'wifi-connect' or use 'nmtui'"
echo "  • Install AUR packages: Run 'post-install'"
echo "  • Start Niri: Login will auto-start (or run 'niri-session')"
echo ""

print_warning "System is ready to reboot!"
echo ""

# Prompt for reboot
read -p "Reboot now? (Y/n): " REBOOT_NOW
REBOOT_NOW=${REBOOT_NOW:-Y}

if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
    print_info "Unmounting filesystems..."
    umount -R /mnt
    
    print_success "Rebooting in 3 seconds..."
    sleep 1
    echo "3..."
    sleep 1
    echo "2..."
    sleep 1
    echo "1..."
    
    reboot
else
    print_info "To reboot manually:"
    echo "  sudo umount -R /mnt"
    echo "  sudo reboot"
fi
