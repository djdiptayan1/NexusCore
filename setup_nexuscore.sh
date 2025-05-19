#!/bin/bash

# NexusCore Advanced Setup Script v2 for Ubuntu 24.04.2 LTS

# Exit on any error, treat unset variables as an error, and ensure pipelines fail on error
set -euo pipefail

# --- Configuration ---
ADMIN_USER="djdiptayan"

# --- Helper Functions ---
log_info() {
    echo -e "\n\033[1;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

log_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 command not found. Please install it or check your PATH."
        exit 1
    fi
}

# --- Initial Setup & Sanity Checks ---
log_info "Starting NexusCore Advanced Server Setup v2 for user: $ADMIN_USER"
if [ "$(id -u)" = "0" ]; then
   log_error "This script should not be run as root. Run as a sudo-enabled user (e.g., $ADMIN_USER)."
   exit 1
fi

if ! sudo -n true 2>/dev/null; then
    log_warning "Sudo access for $USER requires a password. You may be prompted multiple times."
fi

log_info "Updating package lists and upgrading existing packages..."
sudo apt update
sudo apt upgrade -y
log_success "System updated and upgraded."

# --- SSH Configuration Verification ---
log_info "Verifying SSH configuration..."
if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
    log_success "SSH service (sshd or ssh) is active."
else
    log_warning "SSH service does not seem to be active. Attempting to install and enable..."
    sudo apt install -y openssh-server
    sudo systemctl enable ssh
    sudo systemctl start ssh
    if systemctl is-active --quiet ssh; then
        log_success "SSH service installed and started."
    else
        log_error "Failed to start SSH service. Please check manually."
        exit 1
    fi
fi

SSH_CONFIG_FILE="/etc/ssh/sshd_config"
SSH_CONFIG_INCLUDE_DIR="/etc/ssh/sshd_config.d/"
PASSWORD_AUTH_SET=false
AUTH_TARGET_FILE=""

set_password_auth() {
    local file_to_check="$1"
    if grep -qE "^\s*PasswordAuthentication\s+yes" "$file_to_check"; then
        PASSWORD_AUTH_SET=true; AUTH_TARGET_FILE="$file_to_check"; return 0;
    elif grep -qE "^\s*#\s*PasswordAuthentication\s+yes" "$file_to_check"; then
        sudo sed -i.bak 's/^\s*#\s*PasswordAuthentication\s+yes/PasswordAuthentication yes/' "$file_to_check"
        PASSWORD_AUTH_SET=true; AUTH_TARGET_FILE="$file_to_check"; return 0;
    elif grep -qE "^\s*PasswordAuthentication\s+no" "$file_to_check"; then
        sudo sed -i.bak 's/^\s*PasswordAuthentication\s+no/PasswordAuthentication yes/' "$file_to_check"
        PASSWORD_AUTH_SET=true; AUTH_TARGET_FILE="$file_to_check"; return 0;
    fi
    return 1
}

if [ -f "$SSH_CONFIG_FILE" ]; then set_password_auth "$SSH_CONFIG_FILE"; fi
if [ "$PASSWORD_AUTH_SET" = false ] && [ -d "$SSH_CONFIG_INCLUDE_DIR" ]; then
    for conf_file in "$SSH_CONFIG_INCLUDE_DIR"*.conf; do
        if [ -f "$conf_file" ]; then if set_password_auth "$conf_file"; then break; fi; fi
    done
fi
if [ "$PASSWORD_AUTH_SET" = false ]; then
    if [ -f "$SSH_CONFIG_FILE" ] && ! grep -qE "^\s*PasswordAuthentication" "$SSH_CONFIG_FILE"; then
        echo "PasswordAuthentication yes" | sudo tee -a "$SSH_CONFIG_FILE" > /dev/null
        AUTH_TARGET_FILE="$SSH_CONFIG_FILE"
        log_info "Added 'PasswordAuthentication yes' to $SSH_CONFIG_FILE."
    else
        log_warning "Could not confidently set PasswordAuthentication to 'yes'. Please verify SSH config manually."
    fi
fi

if [ -n "$AUTH_TARGET_FILE" ]; then
    log_info "Restarting SSH service due to config change..."
    sudo systemctl restart sshd
    log_success "SSH configured for password authentication (verified/set in $AUTH_TARGET_FILE)."
else
    log_success "SSH password authentication status remains as found or no clear target for modification."
fi
log_warning "SECURITY WARNING: Password-only SSH is less secure. Use strong passwords and consider tools like fail2ban."

# --- Install Basic Utilities & Build Tools ---
log_info "Installing essential packages, development tools, and neofetch..."
sudo apt install -y \
    git curl wget build-essential software-properties-common apt-transport-https \
    ca-certificates gnupg lsb-release unzip zip make cmake pkg-config autoconf automake \
    libtool gettext tree htop iotop iftop ncdu gnupg2 pass neofetch
log_success "Essential packages, development tools, and neofetch installed."

# --- Firewall (UFW) ---
log_info "Setting up UFW (Uncomplicated Firewall)..."
if ! command -v ufw &> /dev/null; then sudo apt install -y ufw; fi
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status verbose
log_success "UFW configured and enabled."

# --- Install Programming Languages & Runtimes ---
# Python
log_info "Ensuring Python 3, pip, venv, and dev headers are installed..."
sudo apt install -y python3 python3-pip python3-venv python3-dev
log_success "Python 3, pip, venv, and dev headers are set up."

# Java
JAVA_VERSION="17"
log_info "Installing OpenJDK $JAVA_VERSION..."
sudo apt install -y openjdk-${JAVA_VERSION}-jdk openjdk-${JAVA_VERSION}-jre
log_success "OpenJDK $JAVA_VERSION (JDK & JRE) installed."

# C/C++
log_info "Ensuring C/C++ toolchain (gcc, g++, gdb, clang) is installed..."
sudo apt install -y gcc g++ gdb clang
log_success "C/C++ toolchain installed."

# Node.js (via NVM)
log_info "Installing Node.js via NVM..."
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    mkdir -p "$NVM_DIR"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash # Check latest NVM
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    if command -v nvm &> /dev/null; then
        nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
        log_success "Node.js LTS installed via NVM and activated for this session."
    else log_error "NVM installation failed."; fi
else
    log_info "NVM already installed. Sourcing and ensuring LTS Node.js."
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    if ! nvm ls 'lts/*' &> /dev/null || ! (nvm current | grep -q 'lts'); then
        nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
    fi
    log_success "NVM sourced, Node.js LTS configured and activated for this session."
fi
echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> ~/.bashrc
echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> ~/.bashrc


# Docker & Docker Compose
log_info "Installing Docker and Docker Compose..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
fi
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if ! groups "$ADMIN_USER" | grep -q '\bdocker\b'; then
    sudo usermod -aG docker "$ADMIN_USER"
    log_info "User $ADMIN_USER added to docker group. CRITICAL: Re-login or use 'newgrp docker' in a new shell for this to take full effect for your interactive session."
else
    log_info "User $ADMIN_USER is already a member of the docker group."
fi
sudo systemctl enable --now docker
log_success "Docker and Docker Compose installed and service enabled/started."

# Miniconda
log_info "Installing Miniconda..."
CONDA_DIR="$HOME/miniconda3"
if [ ! -d "$CONDA_DIR/bin" ]; then
    mkdir -p "$CONDA_DIR"
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$HOME/miniconda_installer.sh"
    bash "$HOME/miniconda_installer.sh" -b -u -p "$CONDA_DIR"
    rm "$HOME/miniconda_installer.sh"
    # shellcheck source=/dev/null
    eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
    "$CONDA_DIR/bin/conda" init bash
    log_success "Miniconda installed to $CONDA_DIR and activated for this session. Bashrc updated."
else
    log_info "Miniconda already installed. Sourcing for current session."
    # shellcheck source=/dev/null
    eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
    log_success "Miniconda sourced for this session."
fi

# --- Monitoring Tools ---
log_info "Installing monitoring tools (htop, glances, bpytop, radeontop, lm-sensors)..."
sudo apt install -y htop glances bpytop radeontop lm-sensors
log_success "Monitoring tools installed."
log_info "For lm-sensors: run 'sudo sensors-detect' (interactive) then 'sensors' to view."

# --- Install Cloudflared ---
log_info "Installing cloudflared..."
if ! command -v cloudflared &> /dev/null; then
    ARCH=$(dpkg --print-architecture)
    CLOUDFLARED_LATEST_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
    wget -O /tmp/cloudflared.deb "${CLOUDFLARED_LATEST_URL}"
    sudo dpkg -i /tmp/cloudflared.deb
    sudo apt-get install -f -y # Install dependencies if any
    rm /tmp/cloudflared.deb
    log_success "cloudflared $(cloudflared --version) installed."
else
    log_info "cloudflared already installed. Version: $(cloudflared --version)"
fi

# --- Final Steps & System Information ---
log_success "NexusCore Advanced Setup script completed!"

log_info "-------------------- SYSTEM INFORMATION --------------------"
echo -e "\033[1;32mHostname:\033[0m $(hostname)"
SERVER_IPS=$(hostname -I)
echo -e "\033[1;32mServer IP Addresses:\033[0m $SERVER_IPS"
echo -e "\033[1;33mTo SSH into this server (from another machine on the same network), use one of these IPs:\033[0m"
for ip in $SERVER_IPS; do
    echo "ssh $ADMIN_USER@$ip"
done
echo ""

if command -v neofetch &> /dev/null; then
    log_info "System Summary (neofetch):"
    neofetch
else
    log_info "OS Version:"
    lsb_release -a
    log_info "Kernel:"
    uname -a
fi
echo ""

log_info "CPU Information:"
lscpu | grep -E 'Model name|Socket|Core|Thread|CPU MHz|Virtualization'
echo ""

log_info "RAM Usage:"
free -h
echo ""

log_info "Disk Usage (OS SSD):"
df -h /
df -hT # Show all filesystems with types
echo ""

log_info "-------------------- IMPORTANT NEXT STEPS --------------------"
log_info "1. NVM & Conda: Activated for this script's session. Your ~/.bashrc has been updated for future logins. For immediate effect in your *current interactive shell* (if different from this script's execution context), run: source ~/.bashrc"
log_info "2. Docker Permissions: User $ADMIN_USER was added to the 'docker' group. For this change to apply to your *current interactive shell*, you MUST either:"
log_info "   a) Log out and log back in."
log_info "   b) Or, in a new terminal tab/window, run: newgrp docker (this starts a new shell with the correct group)."
log_info "3. Configure lm-sensors: Run 'sudo sensors-detect' and follow prompts, then use 'sensors' to view hardware temperatures."
log_info "4. Secure your server further: Consider 'sudo apt install fail2ban' and other security measures."
log_info "5. Set up Cloudflare Tunnel: Run 'cloudflared tunnel login', then create and configure your tunnel as previously discussed."
log_info "6. To add more users: 'sudo adduser newusername', set password. Grant sudo if needed: 'sudo usermod -aG sudo newusername'."

echo -e "\n\033[1;35m--- Review the 'IMPORTANT NEXT STEPS' above carefully! --- \033[0m"
