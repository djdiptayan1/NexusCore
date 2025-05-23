# NexusCore Setup Script v2.1 for Ubuntu 24.04.2 LTS

# Exit on any error, treat unset variables as an error, and ensure pipelines fail on error
set -euo pipefail

# --- Configuration ---
# Change these variables to match your preferences
ADMIN_USER="djdiptayan"
ADDITIONAL_USER="anwin"
JAVA_VERSION="17"
INSTALL_DOCKER=true
INSTALL_PYTHON=true
INSTALL_MINICONDA=true
INSTALL_JAVA=true
INSTALL_CPP=true
INSTALL_NODEJS=true
INSTALL_CLOUDFLARED=true
INSTALL_MONITORING_TOOLS=true
SETUP_UFW=true
ENABLE_PASSWORD_AUTH=true

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

print_banner() {
    echo -e "\033[1;35m"
    echo "███    ██ ███████ ██   ██ ██    ██ ███████  ██████  ██████  ██████  ███████ "
    echo "████   ██ ██       ██ ██  ██    ██ ██      ██      ██    ██ ██   ██ ██      "
    echo "██ ██  ██ █████     ███   ██    ██ ███████ ██      ██    ██ ██████  █████   "
    echo "██  ██ ██ ██       ██ ██  ██    ██      ██ ██      ██    ██ ██   ██ ██      "
    echo "██   ████ ███████ ██   ██  ██████  ███████  ██████  ██████  ██   ██ ███████ "
    echo -e "\033[0m"
    echo -e "\033[1;36mAdvanced Server Setup Script v2.1 for Ubuntu 24.04.2 LTS\033[0m"
    echo
}

check_os_compatibility() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_error "This script is designed for Ubuntu only. Detected: $ID"
            exit 1
        fi
        
        if [[ ! "$VERSION_ID" =~ ^24\.04.* ]]; then
            log_warning "This script is optimized for Ubuntu 24.04. Detected: $VERSION_ID"
            read -p "Do you want to continue anyway? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        log_error "Unable to determine OS. This script is designed for Ubuntu 24.04 LTS."
        exit 1
    fi
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.$(date +%Y%m%d%H%M%S).bak"
        cp "$file" "$backup"
        log_info "Created backup of $file at $backup"
    fi
}

setup_user_environment() {
    local username="$1"
    local user_home="/home/$username"
    
    log_info "Setting up development environment for user: $username"
    
    # NVM setup for the user
    if [ "$INSTALL_NODEJS" = true ]; then
        log_info "Setting up NVM for user $username..."
        sudo -u "$username" bash << 'EOF'
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
    mkdir -p "$NVM_DIR"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    if command -v nvm &> /dev/null; then
        set +u
        nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
        set -u
    fi
    
    # Add to bashrc
    if ! grep -q 'export NVM_DIR="$HOME/.nvm"' ~/.bashrc 2>/dev/null; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc
    fi
    
    # Add to zshrc if it exists
    if [ -f "$HOME/.zshrc" ] && ! grep -q 'export NVM_DIR="$HOME/.nvm"' ~/.zshrc 2>/dev/null; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.zshrc
    fi
fi
EOF
    fi
    
    # Miniconda setup for the user
    if [ "$INSTALL_MINICONDA" = true ]; then
        log_info "Setting up Miniconda for user $username..."
        sudo -u "$username" bash << 'EOF'
CONDA_DIR="$HOME/miniconda3"
if [ ! -d "$CONDA_DIR/bin" ]; then
    mkdir -p "$CONDA_DIR"
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$HOME/miniconda_installer.sh"
    bash "$HOME/miniconda_installer.sh" -b -u -p "$CONDA_DIR"
    rm "$HOME/miniconda_installer.sh"
    eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
    "$CONDA_DIR/bin/conda" init bash
    
    if [ -f "$HOME/.zshrc" ]; then
        "$CONDA_DIR/bin/conda" init zsh
    fi
    
    conda config --set auto_activate_base false
fi
EOF
    fi
    
    # Create system logs directory for the user
    sudo -u "$username" mkdir -p "$user_home/system_logs"
    
    log_success "Development environment set up for user: $username"
}

create_restricted_sudo_user() {
    local username="$1"
    
    log_info "Creating user '$username' with restricted sudo privileges..."
    
    # Create the user if it doesn't exist
    if ! id "$username" &>/dev/null; then
        sudo adduser --disabled-password --gecos "" "$username"
        log_info "User '$username' created."
        
        # Set a temporary password and force password change on first login
        echo "Please set a password for user '$username':"
        sudo passwd "$username"
        sudo chage -d 0 "$username"  # Force password change on first login
    else
        log_info "User '$username' already exists."
    fi
    
    # Add user to necessary groups
    sudo usermod -aG sudo "$username"
    if [ "$INSTALL_DOCKER" = true ]; then
        sudo usermod -aG docker "$username"
    fi
    
    # Create sudoers configuration for restricted access
    sudo tee "/etc/sudoers.d/${username}_restricted" > /dev/null << EOF
# Define command aliases for user management restrictions
Cmnd_Alias USERMOD_CMDS = /usr/sbin/adduser, /usr/sbin/useradd, /usr/sbin/userdel, /usr/sbin/usermod, /usr/sbin/deluser
Cmnd_Alias USER_PASSWD_CMDS = /usr/bin/passwd [A-z]*, /usr/sbin/chpasswd, /usr/sbin/newusers

# Allow $username to run most commands with sudo, but restrict user management
$username ALL=(ALL:ALL) ALL, !USERMOD_CMDS, !USER_PASSWD_CMDS

# Allow $username to change their own password
$username ALL=(ALL) NOPASSWD: /usr/bin/passwd $username
EOF
    
    sudo chmod 440 "/etc/sudoers.d/${username}_restricted"
    
    # Verify sudoers file syntax
    if sudo visudo -c; then
        log_success "Sudoers file syntax is valid."
    else
        log_error "Sudoers file syntax error. Removing the restricted configuration."
        sudo rm "/etc/sudoers.d/${username}_restricted"
        exit 1
    fi
    
    log_success "User '$username' created with restricted sudo privileges (cannot manage users)."
}

# --- Initial Setup & Sanity Checks ---
print_banner
check_os_compatibility

log_info "Starting NexusCore Advanced Server Setup v2.1 for users: $ADMIN_USER and $ADDITIONAL_USER"
if [ "$(id -u)" = "0" ]; then
   log_error "This script should not be run as root. Run as a sudo-enabled user (e.g., $ADMIN_USER)."
   exit 1
fi

if ! sudo -n true 2>/dev/null; then
    log_warning "Sudo access for $USER requires a password. You may be prompted multiple times."
fi

# Create the additional user early in the process
create_restricted_sudo_user "$ADDITIONAL_USER"

log_info "Updating package lists and upgrading existing packages..."
sudo apt update
sudo apt upgrade -y
log_success "System updated and upgraded."

# --- Install Basic Utilities & Build Tools ---
log_info "Installing essential packages, development tools, and neofetch..."
sudo apt install -y \
    git curl wget build-essential software-properties-common apt-transport-https \
    ca-certificates gnupg lsb-release unzip zip make cmake pkg-config autoconf automake \
    libtool gettext tree htop btop nvtop iotop iftop ncdu gnupg2 pass neofetch
log_success "Essential packages, development tools, and neofetch installed."

# --- Firewall (UFW) ---
if [ "$SETUP_UFW" = true ]; then
    log_info "Setting up UFW (Uncomplicated Firewall)..."
    if ! command -v ufw &> /dev/null; then sudo apt install -y ufw; fi
    sudo ufw allow ssh
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw --force enable
    sudo ufw status verbose
    log_success "UFW configured and enabled."
else
    log_info "Skipping UFW setup as per configuration."
fi

# --- Install Programming Languages & Runtimes ---
# Python
if [ "$INSTALL_PYTHON" = true ]; then
    log_info "Ensuring Python 3, pip, venv, and dev headers are installed..."
    sudo apt install -y python3 python3-pip python3-venv python3-dev
    log_success "Python 3 are set up."
fi

# Java
if [ "$INSTALL_JAVA" = true ]; then
    log_info "Installing OpenJDK $JAVA_VERSION..."
    sudo apt install -y openjdk-${JAVA_VERSION}-jdk openjdk-${JAVA_VERSION}-jre
    log_success "OpenJDK $JAVA_VERSION (JDK & JRE) installed."
fi

# C/C++
if [ "$INSTALL_CPP" = true ]; then
    log_info "Ensuring C/C++ toolchain (gcc, g++, gdb, clang) is installed..."
    sudo apt install -y gcc g++ gdb clang valgrind
    log_success "C/C++ toolchain installed."
fi

# Node.js (via NVM) - for current user
if [ "$INSTALL_NODEJS" = true ]; then
    log_info "Installing Node.js via NVM for current user..."
    export NVM_DIR="$HOME/.nvm"
    if [ ! -d "$NVM_DIR" ]; then
        mkdir -p "$NVM_DIR"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        if command -v nvm &> /dev/null; then
            set +u
            nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
            set -u
            log_success "Node.js LTS installed via NVM and activated for this session."
        else log_error "NVM installation failed."; fi
    else
        log_info "NVM already installed. Sourcing and ensuring LTS Node.js."
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
        set +u
        if ! nvm ls 'lts/*' &> /dev/null || ! (nvm current | grep -q 'lts'); then
            nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
        fi
        set -u
        
        log_success "NVM sourced, Node.js LTS configured and activated for this session."
    fi
    
    # Add to bashrc and zshrc
    if ! grep -q 'export NVM_DIR="$HOME/.nvm"' ~/.bashrc 2>/dev/null; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc
        log_info "NVM configuration added to .bashrc"
    fi
    
    if [ -f "$HOME/.zshrc" ] && ! grep -q 'export NVM_DIR="$HOME/.nvm"' ~/.zshrc 2>/dev/null; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.zshrc
        log_info "NVM configuration added to .zshrc"
    fi
    
    # Install global npm packages
    if command -v npm &> /dev/null; then
        set +u
        npm install -g yarn typescript ts-node nodemon pm2
        set -u
        log_success "Installed global npm packages: yarn, typescript, ts-node, nodemon, pm2"
    fi
fi

# Docker & Docker Compose
if [ "$INSTALL_DOCKER" = true ]; then
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
    
    # Add both users to docker group
    for user in "$ADMIN_USER" "$ADDITIONAL_USER"; do
        if ! groups "$user" | grep -q '\bdocker\b'; then
            sudo usermod -aG docker "$user"
            log_info "User $user added to docker group."
        else
            log_info "User $user is already a member of the docker group."
        fi
    done
    
    sudo systemctl enable --now docker
    log_success "Docker and Docker Compose installed and service enabled/started."
fi

# Miniconda - for current user
if [ "$INSTALL_MINICONDA" = true ]; then
    log_info "Installing Miniconda for current user..."
    CONDA_DIR="$HOME/miniconda3"
    if [ ! -d "$CONDA_DIR/bin" ]; then
        mkdir -p "$CONDA_DIR"
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$HOME/miniconda_installer.sh"
        bash "$HOME/miniconda_installer.sh" -b -u -p "$CONDA_DIR"
        rm "$HOME/miniconda_installer.sh"
        eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
        "$CONDA_DIR/bin/conda" init bash
        
        if [ -f "$HOME/.zshrc" ]; then
            "$CONDA_DIR/bin/conda" init zsh
        fi
        
        log_success "Miniconda installed to $CONDA_DIR and activated for this session."
    else
        log_info "Miniconda already installed. Sourcing for current session."
        eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
        log_success "Miniconda sourced for this session."
    fi
    
    conda config --set auto_activate_base false
    log_success "Configured conda to not auto-activate base environment."
fi

# --- Monitoring Tools ---
if [ "$INSTALL_MONITORING_TOOLS" = true ]; then
    log_info "Installing monitoring tools (htop, nvtop, btop, glances, bpytop, radeontop, lm-sensors)..."
    sudo apt install -y htop nvtop btop glances bpytop radeontop lm-sensors
    log_success "Monitoring tools installed."
fi

# --- Install Cloudflared ---
if [ "$INSTALL_CLOUDFLARED" = true ]; then
    log_info "Installing cloudflared..."
    if ! command -v cloudflared &> /dev/null; then
        ARCH=$(dpkg --print-architecture)
        CLOUDFLARED_LATEST_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
        wget -O /tmp/cloudflared.deb "${CLOUDFLARED_LATEST_URL}"
        sudo dpkg -i /tmp/cloudflared.deb
        sudo apt-get install -f -y
        rm /tmp/cloudflared.deb
        log_success "cloudflared $(cloudflared --version) installed and configured."
    else
        log_info "cloudflared already installed. Version: $(cloudflared --version)"
    fi
fi

# --- Security Improvements ---
log_info "Installing and configuring additional security tools..."

# Install fail2ban for SSH protection
log_info "Installing fail2ban for SSH protection..."
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Create a basic fail2ban config for SSH if it doesn't exist
if [ ! -f /etc/fail2ban/jail.d/sshd.conf ]; then
    log_info "Creating basic fail2ban configuration for SSH..."
    cat << 'EOF' | sudo tee /etc/fail2ban/jail.d/sshd.conf > /dev/null
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
EOF
    sudo systemctl restart fail2ban
    log_success "fail2ban configured to protect SSH."
fi

# --- Set up development environments for additional user ---
setup_user_environment "$ADDITIONAL_USER"

# --- Create System Logs Directory ---
log_info "Creating system logs directory..."
LOGS_DIR="$HOME/system_logs"
mkdir -p "$LOGS_DIR"
date > "$LOGS_DIR/setup_complete_date.log"
uname -a > "$LOGS_DIR/system_info.log"
lscpu > "$LOGS_DIR/cpu_info.log"
free -h > "$LOGS_DIR/memory_info.log"
df -h > "$LOGS_DIR/disk_info.log"
ip addr > "$LOGS_DIR/network_info.log"
if command -v docker &> /dev/null; then
    docker info > "$LOGS_DIR/docker_info.log" 2>/dev/null || echo "Docker not running or permission issue" > "$LOGS_DIR/docker_info.log"
fi
log_success "System logs directory created at $LOGS_DIR"

# --- Final Steps & System Information ---
log_success "NexusCore Advanced Setup script v2.1 completed!"

log_info "-------------------- SYSTEM INFORMATION --------------------"
echo -e "\033[1;32mHostname:\033[0m $(hostname)"
SERVER_IPS=$(hostname -I)
echo -e "\033[1;32mServer IP Addresses:\033[0m $SERVER_IPS"
echo -e "\033[1;33mTo SSH into this server (from another machine on the same network), use one of these IPs:\033[0m"
for ip in $SERVER_IPS; do
    echo "ssh $ADMIN_USER@$ip"
    echo "ssh $ADDITIONAL_USER@$ip"
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
df -hT
echo ""

log_info "-------------------- USER INFORMATION --------------------"
echo -e "\033[1;32mUsers created:\033[0m"
echo -e "  • $ADMIN_USER (full sudo access)"
echo -e "  • $ADDITIONAL_USER (restricted sudo - cannot manage users)"
echo ""

log_info "-------------------- IMPORTANT NEXT STEPS --------------------"
log_info "1. User '$ADDITIONAL_USER' Setup:"
echo -e "   \033[1;36mSwitch to user:\033[0m sudo su - $ADDITIONAL_USER"
echo -e "   \033[1;36mLogin as user:\033[0m ssh $ADDITIONAL_USER@<server-ip>"
echo -e "   \033[1;36mPassword change:\033[0m The user will be prompted to change password on first login"
echo ""

log_info "2. Development Environment Activation:"
echo -e "   \033[1;36mFor both users:\033[0m source ~/.bashrc"
echo -e "   \033[1;36mTest Node.js:\033[0m node -v"
echo -e "   \033[1;36mTest Conda:\033[0m conda --version"
echo ""

log_info "3. Docker Permissions:"
echo -e "   \033[1;36mBoth users added to docker group. To apply:\033[0m"
echo -e "   \033[1;36mOption 1:\033[0m Log out and log back in"
echo -e "   \033[1;36mOption 2:\033[0m newgrp docker"
echo -e "   \033[1;36mTest Docker:\033[0m docker run hello-world"
echo ""

log_info "4. User '$ADDITIONAL_USER' Restrictions:"
echo -e "   \033[1;33mCannot run:\033[0m adduser, useradd, userdel, usermod, deluser"
echo -e "   \033[1;33mCannot change other users' passwords\033[0m"
echo -e "   \033[1;32mCan do everything else with sudo\033[0m"
echo -e "   \033[1;36mTest restrictions:\033[0m sudo adduser testuser (should be denied)"
echo ""

log_info "5. Configure hardware monitoring tools:"
echo -e "   \033[1;36mSensors setup:\033[0m sudo sensors-detect"
echo -e "   \033[1;36mView sensors:\033[0m sensors"
echo -e "   \033[1;36mMonitor tools:\033[0m htop, glances, bpytop"
echo ""

log_info "6. Security and Access:"
echo -e "   \033[1;36mCheck fail2ban:\033[0m sudo fail2ban-client status"
echo -e "   \033[1;36mGenerate SSH keys for both users:\033[0m ssh-keygen -t ed25519"
echo -e "   \033[1;36mFirewall status:\033[0m sudo ufw status verbose"
echo ""

log_info "7. Cloudflare Tunnel (available for both users):"
echo -e "   \033[1;36mLogin:\033[0m cloudflared tunnel login"
echo -e "   \033[1;36mCreate tunnel:\033[0m cloudflared tunnel create <tunnel-name>"
echo ""

log_info "NexusCore Setup Completed for users: $ADMIN_USER and $ADDITIONAL_USER"
echo -e "\n\033[1;35m--- Both users '$ADMIN_USER' and '$ADDITIONAL_USER' are ready to use! ---\033[0m"
echo
read -p "Reboot now to apply all changes? (y/N): " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi