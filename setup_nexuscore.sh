# NexusCore Setup Script v2.1 for Ubuntu 24.04.2 LTS

# Exit on any error, treat unset variables as an error, and ensure pipelines fail on error
set -euo pipefail

# --- Configuration ---
# Change these variables to match your preferences
ADMIN_USER="djdiptayan"
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

# --- Initial Setup & Sanity Checks ---
print_banner
check_os_compatibility

log_info "Starting NexusCore Advanced Server Setup v2.1 for user: $ADMIN_USER"
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

# --- Install Basic Utilities & Build Tools ---
log_info "Installing essential packages, development tools, and neofetch..."
sudo apt install -y \
    git curl wget build-essential software-properties-common apt-transport-https \
    ca-certificates gnupg lsb-release unzip zip make cmake pkg-config autoconf automake \
    libtool gettext tree htop iotop iftop ncdu gnupg2 pass neofetch
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

# Node.js (via NVM)
if [ "$INSTALL_NODEJS" = true ]; then
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
            # Temporarily disable unset variable checking for NVM operations
            set +u
            nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
            set -u  # Re-enable strict mode
            log_success "Node.js LTS installed via NVM and activated for this session."
        else log_error "NVM installation failed."; fi
    else
        log_info "NVM already installed. Sourcing and ensuring LTS Node.js."
        # shellcheck source=/dev/null
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
        # Temporarily disable unset variable checking for NVM operations
        set +u
        if ! nvm ls 'lts/*' &> /dev/null || ! (nvm current | grep -q 'lts'); then
            nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
        fi
        set -u  # Re-enable strict mode
        
        log_success "NVM sourced, Node.js LTS configured and activated for this session."
    fi
    
    # Add to both bashrc and zshrc if it exists (only if not already present)
    if ! grep -q 'export NVM_DIR="$HOME/.nvm"' ~/.bashrc 2>/dev/null; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> ~/.bashrc
        log_info "NVM configuration added to .bashrc"
    else
        log_info "NVM configuration already exists in .bashrc"
    fi
    
    if [ -f "$HOME/.zshrc" ] && ! grep -q 'export NVM_DIR="$HOME/.nvm"' ~/.zshrc 2>/dev/null; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> ~/.zshrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> ~/.zshrc
        log_info "NVM configuration added to .zshrc"
    elif [ -f "$HOME/.zshrc" ]; then
        log_info "NVM configuration already exists in .zshrc"
    fi
    
    # Install some useful global npm packages
    if command -v npm &> /dev/null; then
        # Temporarily disable unset variable checking for npm operations too
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
    if ! groups "$ADMIN_USER" | grep -q '\bdocker\b'; then
        sudo usermod -aG docker "$ADMIN_USER"
        log_info "User $ADMIN_USER added to docker group. CRITICAL: Re-login or use 'newgrp docker' in a new shell for this to take full effect for your interactive session."
    else
        log_info "User $ADMIN_USER is already a member of the docker group."
    fi
    sudo systemctl enable --now docker
    log_success "Docker and Docker Compose installed and service enabled/started."
fi

# Miniconda
if [ "$INSTALL_MINICONDA" = true ]; then
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
        
        # Also initialize for zsh if it exists
        if [ -f "$HOME/.zshrc" ]; then
            "$CONDA_DIR/bin/conda" init zsh
            log_info "Miniconda initialized for zsh shell."
        fi
        
        log_success "Miniconda installed to $CONDA_DIR and activated for this session. Bashrc updated."
    else
        log_info "Miniconda already installed. Sourcing for current session."
        # shellcheck source=/dev/null
        eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
        log_success "Miniconda sourced for this session."
    fi
    
    # Some conda configuration improvements
    conda config --set auto_activate_base false
    log_success "Configured conda to not auto-activate base environment."
fi

# --- Monitoring Tools ---
if [ "$INSTALL_MONITORING_TOOLS" = true ]; then
    log_info "Installing monitoring tools (htop, glances, bpytop, radeontop, lm-sensors)..."
    sudo apt install -y htop glances bpytop radeontop lm-sensors
    log_success "Monitoring tools installed."
    log_info "For lm-sensors: run 'sudo sensors-detect' (interactive) then 'sensors' to view."
fi

# --- Install Cloudflared ---
if [ "$INSTALL_CLOUDFLARED" = true ]; then
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

# --- Create System Logs Directory ---
log_info "Creating system logs directory..."
LOGS_DIR="$HOME/system_logs"
mkdir -p "$LOGS_DIR"
# Create initial log files
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
log_info "1. NVM & Conda: Activated for this script's session. Your ~/.bashrc has been updated for future logins."
echo -e "   \033[1;36mCommand:\033[0m source ~/.bashrc"
echo ""

log_info "2. Docker Permissions: User $ADMIN_USER was added to the 'docker' group. For this change to apply:"
echo -e "   \033[1;36mOption 1:\033[0m Log out and log back in"
echo -e "   \033[1;36mOption 2:\033[0m newgrp docker"
echo -e "   \033[1;36mTest Docker:\033[0m docker run hello-world"
echo ""

log_info "3. Configure and use hardware monitoring tools:"
echo -e "   \033[1;36mSensors setup:\033[0m sudo sensors-detect  # Follow the prompts"
echo -e "   \033[1;36mView sensors:\033[0m sensors"
echo -e "   \033[1;36mMonitor CPU:\033[0m htop"
echo -e "   \033[1;36mSystem monitor:\033[0m glances"
echo -e "   \033[1;36mInteractive monitor:\033[0m bpytop"
echo -e "   \033[1;36mDisk I/O monitor:\033[0m sudo iotop"
echo -e "   \033[1;36mNetwork monitor:\033[0m sudo iftop"
echo -e "   \033[1;36mDisk usage analyzer:\033[0m ncdu"
echo ""

log_info "4. Security tools and configurations:"
echo -e "   \033[1;36mCheck fail2ban status:\033[0m sudo fail2ban-client status"
echo -e "   \033[1;36mGenerate SSH key:\033[0m ssh-keygen -t ed25519 -C \"your_email@example.com\""
echo -e "   \033[1;36mCheck firewall status:\033[0m sudo ufw status verbose"
echo -e "   \033[1;36mView latest auth logs:\033[0m sudo tail -f /var/log/auth.log"
echo ""

log_info "5. Set up Cloudflare Tunnel:"
echo -e "   \033[1;36mLogin to Cloudflare:\033[0m cloudflared tunnel login"
echo -e "   \033[1;36mCreate tunnel:\033[0m cloudflared tunnel create <tunnel-name>"
echo -e "   \033[1;36mConfigure tunnel:\033[0m nano ~/.cloudflared/config.yml"
echo -e "   \033[1;36mStart tunnel:\033[0m cloudflared tunnel run <tunnel-name>"
echo ""

log_info "6. User management:"
echo -e "   \033[1;36mAdd new user:\033[0m sudo adduser <username>"
echo -e "   \033[1;36mGrant sudo access:\033[0m sudo usermod -aG sudo <username>"
echo -e "   \033[1;36mView users list:\033[0m cut -d: -f1 /etc/passwd"
echo ""

log_info "7. Development environments:"
echo -e "   \033[1;36mNode.js version:\033[0m node -v"
echo -e "   \033[1;36mPython version:\033[0m python3 -V"
echo -e "   \033[1;36mJava version:\033[0m java -version"
echo -e "   \033[1;36mCreate Python venv:\033[0m python3 -m venv /path/to/new/venv"
echo -e "   \033[1;36mCreate conda env:\033[0m conda create -n env_name python=3.10"
echo ""

log_info "8. System logs directory:"
echo -e "   \033[1;36mLocation:\033[0m $LOGS_DIR"
echo -e "   \033[1;36mView logs:\033[0m ls -la $LOGS_DIR"
echo ""

echo -e "\n\033[1;35m--- Review the 'IMPORTANT NEXT STEPS' above carefully! --- \033[0m"
echo -e "\n\033[1;32m--- Thank you for using NexusCore! ---\033[0m"
