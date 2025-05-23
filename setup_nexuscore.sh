#!/bin/bash
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
INSTALL_MINICONDA=true # Installs for the user running the script & ADDITIONAL_USER
INSTALL_JAVA=true
INSTALL_CPP=true
INSTALL_NODEJS=true    # Installs NVM for the user running the script & ADDITIONAL_USER
INSTALL_CLOUDFLARED=true
INSTALL_MONITORING_TOOLS=true
SETUP_UFW=true
ENABLE_PASSWORD_AUTH=true # This variable is declared but not used in the provided script. Assuming it's for future SSH config.

# New: AMD GPU Driver Configuration
INSTALL_AMD_GPU_DRIVERS=false # Set to true to install AMD GPU drivers (ROCm)
# URL and Filename for AMD GPU installer for Ubuntu 24.04 (Noble Numbat)
# Please verify/update this URL for the latest/desired ROCm version for Noble from official AMD sources.
AMD_GPU_INSTALLER_FULL_URL="https://repo.radeon.com/amdgpu-install/6.4.1/ubuntu/noble/amdgpu-install_6.4.60401-1_all.deb"
AMD_GPU_INSTALLER_FILENAME="amdgpu-install_6.4.60401-1_all.deb"


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
    local user_home
    user_home=$(eval echo "~$username") # Robust way to get home directory
    
    if [ ! -d "$user_home" ]; then
        log_warning "Home directory for user $username ($user_home) not found. Skipping environment setup for this user."
        return
    fi

    log_info "Setting up development environment for user: $username"
    
    # NVM setup for the user
    if [ "$INSTALL_NODEJS" = true ]; then
        log_info "Setting up NVM for user $username..."
        sudo -u "$username" bash -e -u -o pipefail << EOF
export NVM_DIR="\$HOME/.nvm"
if [ ! -d "\$NVM_DIR" ]; then
    mkdir -p "\$NVM_DIR"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    [ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
    [ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
    if command -v nvm &> /dev/null; then
        set +u # NVM scripts might use unbound variables
        nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
        set -u
    fi
    
    # Add to bashrc
    if ! grep -q 'export NVM_DIR="\$HOME/.nvm"' \$HOME/.bashrc 2>/dev/null; then
        echo '' >> \$HOME/.bashrc
        echo 'export NVM_DIR="\$HOME/.nvm"' >> \$HOME/.bashrc
        echo '[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"  # This loads nvm' >> \$HOME/.bashrc
        echo '[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> \$HOME/.bashrc
    fi
    
    # Add to zshrc if it exists
    if [ -f "\$HOME/.zshrc" ] && ! grep -q 'export NVM_DIR="\$HOME/.nvm"' \$HOME/.zshrc 2>/dev/null; then
        echo '' >> \$HOME/.zshrc
        echo 'export NVM_DIR="\$HOME/.nvm"' >> \$HOME/.zshrc
        echo '[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"' >> \$HOME/.zshrc
        echo '[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"' >> \$HOME/.zshrc
    fi
fi
EOF
    fi
    
    # Miniconda setup for the user
    if [ "$INSTALL_MINICONDA" = true ]; then
        log_info "Setting up Miniconda for user $username..."
        sudo -u "$username" bash -e -u -o pipefail << EOF
CONDA_DIR="\$HOME/miniconda3"
if [ ! -d "\$CONDA_DIR/bin" ]; then
    mkdir -p "\$HOME/miniconda_tmp" # Temporary directory for installer
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "\$HOME/miniconda_tmp/miniconda_installer.sh"
    bash "\$HOME/miniconda_tmp/miniconda_installer.sh" -b -u -p "\$CONDA_DIR"
    rm -rf "\$HOME/miniconda_tmp" # Clean up installer and temp dir

    # Initialize conda for bash and zsh (if .zshrc exists)
    eval "\$("\$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
    "\$CONDA_DIR/bin/conda" init bash
    
    if [ -f "\$HOME/.zshrc" ]; then
        "\$CONDA_DIR/bin/conda" init zsh
    fi
    
    # Ensure conda command is available for the next step
    PATH="\$CONDA_DIR/bin:\$PATH"
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
    
    if ! id "$username" &>/dev/null; then
        sudo adduser --disabled-password --gecos "" "$username"
        log_info "User '$username' created."
        
        echo "Please set a password for user '$username':"
        sudo passwd "$username"
        sudo chage -d 0 "$username"
    else
        log_info "User '$username' already exists."
    fi
    
    sudo usermod -aG sudo "$username"
    if [ "$INSTALL_DOCKER" = true ]; then
        # Docker group might not exist yet if Docker isn't installed.
        # Docker installation section will re-ensure this.
        if getent group docker > /dev/null; then
            sudo usermod -aG docker "$username"
        else
            log_info "Docker group not yet created. User $username will be added during Docker install."
        fi
    fi
    
    sudo tee "/etc/sudoers.d/${username}_restricted" > /dev/null << EOF
# Define command aliases for user management restrictions
Cmnd_Alias USERMOD_CMDS = /usr/sbin/adduser, /usr/sbin/useradd, /usr/sbin/userdel, /usr/sbin/usermod, /usr/sbin/deluser
Cmnd_Alias USER_PASSWD_CMDS = /usr/bin/passwd [A-Za-z0-9_]*, !/usr/bin/passwd $username, /usr/sbin/chpasswd, /usr/sbin/newusers

# Allow $username to run most commands with sudo, but restrict user management
$username ALL=(ALL:ALL) ALL, !USERMOD_CMDS, !USER_PASSWD_CMDS

# Allow $username to change their own password with 'sudo passwd $username' without password prompt (optional, 'passwd' alone works too)
# $username ALL=(root) NOPASSWD: /usr/bin/passwd $username
EOF
# The NOPASSWD line for self-passwd is often not needed as `passwd` works without sudo for oneself.
# Restricted `USER_PASSWD_CMDS` ensures `sudo passwd otheruser` is blocked.
    
    sudo chmod 440 "/etc/sudoers.d/${username}_restricted"
    
    if sudo visudo -c; then
        log_success "Sudoers file syntax is valid for ${username}_restricted."
    else
        log_error "Sudoers file syntax error for ${username}_restricted. Removing the configuration."
        sudo rm -f "/etc/sudoers.d/${username}_restricted"
        # exit 1 # Decided not to exit, but log error. Sudo restriction is bonus.
    fi
    
    log_success "User '$username' configured with restricted sudo privileges (cannot manage other users)."
}

install_amd_gpu_drivers() {
    log_info "Starting AMD GPU Driver (ROCm) installation..."

    # Check OS (specifically for Ubuntu 24.04 - Noble Numbat)
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$VERSION_CODENAME" != "noble" ]]; then
            log_error "AMD GPU ROCm installation in this script is tailored for Ubuntu 24.04 (noble). Detected: $VERSION_CODENAME. Skipping."
            return 1
        fi
    else
        log_error "Cannot determine OS version codename. Skipping AMD GPU ROCm installation."
        return 1
    fi

    log_info "Installing prerequisites for AMD GPU drivers..."
    sudo apt update
    sudo apt install -y python3-setuptools python3-wheel
    log_success "Prerequisites for AMD GPU drivers installed."

    log_info "Downloading AMD GPU installer script package: ${AMD_GPU_INSTALLER_FILENAME}..."
    wget --progress=bar:force -O "/tmp/${AMD_GPU_INSTALLER_FILENAME}" "${AMD_GPU_INSTALLER_FULL_URL}"
    if [ $? -ne 0 ]; then
        log_error "Failed to download AMD GPU installer from ${AMD_GPU_INSTALLER_FULL_URL}. Skipping."
        rm -f "/tmp/${AMD_GPU_INSTALLER_FILENAME}"
        return 1
    fi
    log_success "AMD GPU installer script package downloaded."

    log_info "Installing AMD GPU installer script package..."
    sudo apt install -y "/tmp/${AMD_GPU_INSTALLER_FILENAME}"
    rm "/tmp/${AMD_GPU_INSTALLER_FILENAME}" # Clean up downloaded .deb
    log_success "AMD GPU installer script package installed."

    log_info "Running amdgpu-install to install workstation drivers and ROCm..."
    log_warning "This step can take a significant amount of time (e.g., 15-45+ minutes) depending on your internet connection and system performance. Please be patient."
    # Refresh package lists again as amdgpu-install script might have added new repos
    sudo apt update 
    sudo amdgpu-install -y --usecase=workstation,rocm
    log_success "amdgpu-install process completed for workstation and ROCm."

    log_info "Adding users to 'render' and 'video' groups for GPU access..."
    for user_to_add_gpu_groups in "$ADMIN_USER" "$ADDITIONAL_USER"; do
        if id "$user_to_add_gpu_groups" &>/dev/null; then
            sudo usermod -aG render "$user_to_add_gpu_groups"
            sudo usermod -aG video "$user_to_add_gpu_groups"
            log_info "User $user_to_add_gpu_groups added to 'render' and 'video' groups."
        else
            log_warning "User $user_to_add_gpu_groups not found. Skipping 'render'/'video' group addition for this user."
        fi
    done
    log_success "Users configured for 'render' and 'video' groups."

    log_warning "A SYSTEM REBOOT IS REQUIRED to complete AMD GPU driver installation and apply group changes."
    log_info "After reboot, you can verify the installation:"
    log_info "1. Check user groups: groups (ensure 'render' and 'video' are listed)"
    log_info "2. Check DKMS status: dkms status (look for 'amdgpu' module)"
    log_info "3. Check ROCm agent info: rocminfo"
    log_info "4. Check OpenCL info: clinfo"
    log_info "   (If 'rocminfo' or 'clinfo' commands are not found, ensure ROCm packages like 'rocm-core' and OpenCL ICD loaders are correctly installed and in PATH.)"

    log_success "AMD GPU Driver (ROCm) installation script finished."
}

# --- Initial Setup & Sanity Checks ---
print_banner
check_os_compatibility

log_info "Starting NexusCore Advanced Server Setup v2.1 for users: $ADMIN_USER and $ADDITIONAL_USER"
log_info "This script should be run by the user who will be '$ADMIN_USER'."
if [ "$(id -u)" = "0" ]; then
   log_error "This script should not be run as root. Run as a sudo-enabled user (preferably as '$ADMIN_USER')."
   exit 1
fi

if [ "$USER" != "$ADMIN_USER" ]; then
    log_warning "You are running this script as user '$USER', but ADMIN_USER is set to '$ADMIN_USER'."
    log_warning "NVM and Miniconda for the current user ('$USER') will be set up. '$ADMIN_USER' will not get this specific setup unless '$USER' is '$ADMIN_USER'."
    log_warning "Consider running this script as '$ADMIN_USER', or manually run 'setup_user_environment \"$ADMIN_USER\"' later if needed."
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi


if ! sudo -n true 2>/dev/null; then
    log_warning "Sudo access for $USER requires a password. You may be prompted multiple times."
fi

# Create the additional user early
if [ -n "$ADDITIONAL_USER" ]; then
    create_restricted_sudo_user "$ADDITIONAL_USER"
else
    log_info "ADDITIONAL_USER variable is empty. Skipping creation of additional user."
fi


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
    sudo ufw allow 80/tcp  # For web servers
    sudo ufw allow 443/tcp # For HTTPS
    # Add any other essential ports here before enabling
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
    log_success "Python 3, pip, venv, and dev headers are set up."
fi

# Java
if [ "$INSTALL_JAVA" = true ]; then
    log_info "Installing OpenJDK $JAVA_VERSION..."
    sudo apt install -y "openjdk-${JAVA_VERSION}-jdk" "openjdk-${JAVA_VERSION}-jre"
    log_success "OpenJDK $JAVA_VERSION (JDK & JRE) installed."
fi

# C/C++
if [ "$INSTALL_CPP" = true ]; then
    log_info "Ensuring C/C++ toolchain (gcc, g++, gdb, clang, valgrind) is installed..."
    sudo apt install -y gcc g++ gdb clang valgrind
    log_success "C/C++ toolchain installed."
fi

# Node.js (via NVM) - for current user (assumed to be ADMIN_USER)
if [ "$INSTALL_NODEJS" = true ]; then
    log_info "Installing Node.js via NVM for current user ($USER)..."
    export NVM_DIR="$HOME/.nvm"
    if [ ! -d "$NVM_DIR" ]; then
        mkdir -p "$NVM_DIR"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        # Source NVM for the current script session
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        if command -v nvm &> /dev/null; then
            set +u # NVM scripts might use unbound variables
            nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
            set -u
            log_success "Node.js LTS installed via NVM and activated for this session."
        else 
            log_error "NVM installation failed for current user."; 
        fi
    else
        log_info "NVM already installed for current user. Sourcing and ensuring LTS Node.js."
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
        set +u # NVM scripts might use unbound variables
        if ! nvm ls 'lts/*' &> /dev/null || ! (nvm current | grep -qE 'lts|node'); then # Check if LTS is installed or if any version is active
            nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
        elif ! (nvm current | grep -q 'lts'); then # If a node is active but not LTS
            nvm use 'lts/*' && nvm alias default 'lts/*'
        fi
        set -u
        log_success "NVM sourced, Node.js LTS configured and activated for this session."
    fi
    
    # Add NVM to shell configuration files for current user
    if ! grep -q 'export NVM_DIR="$HOME/.nvm"' ~/.bashrc 2>/dev/null; then
        echo '' >> ~/.bashrc
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> ~/.bashrc
        log_info "NVM configuration added to .bashrc for current user."
    fi
    
    if [ -f "$HOME/.zshrc" ] && ! grep -q 'export NVM_DIR="$HOME/.nvm"' ~/.zshrc 2>/dev/null; then
        echo '' >> ~/.zshrc
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.zshrc
        log_info "NVM configuration added to .zshrc for current user."
    fi
    
    # Install global npm packages (ensure NVM is sourced for this)
    if command -v npm &> /dev/null; then
        log_info "Installing global npm packages: yarn, typescript, ts-node, nodemon, pm2..."
        # Source NVM again just in case, within a subshell to avoid polluting main script's NVM state if already complex
        (
          [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
          set +u # npm/global packages might have issues with set -u
          npm install -g yarn typescript ts-node nodemon pm2
          set -u
        )
        log_success "Installed global npm packages: yarn, typescript, ts-node, nodemon, pm2."
    else
        log_warning "npm command not found after NVM setup. Skipping global npm packages."
    fi
fi

# --- Install AMD GPU Drivers (Optional) ---
if [ "$INSTALL_AMD_GPU_DRIVERS" = true ]; then
    install_amd_gpu_drivers
fi

# Docker & Docker Compose
if [ "$INSTALL_DOCKER" = true ]; then
    log_info "Installing Docker and Docker Compose..."
    # Add Docker's official GPG key & Set up repository
    sudo install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then # Check if key already exists
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then # Check if repo source already exists
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update # Update apt package index again after adding new repo
    fi
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add users to docker group
    if ! getent group docker > /dev/null; then
        sudo groupadd docker
        log_info "Created docker group."
    fi
    for user_to_add_docker_group in "$ADMIN_USER" "$ADDITIONAL_USER"; do
        if [ -n "$user_to_add_docker_group" ] && id "$user_to_add_docker_group" &>/dev/null; then
            if ! groups "$user_to_add_docker_group" | grep -q '\bdocker\b'; then
                sudo usermod -aG docker "$user_to_add_docker_group"
                log_info "User $user_to_add_docker_group added to docker group."
            else
                log_info "User $user_to_add_docker_group is already a member of the docker group."
            fi
        elif [ -n "$user_to_add_docker_group" ]; then
             log_warning "User $user_to_add_docker_group not found, cannot add to docker group."
        fi
    done
    # Also add current user if not one of the above
    if [[ "$USER" != "$ADMIN_USER" && ("$ADDITIONAL_USER" = "" || "$USER" != "$ADDITIONAL_USER") ]]; then
        if ! groups "$USER" | grep -q '\bdocker\b'; then
            sudo usermod -aG docker "$USER"
            log_info "Current user $USER added to docker group."
        fi
    fi


    sudo systemctl enable --now docker
    log_success "Docker and Docker Compose installed and service enabled/started."
fi

# Miniconda - for current user (assumed to be ADMIN_USER)
if [ "$INSTALL_MINICONDA" = true ]; then
    log_info "Installing Miniconda for current user ($USER)..."
    CONDA_DIR="$HOME/miniconda3"
    if [ ! -d "$CONDA_DIR/bin" ]; then
        mkdir -p "$HOME/miniconda_tmp"
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$HOME/miniconda_tmp/miniconda_installer.sh"
        bash "$HOME/miniconda_tmp/miniconda_installer.sh" -b -u -p "$CONDA_DIR"
        rm -rf "$HOME/miniconda_tmp" # Clean up installer and temp dir
        
        # Initialize conda for current shell session and for bash/zsh config files
        eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
        "$CONDA_DIR/bin/conda" init bash
        if [ -f "$HOME/.zshrc" ]; then
            "$CONDA_DIR/bin/conda" init zsh
        fi
        log_success "Miniconda installed to $CONDA_DIR and shell initialised."
    else
        log_info "Miniconda already installed for current user. Sourcing for current session."
        eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
        log_success "Miniconda sourced for this session."
    fi
    
    # Ensure conda command is available before configuring
    if command -v conda &> /dev/null; then
        conda config --set auto_activate_base false
        log_success "Configured conda to not auto-activate base environment for current user."
    else
        log_warning "Conda command not found. Could not set auto_activate_base for current user."
    fi
fi

# --- Monitoring Tools ---
if [ "$INSTALL_MONITORING_TOOLS" = true ]; then
    log_info "Installing additional monitoring tools (glances, bpytop, radeontop, lm-sensors)..."
    # htop, btop, nvtop already installed with essentials
    sudo apt install -y glances bpytop radeontop lm-sensors
    log_success "Additional monitoring tools installed."
fi

# --- Install Cloudflared ---
if [ "$INSTALL_CLOUDFLARED" = true ]; then
    log_info "Installing cloudflared..."
    if ! command -v cloudflared &> /dev/null; then
        ARCH=$(dpkg --print-architecture)
        # Ensure the URL is general or point to a specific version if needed.
        # This fetches the latest, which is usually fine.
        CLOUDFLARED_LATEST_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
        wget -O /tmp/cloudflared.deb "${CLOUDFLARED_LATEST_URL}"
        sudo dpkg -i /tmp/cloudflared.deb
        sudo apt-get install -f -y # Install dependencies if any
        rm /tmp/cloudflared.deb
        if command -v cloudflared &> /dev/null; then
            log_success "cloudflared $(cloudflared --version) installed."
        else
            log_error "cloudflared installation failed."
        fi
    else
        log_info "cloudflared already installed. Version: $(cloudflared --version)"
    fi
fi

# --- Security Improvements ---
log_info "Installing and configuring additional security tools..."
# Install fail2ban for SSH protection
log_info "Installing fail2ban for SSH protection..."
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban

# Create a basic fail2ban config for SSH if it doesn't exist
JAIL_LOCAL_CONF="/etc/fail2ban/jail.local" # Use jail.local for overrides
if [ ! -f "$JAIL_LOCAL_CONF" ] || ! grep -q "\[sshd\]" "$JAIL_LOCAL_CONF"; then
    log_info "Creating/updating fail2ban jail.local configuration for SSH..."
    sudo bash -c "cat >> $JAIL_LOCAL_CONF" << EOF

[sshd]
enabled = true
port = ssh
# filter = sshd # Default filter, usually fine
logpath = /var/log/auth.log
maxretry = 5
bantime = 1h   # Ban for 1 hour
findtime = 10m # Within 10 minutes
EOF
    sudo systemctl restart fail2ban
    log_success "fail2ban configured to protect SSH via jail.local."
else
    log_info "fail2ban sshd configuration seems to exist in $JAIL_LOCAL_CONF or is managed elsewhere."
fi


# --- Set up development environments for additional user ---
if [ -n "$ADDITIONAL_USER" ] && id "$ADDITIONAL_USER" &>/dev/null; then
    setup_user_environment "$ADDITIONAL_USER"
else
    log_info "Skipping environment setup for ADDITIONAL_USER (not defined or does not exist)."
fi

# --- Create System Logs Directory for current user ---
log_info "Creating system logs directory for current user ($USER)..."
LOGS_DIR="$HOME/system_logs"
mkdir -p "$LOGS_DIR"
date > "$LOGS_DIR/setup_complete_date.log"
uname -a > "$LOGS_DIR/system_info.log"
lscpu > "$LOGS_DIR/cpu_info.log"
free -h > "$LOGS_DIR/memory_info.log"
df -h > "$LOGS_DIR/disk_info.log"
ip addr > "$LOGS_DIR/network_info.log"
if command -v docker &> /dev/null && docker ps -q &>/dev/null ; then # Check if docker is running
    docker info > "$LOGS_DIR/docker_info.log" 2>/dev/null || echo "Docker not running or permission issue to get info." > "$LOGS_DIR/docker_info.log"
else
    echo "Docker not installed or not running." > "$LOGS_DIR/docker_info.log"
fi
log_success "System logs directory created at $LOGS_DIR for user $USER"

# --- Final Steps & System Information ---
log_success "NexusCore Advanced Setup script v2.1 completed!"

log_info "-------------------- SYSTEM INFORMATION --------------------"
echo -e "\033[1;32mHostname:\033[0m $(hostname)"
SERVER_IPS=$(hostname -I)
echo -e "\033[1;32mServer IP Addresses:\033[0m $SERVER_IPS"
echo -e "\033[1;33mTo SSH into this server (from another machine), use one of these IPs:\033[0m"
for ip_addr in $SERVER_IPS; do
    if [ "$USER" == "$ADMIN_USER" ]; then # If script runner is ADMIN_USER
        echo "ssh $ADMIN_USER@$ip_addr"
    else # If script runner is different, provide for both
        echo "ssh $ADMIN_USER@$ip_addr  (Primary Admin User)"
        echo "ssh $USER@$ip_addr (User who ran this script)"
    fi
    if [ -n "$ADDITIONAL_USER" ] && id "$ADDITIONAL_USER" &>/dev/null; then
        echo "ssh $ADDITIONAL_USER@$ip_addr"
    fi
done
echo ""

if command -v neofetch &> /dev/null; then
    log_info "System Summary (neofetch):"
    neofetch
else
    log_info "OS Version:"; lsb_release -a
    log_info "Kernel:"; uname -a
fi
echo ""

log_info "CPU Information:"; lscpu | grep -E 'Model name|Socket|Core|Thread|CPU MHz|Virtualization'
echo ""
log_info "RAM Usage:"; free -h
echo ""
log_info "Disk Usage:"; df -hT /; 
echo ""

log_info "-------------------- USER INFORMATION --------------------"
echo -e "\033[1;32mAdmin User (intended):\033[0m $ADMIN_USER"
echo -e "\033[1;32mUser who ran script:\033[0m $USER"
if [ -n "$ADDITIONAL_USER" ] && id "$ADDITIONAL_USER" &>/dev/null; then
    echo -e "\033[1;32mAdditional User:\033[0m $ADDITIONAL_USER (restricted sudo - cannot manage other users)"
fi
echo ""

log_info "-------------------- IMPORTANT NEXT STEPS --------------------"
NEXT_STEP_COUNT=1
if [ -n "$ADDITIONAL_USER" ] && id "$ADDITIONAL_USER" &>/dev/null; then
    log_info "${NEXT_STEP_COUNT}. User '$ADDITIONAL_USER' Setup:"
    echo -e "   \033[1;36mSwitch to user:\033[0m sudo su - $ADDITIONAL_USER"
    echo -e "   \033[1;36mLogin as user:\033[0m ssh $ADDITIONAL_USER@<server-ip>"
    echo -e "   \033[1;36mPassword change:\033[0m The user will be prompted to change password on first login."
    echo ""
    ((NEXT_STEP_COUNT++))
fi

log_info "${NEXT_STEP_COUNT}. Development Environment Activation:"
echo -e "   \033[1;36mFor all configured users (including $USER):\033[0m You may need to log out and log back in or run 'source ~/.bashrc' (or ~/.zshrc)."
echo -e "   \033[1;36mTest Node.js (NVM):\033[0m node -v && npm -v"
echo -e "   \033[1;36mTest Conda:\033[0m conda --version (after sourcing shell config or new login)"
echo ""
((NEXT_STEP_COUNT++))

if [ "$INSTALL_DOCKER" = true ]; then
    log_info "${NEXT_STEP_COUNT}. Docker Permissions:"
    echo -e "   \033[1;36mUsers ($USER, $ADMIN_USER, $ADDITIONAL_USER where applicable) added to 'docker' group.\033[0m"
    echo -e "   \033[1;36mTo apply group changes:\033[0m"
    echo -e "     \033[1;36mOption 1:\033[0m Log out and log back in."
    echo -e "     \033[1;36mOption 2 (temporary for current session):\033[0m newgrp docker"
    echo -e "   \033[1;36mTest Docker (after applying group changes):\033[0m docker run hello-world"
    echo ""
    ((NEXT_STEP_COUNT++))
fi

if [ -n "$ADDITIONAL_USER" ] && id "$ADDITIONAL_USER" &>/dev/null; then
    log_info "${NEXT_STEP_COUNT}. User '$ADDITIONAL_USER' Sudo Restrictions:"
    echo -e "   \033[1;33m'$ADDITIONAL_USER' cannot use sudo for:\033[0m adduser, userdel, usermod, passwd (for other users), etc."
    echo -e "   \033[1;32mCan do most other operations with sudo.\033[0m"
    echo -e "   \033[1;36mTest (as $ADDITIONAL_USER):\033[0m sudo adduser testuser (should be denied)"
    echo ""
    ((NEXT_STEP_COUNT++))
fi

log_info "${NEXT_STEP_COUNT}. Monitoring Tools:"
echo -e "   \033[1;36mHardware Sensors (if not already done):\033[0m sudo sensors-detect (follow prompts)"
echo -e "   \033[1;36mView sensor data:\033[0m sensors"
echo -e "   \033[1;36mUseful commands:\033[0m htop, btop, glances, nvtop (for NVIDIA), radeontop (for AMD)"
echo ""
((NEXT_STEP_COUNT++))

log_info "${NEXT_STEP_COUNT}. Security and Access:"
echo -e "   \033[1;36mFail2ban Status:\033[0m sudo fail2ban-client status sshd"
echo -e "   \033[1;36mSSH Keys:\033[0m For passwordless login, generate SSH keys on your client and add public key to server's ~/.ssh/authorized_keys for each user."
echo -e "     \033[1;36m(Client):\033[0m ssh-keygen -t ed25519"
echo -e "     \033[1;36m(Client):\033[0m ssh-copy-id user@server-ip"
echo -e "   \033[1;36mFirewall Status:\033[0m sudo ufw status verbose"
echo ""
((NEXT_STEP_COUNT++))

if [ "$INSTALL_CLOUDFLARED" = true ] && command -v cloudflared &>/dev/null; then
    log_info "${NEXT_STEP_COUNT}. Cloudflare Tunnel (cloudflared):"
    echo -e "   \033[1;36mCloudflared is installed. To use it:\033[0m"
    echo -e "     \033[1;36mLogin:\033[0m cloudflared tunnel login"
    echo -e "     \033[1;36mCreate a tunnel:\033[0m cloudflared tunnel create <your-tunnel-name>"
    echo -e "     \033[1;36mFollow Cloudflare's documentation for further setup.\033[0m"
    echo ""
    ((NEXT_STEP_COUNT++))
fi

if [ "$INSTALL_AMD_GPU_DRIVERS" = true ]; then
    log_info "${NEXT_STEP_COUNT}. AMD GPU Drivers (ROCm):"
    echo -e "   \033[1;33mIMPORTANT:\033[0m A system reboot is REQUIRED for AMD drivers to function correctly and for group changes (render, video) to take full effect."
    echo -e "   \033[1;36mAfter reboot, verify installation:\033[0m"
    echo -e "     - \033[1;36mCheck groups:\033[0m groups (ensure you are in 'render' and 'video')"
    echo -e "     - \033[1;36mDKMS status:\033[0m dkms status (look for 'amdgpu' being 'installed')"
    echo -e "     - \033[1;36mROCm info:\033[0m rocminfo"
    echo -e "     - \033[1;36mOpenCL info:\033[0m clinfo"
    echo -e "     (If 'rocminfo' or 'clinfo' not found, check ROCm installation logs and ensure required packages like 'rocm-core' are installed and PATH is correct.)"
    echo ""
    ((NEXT_STEP_COUNT++))
fi


log_info "NexusCore Setup Process Completed for user $USER. Primary admin user is '$ADMIN_USER'."
if [ -n "$ADDITIONAL_USER" ] && id "$ADDITIONAL_USER" &>/dev/null; then
    echo -e "\033[1;35m--- Users '$USER', '$ADMIN_USER' (if different), and '$ADDITIONAL_USER' are configured! ---\033[0m"
else
    echo -e "\033[1;35m--- User '$USER' (and '$ADMIN_USER' if different) is configured! ---\033[0m"
fi
echo

REBOOT_PROMPT_MESSAGE="Reboot now to apply all changes? (y/N): "
if [ "$INSTALL_AMD_GPU_DRIVERS" = true ] || [ "$INSTALL_DOCKER" = true ]; then
    REBOOT_PROMPT_MESSAGE="Reboot now to apply all changes (RECOMMENDED for Docker group changes and/or AMD GPU drivers)? (y/N): "
fi
read -p "$REBOOT_PROMPT_MESSAGE" -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Rebooting system..."
    sudo reboot
fi