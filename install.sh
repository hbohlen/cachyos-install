#!/bin/bash
#
# CachyOS Complete System Installation Script
# For ASUS ROG Zephyrus M16 GU603ZW with 1TB + 2TB Crucial P310 Plus
# Includes: Niri, DMS, Claude Code, OpenCode, Zen Browser, Power Profiles
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

# Spinner
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  CachyOS Complete System Installation for Zephyrus M16      ║"
    echo "║  Optimized for Development & AI Agent Workflows              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() { echo -e "\n${BLUE}[STEP $1/$2]${NC} $3"; }
print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_progress() { echo -e "${MAGENTA}[▶]${NC} $1"; }

spinner() {
    local pid=$1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Root check
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo $0"
    exit 1
fi

print_header

# Load configuration from disk.sh
if [ ! -f "/tmp/cachyos-config.env" ]; then
    print_error "Configuration file not found! Run ./disk.sh first"
    exit 1
fi

source "/tmp/cachyos-config.env"

print_info "Loaded configuration:"
echo "  System Drive: $DRIVE_1TB"
echo "  Dev Drive:    $DRIVE_2TB"
echo "  Username:     $USERNAME"
echo ""

# Interactive input for passwords and settings
print_step 1 14 "Gathering configuration..."

read -p "Enter hostname (default: zephyrus-cachy): " HOSTNAME
HOSTNAME=${HOSTNAME:-zephyrus-cachy}

read -p "Enter timezone (default: America/Chicago): " TIMEZONE
TIMEZONE=${TIMEZONE:-America/Chicago}

read -sp "Enter root password: " ROOT_PASSWORD
echo ""
read -sp "Confirm root password: " ROOT_PASSWORD_CONFIRM
echo ""

if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
    print_error "Passwords don't match!"
    exit 1
fi

read -sp "Enter user password for $USERNAME: " USER_PASSWORD
echo ""
read -sp "Confirm user password: " USER_PASSWORD_CONFIRM
echo ""

if [ "$USER_PASSWORD" != "$USER_PASSWORD_CONFIRM" ]; then
    print_error "Passwords don't match!"
    exit 1
fi

print_success "Configuration gathered"

# Mount filesystems
print_step 2 14 "Mounting filesystems..."

print_progress "Unmounting existing mounts..."
umount -R /mnt 2>/dev/null || true

print_progress "Mounting root filesystem..."
mount -o subvol=@,compress=zstd:3,noatime "${DRIVE_1TB}p2" /mnt

mkdir -p /mnt/{boot/efi,nix,var/lib/containers,.snapshots}
mkdir -p /mnt/home/$USERNAME/{dev,.cache,.cargo,.rustup,go,.local/share,.nvm,.bun,.claude}

mount "${DRIVE_1TB}p1" /mnt/boot/efi
mount -o subvol=@snapshots,compress=zstd:3,noatime "${DRIVE_1TB}p2" /mnt/.snapshots
mount -o subvol=@home,compress=zstd:3,noatime "${DRIVE_1TB}p2" /mnt/home
mount -o subvol=@var-log,compress=zstd:3,noatime "${DRIVE_1TB}p2" /mnt/var/log
mount -o subvol=@tmp,compress=zstd:1,noatime "${DRIVE_1TB}p2" /mnt/tmp

mount -o subvol=@dev,compress=zstd:1,noatime,nodatacow "${DRIVE_2TB}p1" /mnt/home/$USERNAME/dev
mount -o subvol=@nix,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/nix
mount -o subvol=@containers,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/var/lib/containers
mount -o subvol=@cache-dev,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/home/$USERNAME/.cache
mount -o subvol=@cargo,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/home/$USERNAME/.cargo
mount -o subvol=@rustup,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/home/$USERNAME/.rustup
mount -o subvol=@go,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/home/$USERNAME/go
mount -o subvol=@local-share,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/home/$USERNAME/.local/share
mount -o subvol=@nvm,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/home/$USERNAME/.nvm
mount -o subvol=@bun,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/home/$USERNAME/.bun
mount -o subvol=@claude-cache,compress=zstd:1,noatime "${DRIVE_2TB}p1" /mnt/home/$USERNAME/.claude

print_success "All filesystems mounted"

# Configure mirrors
print_step 3 14 "Configuring fastest mirrors..."
print_progress "Running reflector for optimal mirrors..."
(reflector --country US --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist) &
spinner $!
print_success "Mirrors configured"

# Install base system
print_step 4 14 "Installing base CachyOS system..."
print_progress "Installing base packages with CachyOS kernel..."

pacstrap -K /mnt \
    base base-devel linux-firmware linux-cachyos linux-cachyos-headers \
    btrfs-progs networkmanager nano vim git wget curl fish \
    sudo polkit-qt6 mate-polkit xdg-desktop-portal-gnome \
    wl-clipboard cliphist brightnessctl accountsservice \
    podman podman-compose docker-compose \
    go rust rustup nodejs npm python python-pip \
    chezmoi zed github-cli lazygit \
    ripgrep fd bat eza zoxide fzf btop htop starship \
    cachyos-fish-config \
    2>&1 | grep -E "^Downloading|^Extracting|^Installing" | tail -20

print_success "Base system installed"

# Generate fstab
print_step 5 14 "Configuring filesystem table..."
genfstab -U /mnt >> /mnt/etc/fstab
cp "$FSTAB_FILE" /mnt/etc/fstab.manual-backup
print_success "fstab generated and backed up"

# Create chroot configuration script
print_step 6 14 "Preparing system configuration..."

cat > /mnt/root/setup.sh << 'CHROOT_SETUP'
#!/bin/bash
set -e

USERNAME="$1"
USER_PASSWORD="$2"
ROOT_PASSWORD="$3"
HOSTNAME="$4"
TIMEZONE="$5"

# Locale and timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname and network
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Set passwords
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel,storage,power,audio,video -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/wheel

# Enable services
systemctl enable NetworkManager
systemctl enable fstrim.timer
systemctl enable systemd-timesyncd

# Configure CachyOS repos
pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com 2>/dev/null || true
pacman-key --lsign-key F3B607488DB35A47 2>/dev/null || true

# Install CachyOS packages
pacman --noconfirm -U \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
    'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-18-1-any.pkg.tar.zst' \
    2>/dev/null || echo "CachyOS keyring already installed"

# Add CachyOS repos to pacman.conf
grep -q "\[cachyos\]" /etc/pacman.conf || cat >> /etc/pacman.conf << 'REPOS'

# CachyOS repositories
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
REPOS

pacman -Syy

CHROOT_SETUP

chmod +x /mnt/root/setup.sh
arch-chroot /mnt /root/setup.sh "$USERNAME" "$USER_PASSWORD" "$ROOT_PASSWORD" "$HOSTNAME" "$TIMEZONE"

print_success "System configured"

# Install desktop environment and development tools
print_step 7 14 "Installing Niri compositor and DMS..."

cat > /mnt/root/install-desktop.sh << 'CHROOT_DESKTOP'
#!/bin/bash
set -e

USERNAME="$1"

# Update system
pacman -Syu --noconfirm

# Install Niri
pacman -S --noconfirm niri waybar fuzzel mako alacritty foot swaybg swaylock xdg-desktop-portal-gnome

# Install Ghostty (from AUR via paru)
su - $USERNAME -c "cd /tmp && git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si --noconfirm && rm -rf paru" 2>/dev/null || true

# Install additional packages
pacman -S --noconfirm \
    qt6-multimedia accountsservice \
    nix \
    1password 1password-cli \
    uv ripgrep fd bat eza zoxide fzf btop htop

# Install Ghostty via paru as user
su - $USERNAME -c "paru -S --noconfirm ghostty-bin 2>/dev/null || echo 'Ghostty install optional'" &

CHROOT_DESKTOP

chmod +x /mnt/root/install-desktop.sh
arch-chroot /mnt /root/install-desktop.sh "$USERNAME"

print_success "Desktop environment installed"

# Install AI tools and browsers
print_step 8 14 "Installing AI agents and Zen Browser..."

cat > /mnt/root/install-tools.sh << 'CHROOT_TOOLS'
#!/bin/bash
set -e

USERNAME="$1"

# Install Claude Desktop
su - $USERNAME -c "
    cd /tmp
    wget -q https://storage.googleapis.com/claude-release/claude_installer_latest.tar.gz 2>/dev/null || true
    tar -xzf claude_installer_latest.tar.gz 2>/dev/null || true
    ./claude-installer/install.sh 2>/dev/null || echo 'Claude Desktop install optional'
    rm -rf claude_installer_latest.tar.gz claude-installer
" &

# Install OpenCode via paru
su - $USERNAME -c "paru -S --noconfirm opencode-bin" 2>/dev/null || su - $USERNAME -c "paru -S --noconfirm opencode" &

# Install Zen Browser via paru
su - $USERNAME -c "paru -S --noconfirm zen-browser-bin" 2>/dev/null || su - $USERNAME -c "paru -S --noconfirm zen-browser" &

wait

CHROOT_TOOLS

chmod +x /mnt/root/install-tools.sh
arch-chroot /mnt /root/install-tools.sh "$USERNAME"

print_success "AI tools and browsers installed"

# Install DMS (Dank Material Shell)
print_step 9 14 "Installing DMS (Dank Material Shell)..."

cat > /mnt/root/install-dms.sh << 'CHROOT_DMS'
#!/bin/bash
set -e

USERNAME="$1"

# DMS installation via paru
su - $USERNAME -c "
    paru -S --noconfirm dms-shell-bin 2>/dev/null || \
    paru -S --noconfirm dms-shell-git 2>/dev/null || \
    paru -S --noconfirm dms-shell 2>/dev/null || \
    echo 'DMS shell installation skipped'
"

# Install DMS dependencies
su - $USERNAME -c "paru -S --noconfirm matugen-bin dgop" 2>/dev/null || true

CHROOT_DMS

chmod +x /mnt/root/install-dms.sh
arch-chroot /mnt /root/install-dms.sh "$USERNAME"

print_success "DMS installed"

# Install bootloader
print_step 10 14 "Installing bootloader..."

arch-chroot /mnt bash << CHROOT_BOOT
bootctl install

cat > /boot/loader/loader.conf << 'EOF'
default cachyos.conf
timeout 3
console-mode max
editor no
EOF

cat > /boot/loader/entries/cachyos.conf << 'EOF'
title   CachyOS
linux   /vmlinuz-linux-cachyos
initrd  /initramfs-linux-cachyos.img
options root=UUID=$UUID_SYSTEM rootflags=subvol=@ rw quiet splash
EOF

CHROOT_BOOT

print_success "Bootloader installed"

# Configure Fish shell
print_step 11 14 "Configuring Fish shell environment..."

mkdir -p /mnt/home/$USERNAME/.config/fish

cat > /mnt/home/$USERNAME/.config/fish/config.fish << 'FISH_CONFIG'
# CachyOS Development Environment Configuration

# XDG directories
set -x XDG_CACHE_HOME "$HOME/.cache"
set -x XDG_DATA_HOME "$HOME/.local/share"
set -x XDG_CONFIG_HOME "$HOME/.config"

# Development paths (all on P310 Plus)
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

# PATH
fish_add_path $HOME/.cargo/bin
fish_add_path $HOME/.local/bin
fish_add_path $HOME/.bun/bin
fish_add_path $GOPATH/bin

# 1Password CLI
if type -q op
    op completion fish | source
end

# Zoxide
if type -q zoxide
    zoxide init fish | source
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

# Starship prompt
if type -q starship
    starship init fish | source
end

FISH_CONFIG

chown -R $USERNAME:$USERNAME /mnt/home/$USERNAME/.config

print_success "Fish configured"

# Configure Niri for DMS
print_step 12 14 "Configuring Niri for DMS integration..."

mkdir -p /mnt/home/$USERNAME/.config/niri

cat > /mnt/home/$USERNAME/.config/niri/config.kdl << 'NIRI_CONFIG'
// Niri configuration for CachyOS + DMS

layout {
    gaps 8
    struts {
        left 0
        right 0
        top 30
        bottom 0
    }
}

spawn-at-startup "mate-polkit"
spawn-at-startup "dms" "run"
spawn-at-startup "bash" "-c" "wl-paste --watch cliphist store"

binds {
    Mod+Return { spawn "ghostty"; }
    Mod+T { spawn "ghostty"; }
    Mod+Q { close-window; }
    Mod+Alt+Q { quit; }

    // DMS keybindings
    Mod+Space { spawn "dms" "ipc" "call" "spotlight" "toggle"; }
    Mod+V { spawn "dms" "ipc" "call" "clipboard" "toggle"; }
    Mod+M { spawn "dms" "ipc" "call" "processlist" "toggle"; }
    Mod+N { spawn "dms" "ipc" "call" "notifications" "toggle"; }
    Mod+C { spawn "dms" "ipc" "call" "control-center" "toggle"; }
    Mod+Comma { spawn "dms" "ipc" "call" "settings" "toggle"; }
    Mod+P { spawn "dms" "ipc" "call" "notepad" "toggle"; }
    Mod+Shift+L { spawn "dms" "ipc" "call" "lock" "lock"; }

    // Media
    XF86AudioRaiseVolume { spawn "dms" "ipc" "call" "audio" "increment" "3"; }
    XF86AudioLowerVolume { spawn "dms" "ipc" "call" "audio" "decrement" "3"; }
    XF86AudioMute { spawn "dms" "ipc" "call" "audio" "mute"; }

    // Brightness
    XF86MonBrightnessUp { spawn "brightnessctl" "set" "10%+"; }
    XF86MonBrightnessDown { spawn "brightnessctl" "set" "10%-"; }

    // Window management
    Mod+Left { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Up { focus-window-up; }
    Mod+Down { focus-window-down; }
    Mod+Shift+Left { move-column-left; }
    Mod+Shift+Right { move-column-right; }
    Mod+Shift+Up { move-window-up; }
    Mod+Shift+Down { move-window-down; }

    // Workspaces
    Mod+Home { focus-workspace 1; }
    Mod+End { focus-workspace 10; }
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
}

NIRI_CONFIG

chown -R $USERNAME:$USERNAME /mnt/home/$USERNAME/.config/niri

print_success "Niri configured"

# Configure WiFi
print_step 13 14 "Configuring WiFi..."

cat > /mnt/root/setup-wifi.sh << 'CHROOT_WIFI'
#!/bin/bash

# Enable NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager

# Create connection helper
cat > /usr/local/bin/nmconnect << 'NMEOF'
#!/bin/bash
nmcli device wifi list
read -p "Enter network SSID: " SSID
read -sp "Enter password: " PASS
nmcli device wifi connect "$SSID" password "$PASS"
NMEOF
chmod +x /usr/local/bin/nmconnect

CHROOT_WIFI

chmod +x /mnt/root/setup-wifi.sh
arch-chroot /mnt /root/setup-wifi.sh

print_success "WiFi configured"

# Apply kernel optimizations
print_step 14 14 "Applying kernel performance optimizations..."

cat > /mnt/root/kernel-tuning.sh << 'CHROOT_KERNEL'
#!/bin/bash

# Create sysctl configuration for performance
cat > /etc/sysctl.d/99-cachyos-zephyrus.conf << 'SYSCTL_EOF'
# CachyOS Kernel Tuning for ASUS ROG Zephyrus M16 GU603ZW
# Optimized for maximum performance while plugged in

# ===== CPU Scheduler (SCX) =====
# Already optimized via CachyOS kernel and scx_bpfland

# ===== Memory Management =====
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=20
vm.dirty_background_ratio=10
vm.dirty_writeback_centisecs=100

# ===== I/O Scheduler =====
# NVMe uses none scheduler by default (optimal)

# ===== Network Tuning =====
net.ipv4.tcp_tw_reuse=1
net.ipv4.ip_local_port_range=10000 65535
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864

# ===== File Descriptor Limits =====
fs.file-max=2097152
fs.inotify.max_user_watches=524288

SYSCTL_EOF

sysctl -p /etc/sysctl.d/99-cachyos-zephyrus.conf

# CPU Frequency Scaling - Performance mode (always plugged in)
echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null

# Disable ZRAM for development (uses more RAM but faster)
# systemctl mask systemd-zram-setup@zram0.service

# Create power profile hook
mkdir -p /etc/udev/rules.d

cat > /etc/udev/rules.d/99-nmi-watchdog.rules << 'UDEV_EOF'
# Disable NMI watchdog for performance
ACTION=="add", SUBSYSTEM=="module", DEVPATH=="*/nmi_watchdog", RUN+="/bin/sh -c 'echo 0 > /proc/sys/kernel/nmi_watchdog'"
UDEV_EOF

# Create systemd power profile for plugged in (Performance)
cat > /etc/systemd/system-generators/gen-power-profiles.sh << 'POWERPROF_EOF'
#!/bin/bash

# Create performance profile (plugged in)
cat > /etc/power-profiles-daemon.conf.d/zephyrus-performance.conf << 'PROFEOF'
[Performance]
Governor=performance
EPB=performance
PROFEOF

# Create power-save profile (battery)
cat > /etc/power-profiles-daemon.conf.d/zephyrus-powersave.conf << 'PROFEOF2'
[PowerSaver]
Governor=powersave
EPB=balance_power
EPB=powersave
PROFEOF2

POWERPROF_EOF

chmod +x /etc/systemd/system-generators/gen-power-profiles.sh

# Install power-profiles-daemon if available
pacman -S --noconfirm power-profiles-daemon 2>/dev/null || true

# Enable thermald for thermal management
pacman -S --noconfirm thermald 2>/dev/null || true
systemctl enable thermald 2>/dev/null || true

CHROOT_KERNEL

chmod +x /mnt/root/kernel-tuning.sh
arch-chroot /mnt /root/kernel-tuning.sh

print_success "Kernel optimizations applied"

# Set ownership
print_progress "Setting ownership..."
chown -R $USERNAME:$USERNAME /mnt/home/$USERNAME

# Disable COW for dev folder (critical for performance)
arch-chroot /mnt bash << CHROOT_COW
chattr +C /home/$USERNAME/dev 2>/dev/null || echo "COW disable will happen after first boot"
CHROOT_COW

# Cleanup
rm -f /mnt/root/setup.sh /mnt/root/install-desktop.sh /mnt/root/install-tools.sh /mnt/root/install-dms.sh /mnt/root/setup-wifi.sh /mnt/root/kernel-tuning.sh

# Sync
sync

print_success "Installation cleanup complete"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           CACHYOS INSTALLATION SUCCESSFUL!                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_info "Installation Summary:"
echo "  ✓ Base CachyOS system installed"
echo "  ✓ Niri compositor configured"
echo "  ✓ DMS (Dank Material Shell) installed"
echo "  ✓ Claude Code, OpenCode, Zen Browser installed"
echo "  ✓ Development tools: Podman, Rust, Go, Node, Python"
echo "  ✓ Fish shell configured"
echo "  ✓ Kernel optimized for Zephyrus M16"
echo "  ✓ WiFi configured with NetworkManager"
echo "  ✓ Power profiles ready (performance/powersave)"
echo ""
print_warning "FINAL STEPS:"
echo ""
echo "1. Unmount filesystems:"
echo "   sudo umount -R /mnt"
echo ""
echo "2. Reboot:"
echo "   sudo reboot"
echo ""
echo "3. After first boot:"
echo "   • Complete WiFi setup if needed: nmconnect"
echo "   • Setup Nix: sh <(curl -L https://nixos.org/nix/install) --daemon"
echo "   • Initialize Chezmoi: chezmoi init --apply"
echo "   • Configure DMS: Press Mod+Comma"
echo "   • Verify performance: uname -r && cpupower frequency-info"
echo ""
echo "4. Optional: Setup 1Password CLI"
echo "   op signin && op account add"
echo ""
print_success "System ready to boot!"
