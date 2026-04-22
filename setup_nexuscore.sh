# NexusCore Setup Script v3.3 — Multi-Distribution Linux Support
# Supported: Ubuntu, Pop!_OS, Zorin OS (Debian-based) and Fedora (RPM-based)
# Resilient setup with interactive prompts for root or sudo-enabled users
# Components are isolated — a failure in one does not stop the rest

# treat unset variables as an error, and ensure pipelines fail on error.
set -uo pipefail

# --- Configuration (defaults, overridden by interactive prompts) ---
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    ADMIN_USER="$SUDO_USER"
else
    ADMIN_USER="$USER"
fi
JAVA_VERSION=""   # Auto-detected: latest LTS from package manager
GO_VERSION=""     # Auto-detected: latest stable from go.dev
INSTALL_DOCKER=false
INSTALL_PYTHON=false
INSTALL_MINICONDA=false
INSTALL_JAVA=false
INSTALL_GO=false
INSTALL_CPP=false
INSTALL_NODEJS=false
INSTALL_CLOUDFLARED=false
INSTALL_MONITORING_TOOLS=false
INSTALL_NGINX=false
SETUP_UFW=false
SETUP_SWAP=false
SWAP_SIZE="2G"
SETUP_TIMEZONE=false
SETUP_HOSTNAME=false
NEW_HOSTNAME=""
SETUP_UNATTENDED_UPGRADES=false
CONFIGURE_SSH=false
ENABLE_PASSWORD_AUTH=true

# --- Distribution Detection ---
DISTRO_FAMILY=""   # "debian" or "fedora"
DISTRO_ID=""       # e.g., "ubuntu", "pop", "zorin", "fedora"
DISTRO_VERSION=""  # e.g., "24.04", "22.04", "40"
RUNNING_AS_ROOT=false
HAS_NATIVE_SUDO=false

if [ "$(id -u)" -eq 0 ]; then
    RUNNING_AS_ROOT=true
fi

if command -v sudo >/dev/null 2>&1; then
    HAS_NATIVE_SUDO=true
fi

# Root-compatible sudo wrapper:
# - Non-root: delegate to native sudo
# - Root: run commands directly, including "sudo -u user" calls used by this script
sudo() {
    if [ "$RUNNING_AS_ROOT" = true ]; then
        if [ "${1:-}" = "-u" ]; then
            if [ -z "${2:-}" ]; then
                log_error "Invalid sudo usage: '-u' requires a target user."
                return 1
            fi
            shift 2
        fi
        "$@"
    else
        command sudo "$@"
    fi
}

# --- Cleanup Handler ---
declare -a CLEANUP_ACTIONS_ON_FAILURE # Stores commands or function calls for cleanup
SCRIPT_SUCCESSFUL=false # Flag to indicate if the script completed without error

cleanup_on_error() {
    local err_lineno="$1"
    local err_command="$2"
    
    if [ "$SCRIPT_SUCCESSFUL" = true ]; then
        log_info "Script finished successfully, no error cleanup needed."
        return 0 # Do nothing if script was successful
    fi

    log_error "An error occurred on or near line $err_lineno, command: '$err_command'. Initiating cleanup..."
    # Turn off exit on error for cleanup itself, but errors in cleanup should be noted
    set +e

    if [ ${#CLEANUP_ACTIONS_ON_FAILURE[@]} -eq 0 ]; then
        log_warning "No cleanup actions registered."
    else
        log_info "Executing cleanup actions in reverse order..."
        for ((i=${#CLEANUP_ACTIONS_ON_FAILURE[@]}-1; i>=0; i--)); do
            local action="${CLEANUP_ACTIONS_ON_FAILURE[i]}"
            log_warning "Attempting cleanup: $action"
            eval "$action" # Using eval to execute the command string
            if [ $? -ne 0 ]; then
                log_error "Cleanup action FAILED: $action"
            else
                log_success "Cleanup action SUCCEEDED: $action"
            fi
        done
    fi

    log_error "Cleanup process finished. The system might be in an inconsistent state due to the initial error."
}
trap 'cleanup_on_error "$LINENO" "$BASH_COMMAND"' ERR

add_cleanup_action_on_failure() {
    CLEANUP_ACTIONS_ON_FAILURE+=("$1")
}

# --- Component Tracking ---
declare -a SUCCEEDED_COMPONENTS=()
declare -a FAILED_COMPONENTS=()
declare -a SKIPPED_COMPONENTS=()

# Run an optional component in isolation. If it fails, log the error and continue.
# Usage: run_component "Component Name" component_function_or_commands
run_component() {
    local name="$1"
    shift
    log_info "────────────────────────────────────────"
    log_info "Setting up: $name"
    log_info "────────────────────────────────────────"
    # Run in a subshell so set -e failures don't kill the parent
    if ( set -e; "$@" ); then
        log_success "$name — done."
        SUCCEEDED_COMPONENTS+=("$name")
    else
        log_error "$name — FAILED. Continuing with remaining components..."
        FAILED_COMPONENTS+=("$name")
    fi
}

# Retry wrapper for apt operations (handles dpkg lock contention)
apt_retry() {
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if sudo apt-get "$@"; then
            return 0
        fi
        log_warning "apt command failed (attempt $attempt/$max_attempts). Retrying in 10 seconds..."
        sleep 10
        ((attempt++))
    done
    log_error "apt command failed after $max_attempts attempts."
    return 1
}

# Retry wrapper for dnf operations
dnf_retry() {
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if sudo dnf "$@"; then
            return 0
        fi
        log_warning "dnf command failed (attempt $attempt/$max_attempts). Retrying in 10 seconds..."
        sleep 10
        ((attempt++))
    done
    log_error "dnf command failed after $max_attempts attempts."
    return 1
}

# --- Distribution Detection & Package Manager Abstraction ---
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
        case "$ID" in
            ubuntu|pop|zorin)
                DISTRO_FAMILY="debian"
                ;;
            fedora)
                DISTRO_FAMILY="fedora"
                ;;
            *)
                # Check ID_LIKE for derivatives
                if [[ "${ID_LIKE:-}" == *"ubuntu"* ]] || [[ "${ID_LIKE:-}" == *"debian"* ]]; then
                    DISTRO_FAMILY="debian"
                elif [[ "${ID_LIKE:-}" == *"fedora"* ]]; then
                    DISTRO_FAMILY="fedora"
                else
                    log_error "Unsupported distribution: $ID"
                    return 1
                fi
                ;;
        esac
    else
        log_error "Unable to determine OS. /etc/os-release not found."
        return 1
    fi
    log_info "Detected: $DISTRO_ID $DISTRO_VERSION (family: $DISTRO_FAMILY)"
    return 0
}

get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armhf" ;;
        *)       echo "$arch" ;;
    esac
}

pkg_update() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        apt_retry update
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        # dnf check-update returns 100 if updates are available, 0 if none
        sudo dnf check-update || true
    fi
}

pkg_upgrade() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        apt_retry -y upgrade
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        dnf_retry upgrade -y
    fi
}

pkg_install() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        apt_retry -y install "$@"
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        dnf_retry install -y "$@"
    fi
}

install_base_packages() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        apt_retry -y install \
            git curl wget build-essential software-properties-common apt-transport-https \
            ca-certificates gnupg lsb-release unzip zip make cmake pkg-config autoconf automake \
            libtool gettext tree htop btop iotop iftop ncdu gnupg2 pass neofetch \
            tmux screen vim nano jq net-tools dnsutils rsync socat mtr-tiny nload \
            sysstat logrotate cron
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        dnf_retry groupinstall -y "Development Tools"
        dnf_retry install -y \
            git curl wget gcc gcc-c++ make cmake pkgconf autoconf automake \
            libtool gettext tree htop btop iotop iftop ncdu gnupg2 pass neofetch \
            tmux screen vim-enhanced nano jq net-tools bind-utils rsync socat mtr nload \
            sysstat logrotate cronie zip unzip ca-certificates
    fi
}

# --- Version Detection (auto-detect latest LTS/stable versions) ---

# Detect latest available Java LTS version from the package manager
# Java LTS versions: 8, 11, 17, 21, 25, ...
detect_java_lts_version() {
    local lts_versions=("25" "21" "17" "11" "8")
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        for v in "${lts_versions[@]}"; do
            if apt-cache show "openjdk-${v}-jdk" &>/dev/null; then
                echo "$v"
                return 0
            fi
        done
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        for v in "${lts_versions[@]}"; do
            if dnf list available "java-${v}-openjdk" &>/dev/null 2>&1; then
                echo "$v"
                return 0
            fi
        done
    fi
    echo "21"  # Fallback to latest known LTS
}

# Detect latest stable Go version from go.dev
detect_go_version() {
    local version
    # Try fetching from the official Go download API
    version=$(curl -fsSL --connect-timeout 5 'https://go.dev/dl/?mode=json' 2>/dev/null \
        | grep -oP '"version":\s*"go\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    # Fallback: parse the Go downloads page
    version=$(curl -fsSL --connect-timeout 5 'https://go.dev/VERSION?m=text' 2>/dev/null \
        | head -1 | sed 's/^go//')
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    echo "1.24.1"  # Fallback to a known stable version
}

# Resolve all auto-detected versions (called after package lists are updated)
resolve_tool_versions() {
    if [ -z "$JAVA_VERSION" ] && [ "$INSTALL_JAVA" = true ]; then
        log_info "Detecting latest Java LTS version..."
        JAVA_VERSION=$(detect_java_lts_version)
        log_info "Java LTS version resolved: $JAVA_VERSION"
    fi
    if [ -z "$GO_VERSION" ] && [ "$INSTALL_GO" = true ]; then
        log_info "Detecting latest Go stable version..."
        GO_VERSION=$(detect_go_version)
        log_info "Go version resolved: $GO_VERSION"
    fi
}

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
        # This will trigger ERR trap if set -e is active
        return 1 # Ensure it signals error
    fi
    return 0
}

print_banner() {
    echo -e "\033[1;35m"
    echo "███    ██ ███████ ██   ██ ██    ██ ███████  ██████  ██████  ██████  ███████ "
    echo "████   ██ ██       ██ ██  ██    ██ ██      ██      ██    ██ ██   ██ ██      "
    echo "██ ██  ██ █████     ███   ██    ██ ███████ ██      ██    ██ ██████  █████   "
    echo "██  ██ ██ ██       ██ ██  ██    ██      ██ ██      ██    ██ ██   ██ ██      "
    echo "██   ████ ███████ ██   ██  ██████  ███████  ██████  ██████  ██   ██ ███████ "
    echo -e "\033[0m"
    echo -e "\033[1;36mComplete Server Setup Script v3.3 — Multi-Distribution Linux Support\033[0m"
    echo
}

# --- Interactive Prompts ---
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local reply
    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n]: " -r reply
        [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]
    else
        read -p "$prompt [y/N]: " -r reply
        [[ "$reply" =~ ^[Yy]$ ]]
    fi
}

interactive_setup() {
    echo -e "\033[1;36m========================================\033[0m"
    echo -e "\033[1;36m  NexusCore Interactive Setup\033[0m"
    echo -e "\033[1;36m========================================\033[0m"
    echo
    echo -e "\033[1;33m--- Server Configuration ---\033[0m"
    echo

    if ask_yes_no "  Set a custom hostname for this server?"; then
        read -p "    Enter hostname: " -r NEW_HOSTNAME
        if [ -n "$NEW_HOSTNAME" ]; then
            SETUP_HOSTNAME=true
        fi
    fi

    if ask_yes_no "  Configure timezone?"; then
        SETUP_TIMEZONE=true
    fi

    if ask_yes_no "  Create a swap file? (recommended for VPS with limited RAM)"; then
        SETUP_SWAP=true
        read -p "    Swap size (e.g. 1G, 2G, 4G) [2G]: " -r swap_input
        [ -n "$swap_input" ] && SWAP_SIZE="$swap_input"
    fi

    if ask_yes_no "  Harden SSH configuration?"; then
        CONFIGURE_SSH=true
        if ask_yes_no "    Disable SSH password authentication? (key-only access)"; then
            ENABLE_PASSWORD_AUTH=false
        fi
    fi

    if ask_yes_no "  Setup UFW firewall?"; then
        SETUP_UFW=true
    fi

    if ask_yes_no "  Enable automatic security updates (unattended-upgrades)?"; then
        SETUP_UNATTENDED_UPGRADES=true
    fi

    echo
    echo -e "\033[1;33m--- Development Tools ---\033[0m"
    echo

    if ask_yes_no "  Install Python 3 (pip, venv, dev headers)?"; then
        INSTALL_PYTHON=true
    fi

    if ask_yes_no "  Install Java (OpenJDK, latest LTS)?"; then
        INSTALL_JAVA=true
    fi

    if ask_yes_no "  Install Go (latest stable)?"; then
        INSTALL_GO=true
    fi

    if ask_yes_no "  Install Node.js (system-wide)?"; then
        INSTALL_NODEJS=true
    fi

    if ask_yes_no "  Install C/C++ toolchain (gcc, g++, clang)?"; then
        INSTALL_CPP=true
    fi

    if ask_yes_no "  Install Docker & Docker Compose?"; then
        INSTALL_DOCKER=true
    fi

    if ask_yes_no "  Install Miniconda (Python environment manager)?"; then
        INSTALL_MINICONDA=true
    fi

    echo
    echo -e "\033[1;33m--- Server Software ---\033[0m"
    echo

    if ask_yes_no "  Install Nginx web server?"; then
        INSTALL_NGINX=true
    fi

    if ask_yes_no "  Install Cloudflared (Cloudflare Tunnel)?"; then
        INSTALL_CLOUDFLARED=true
    fi

    if ask_yes_no "  Install monitoring tools (htop, glances, bpytop, nload)?"; then
        INSTALL_MONITORING_TOOLS=true
    fi

    echo
    echo -e "\033[1;32mSetup configuration:\033[0m"
    echo -e "  \033[1;36m[Server]\033[0m"
    echo -e "  User:              $ADMIN_USER"
    [ "$SETUP_HOSTNAME" = true ] && echo -e "  Hostname:          $NEW_HOSTNAME"
    echo -e "  Timezone:          $SETUP_TIMEZONE"
    echo -e "  Swap:              $SETUP_SWAP ($SWAP_SIZE)"
    echo -e "  SSH Hardening:     $CONFIGURE_SSH"
    echo -e "  UFW Firewall:      $SETUP_UFW"
    echo -e "  Auto-updates:      $SETUP_UNATTENDED_UPGRADES"
    echo -e "  \033[1;36m[Development]\033[0m"
    echo -e "  Python:            $INSTALL_PYTHON"
    echo -e "  Java:              $INSTALL_JAVA (latest LTS — auto-detected after update)"
    echo -e "  Go:                $INSTALL_GO (latest stable — auto-detected)"
    echo -e "  Node.js:           $INSTALL_NODEJS (latest LTS via NVM)"
    echo -e "  C/C++:             $INSTALL_CPP"
    echo -e "  Docker:            $INSTALL_DOCKER"
    echo -e "  Miniconda:         $INSTALL_MINICONDA"
    echo -e "  \033[1;36m[Software]\033[0m"
    echo -e "  Nginx:             $INSTALL_NGINX"
    echo -e "  Cloudflared:       $INSTALL_CLOUDFLARED"
    echo -e "  Monitoring tools:  $INSTALL_MONITORING_TOOLS"
    echo

    if ! ask_yes_no "  Proceed with installation?" "y"; then
        log_info "Setup cancelled by user."
        exit 0
    fi
    echo
}

check_os_compatibility() {
    detect_distro

    case "$DISTRO_ID" in
        ubuntu)
            if [[ ! "$DISTRO_VERSION" =~ ^24\.04.* ]]; then
                log_warning "This script is optimized for Ubuntu 24.04. Detected: $DISTRO_VERSION"
                read -p "Do you want to continue anyway? (y/N): " -r
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 1
                fi
            fi
            ;;
        pop|zorin)
            log_info "Detected $DISTRO_ID $DISTRO_VERSION (Ubuntu-based). Proceeding with Debian/Ubuntu compatibility."
            ;;
        fedora)
            log_info "Detected Fedora $DISTRO_VERSION. Using DNF package manager."
            ;;
        *)
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                log_warning "Detected $DISTRO_ID (Debian-based). Proceeding with Debian compatibility."
            elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
                log_warning "Detected $DISTRO_ID (Fedora-based). Proceeding with Fedora compatibility."
            fi
            ;;
    esac
    return 0
}

backup_file() {
    local file_to_backup="$1"
    local owner_user="${2:-}" # Optional: user context for file operations

    local SudoPrefix=""
    # Ensure username is quoted if it contains special characters, though typically they don't.
    [[ -n "$owner_user" ]] && SudoPrefix="sudo -u '$owner_user' "

    # Check if file exists BEFORE attempting backup
    # Need to handle the command execution for test carefully with SudoPrefix
    if ! ${SudoPrefix}test -f "$file_to_backup"; then
        log_info "File '$file_to_backup' not found for backup. (This may be normal if it's created later by the script)."
        return 0 # Not an error, just nothing to back up
    fi

    local backup_filename_base
    backup_filename_base=$(${SudoPrefix}basename "$file_to_backup")
    local backup_dir_path
    backup_dir_path=$(${SudoPrefix}dirname "$file_to_backup")
    
    # Use a script-specific, timestamped backup name
    local actual_backup_path="${backup_dir_path}/${backup_filename_base}.nexuscore_setup.bak.$(date +%Y%m%d%H%M%S)"

    log_info "Attempting to create backup of '$file_to_backup' at '$actual_backup_path'..."
    # Preserve permissions, ownership, timestamps with -p
    if ${SudoPrefix}cp -p "$file_to_backup" "$actual_backup_path"; then
        log_info "Successfully created backup: $actual_backup_path"
        
        # Construct the restore command carefully, quoting paths.
        local restore_cmd="${SudoPrefix}mv -f '$actual_backup_path' '$file_to_backup'"
        add_cleanup_action_on_failure "log_warning 'Restoring $file_to_backup from $actual_backup_path'; $restore_cmd"
        return 0
    else
        log_error "CRITICAL: Failed to create backup for '$file_to_backup'. Halting to prevent data loss."
        # This error will propagate due to set -e (if active in calling context) and trigger cleanup_on_error
        return 1 
    fi
}

# ============================================================================
# Component installer functions (each runs in isolation via run_component)
# ============================================================================

install_hostname() {
    if [ -n "$NEW_HOSTNAME" ]; then
        local old_hostname
        old_hostname=$(hostname)
        sudo hostnamectl set-hostname "$NEW_HOSTNAME"
        if grep -qw "$old_hostname" /etc/hosts; then
            backup_file "/etc/hosts"
            sudo sed -i "s/\b${old_hostname}\b/$NEW_HOSTNAME/g" /etc/hosts
        fi
        log_success "Hostname set to $NEW_HOSTNAME."
    fi
}

install_timezone() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        log_info "You will be prompted to select your timezone..."
        sudo dpkg-reconfigure tzdata
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        log_info "Current timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || echo 'unknown')"
        log_info "Available timezones can be listed with: timedatectl list-timezones"
        read -p "Enter timezone (e.g., America/New_York, UTC): " -r tz_input
        if [ -n "$tz_input" ]; then
            sudo timedatectl set-timezone "$tz_input"
        fi
    fi
    log_success "Timezone configured to $(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value)."
}

install_swap() {
    log_info "Creating $SWAP_SIZE swap file..."
    sudo fallocate -l "$SWAP_SIZE" /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    if ! grep -q '/swapfile' /etc/fstab; then
        backup_file "/etc/fstab"
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
    fi
    if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
        echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf > /dev/null
        sudo sysctl vm.swappiness=10
    fi
    log_success "Swap file ($SWAP_SIZE) created and enabled."
}

install_ssh_hardening() {
    local sshd_config="/etc/ssh/sshd_config"
    backup_file "$sshd_config"
    sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
    if [ "$ENABLE_PASSWORD_AUTH" = true ]; then
        sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
    else
        sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
    fi
    sudo sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$sshd_config"
    sudo sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 5/' "$sshd_config"
    sudo systemctl restart sshd
    log_success "SSH hardened (RootLogin=no, PasswordAuth=$ENABLE_PASSWORD_AUTH, EmptyPasswords=no, MaxAuthTries=5)."
}

install_ufw() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        if ! command -v ufw &> /dev/null; then sudo apt install -y ufw; fi
        sudo ufw allow ssh
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw --force enable
        sudo ufw status verbose
        log_success "UFW configured and enabled."
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        sudo systemctl enable --now firewalld
        sudo firewall-cmd --permanent --add-service=ssh
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        sudo firewall-cmd --reload
        sudo firewall-cmd --list-all
        log_success "Firewalld configured and enabled."
    fi
}

install_python() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        if command -v python3 &> /dev/null && dpkg -s python3-pip &> /dev/null; then
            log_info "Python 3 and pip already installed. Ensuring venv and dev headers..."
        fi
        sudo apt install -y python3 python3-pip python3-venv python3-dev
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        if command -v python3 &> /dev/null && rpm -q python3-pip &> /dev/null; then
            log_info "Python 3 and pip already installed. Ensuring dev headers..."
        fi
        sudo dnf install -y python3 python3-pip python3-devel
    fi
    log_success "Python 3, pip, and dev headers are set up."
}

install_java() {
    if java -version 2>&1 | grep -q "openjdk version"; then
        log_info "Java already installed: $(java -version 2>&1 | head -1)"
    fi
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        sudo apt install -y "openjdk-${JAVA_VERSION}-jdk" "openjdk-${JAVA_VERSION}-jre"
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        sudo dnf install -y "java-${JAVA_VERSION}-openjdk" "java-${JAVA_VERSION}-openjdk-devel"
    fi
    log_success "OpenJDK $JAVA_VERSION installed."
}

install_cpp() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        sudo apt install -y gcc g++ gdb clang valgrind
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        sudo dnf install -y gcc gcc-c++ gdb clang valgrind
    fi
    log_success "C/C++ toolchain installed."
}

install_go() {
    local go_tar="go${GO_VERSION}.linux-$(get_arch).tar.gz"
    local go_tmp_path="/tmp/$go_tar"
    wget -O "$go_tmp_path" "https://go.dev/dl/$go_tar"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$go_tmp_path"
    rm -f "$go_tmp_path"
    if ! grep -q '/usr/local/go/bin' "$HOME/.bashrc"; then
        backup_file "$HOME/.bashrc" "$USER"
        echo 'export PATH=$PATH:/usr/local/go/bin' >> "$HOME/.bashrc"
    fi
    export PATH=$PATH:/usr/local/go/bin
    if command -v go &> /dev/null; then
        log_success "Go $(go version) installed."
    else
        log_error "Go installation failed."
        return 1
    fi
}

install_nodejs() {
    log_info "Installing Node.js and npm as system packages..."
    pkg_install nodejs npm
    if command -v node &> /dev/null; then
        log_success "Node.js $(node --version) installed system-wide."
    else
        log_error "Node.js installation failed."
        return 1
    fi
    if command -v npm &> /dev/null; then
        log_info "Installing global npm packages (system-wide)..."
        sudo npm install -g yarn typescript ts-node nodemon pm2
        log_success "Installed global npm packages."
    else
        log_warning "npm not found. Skipping global npm packages."
    fi
}

install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker already installed: $(docker --version). Ensuring service is running..."
        sudo systemctl enable --now docker
        if id "$ADMIN_USER" &>/dev/null && ! groups "$ADMIN_USER" | grep -q '\bdocker\b'; then
            sudo usermod -aG docker "$ADMIN_USER"
            log_info "User $ADMIN_USER added to docker group."
        fi
        log_success "Docker is ready."
        return 0
    fi
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        local docker_gpg_key_path="/etc/apt/keyrings/docker.gpg"
        local docker_repo_list_path="/etc/apt/sources.list.d/docker.list"
        # For Ubuntu derivatives (Pop!_OS, Zorin), use the "ubuntu" Docker repo
        local docker_distro="ubuntu"
        local docker_codename
        docker_codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
        if [ -z "$docker_codename" ]; then
            log_error "Unable to determine distribution codename for Docker repository."
            return 1
        fi
        sudo install -m 0755 -d /etc/apt/keyrings
        if [ ! -f "$docker_gpg_key_path" ]; then
            curl -fsSL "https://download.docker.com/linux/${docker_distro}/gpg" | sudo gpg --dearmor -o "$docker_gpg_key_path"
            sudo chmod a+r "$docker_gpg_key_path"
        fi
        if [ ! -f "$docker_repo_list_path" ]; then
            echo \
              "deb [arch=$(get_arch) signed-by=$docker_gpg_key_path] https://download.docker.com/linux/${docker_distro} \
              ${docker_codename} stable" | \
              sudo tee "$docker_repo_list_path" > /dev/null
            sudo apt update
        fi
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    if ! getent group docker > /dev/null; then
        sudo groupadd docker
        log_info "Created docker group."
    fi
    if id "$ADMIN_USER" &>/dev/null && ! groups "$ADMIN_USER" | grep -q '\bdocker\b'; then
        sudo usermod -aG docker "$ADMIN_USER"
        log_info "User $ADMIN_USER added to docker group."
    fi
    sudo systemctl enable --now docker
    log_success "Docker and Docker Compose installed and running."
}

install_miniconda() {
    CONDA_DIR="$HOME/miniconda3"
    backup_file "$HOME/.bashrc" "$USER"
    if [ -f "$HOME/.zshrc" ]; then
        backup_file "$HOME/.zshrc" "$USER"
    fi
    if [ ! -d "$CONDA_DIR/bin" ]; then
        local miniconda_tmp_dir="$HOME/miniconda_tmp"
        mkdir -p "$miniconda_tmp_dir"
        local miniconda_arch
        miniconda_arch=$(uname -m)
        wget "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${miniconda_arch}.sh" -O "$miniconda_tmp_dir/miniconda_installer.sh"
        bash "$miniconda_tmp_dir/miniconda_installer.sh" -b -u -p "$CONDA_DIR"
        rm -rf "$miniconda_tmp_dir"
        eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
        "$CONDA_DIR/bin/conda" init bash
        if [ -f "$HOME/.zshrc" ]; then
            "$CONDA_DIR/bin/conda" init zsh
        fi
        log_success "Miniconda installed to $CONDA_DIR."
    else
        log_info "Miniconda already installed. Sourcing."
        eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
    fi
    if command -v conda &> /dev/null; then
        conda config --set auto_activate_base false
        log_success "Configured conda auto_activate_base=false."
    else
        log_warning "Conda command not found after install."
    fi
}

install_monitoring_tools() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        sudo apt install -y glances bpytop nload lm-sensors
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        sudo dnf install -y glances bpytop nload lm_sensors
    fi
    log_success "Monitoring tools installed."
}

install_nginx() {
    if command -v nginx &> /dev/null; then
        log_info "Nginx already installed. Ensuring service is running."
        sudo systemctl enable --now nginx
        log_success "Nginx is ready."
        return 0
    fi
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        sudo apt install -y nginx
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        sudo dnf install -y nginx
    fi
    sudo systemctl enable --now nginx
    if [ "$SETUP_UFW" = true ]; then
        if [[ "$DISTRO_FAMILY" == "debian" ]] && sudo ufw status | grep -qw active; then
            sudo ufw allow 'Nginx Full'
        elif [[ "$DISTRO_FAMILY" == "fedora" ]] && systemctl is-active --quiet firewalld; then
            sudo firewall-cmd --permanent --add-service=http
            sudo firewall-cmd --permanent --add-service=https
            sudo firewall-cmd --reload
        fi
    fi
    log_success "Nginx installed and running."
}

install_cloudflared() {
    local arch
    arch=$(get_arch)
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        local cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.deb"
        local cloudflared_pkg_path="/tmp/cloudflared.deb"
        wget -O "$cloudflared_pkg_path" "$cloudflared_url"
        sudo dpkg -i "$cloudflared_pkg_path"
        sudo apt-get install -f -y
        rm -f "$cloudflared_pkg_path"
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        local cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}.rpm"
        local cloudflared_pkg_path="/tmp/cloudflared.rpm"
        wget -O "$cloudflared_pkg_path" "$cloudflared_url"
        sudo dnf install -y "$cloudflared_pkg_path"
        rm -f "$cloudflared_pkg_path"
    fi
    if command -v cloudflared &> /dev/null; then
        log_success "cloudflared $(cloudflared --version) installed."
    else
        log_error "cloudflared installation failed."
        return 1
    fi
}

install_fail2ban() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        sudo apt install -y fail2ban
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        sudo dnf install -y fail2ban
    fi
    sudo systemctl enable --now fail2ban
    JAIL_LOCAL_CONF="/etc/fail2ban/jail.local"
    if [ ! -f "$JAIL_LOCAL_CONF" ] || ! grep -qE "^\s*\[sshd\]" "$JAIL_LOCAL_CONF"; then
        backup_file "$JAIL_LOCAL_CONF"
        local sshd_logpath
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            sshd_logpath="/var/log/auth.log"
        elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
            sshd_logpath="%(sshd_log)s"
        fi
        sudo bash -c "cat >> '$JAIL_LOCAL_CONF'" << EOF

[sshd]
enabled = true
port = ssh
logpath = $sshd_logpath
maxretry = 5
bantime = 1h
findtime = 10m
EOF
        sudo systemctl restart fail2ban
        log_success "fail2ban configured for SSH protection."
    else
        log_info "fail2ban SSH config already exists."
    fi
}

install_unattended_upgrades() {
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        sudo apt install -y unattended-upgrades apt-listchanges
        echo 'APT::Periodic::Update-Package-Lists "1";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null
        echo 'APT::Periodic::Unattended-Upgrade "1";' | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades > /dev/null
        log_success "Automatic security updates enabled (unattended-upgrades)."
    elif [[ "$DISTRO_FAMILY" == "fedora" ]]; then
        sudo dnf install -y dnf-automatic
        sudo sed -i 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
        sudo systemctl enable --now dnf-automatic.timer
        log_success "Automatic security updates enabled (dnf-automatic)."
    fi
}

collect_system_logs() {
    LOGS_DIR="$HOME/system_logs"
    mkdir -p "$LOGS_DIR"
    date > "$LOGS_DIR/setup_complete_date.log"
    uname -a > "$LOGS_DIR/system_info.log"
    cat /proc/cpuinfo > "$LOGS_DIR/cpu_info.log" 2>/dev/null
    free -h > "$LOGS_DIR/memory_info.log"
    df -h > "$LOGS_DIR/disk_info.log"
    ip addr > "$LOGS_DIR/network_info.log" 2>/dev/null
    if command -v docker &> /dev/null; then
        docker info > "$LOGS_DIR/docker_info.log" 2>/dev/null || true
    fi
    {
        echo "NexusCore Setup - $(date)"
        echo "User: $ADMIN_USER"
        echo "Hostname: $(hostname)"
        echo "Python: $INSTALL_PYTHON"
        echo "Java: $INSTALL_JAVA"
        echo "Go: $INSTALL_GO"
        echo "Node.js: $INSTALL_NODEJS"
        echo "C/C++: $INSTALL_CPP"
        echo "Docker: $INSTALL_DOCKER"
        echo "Miniconda: $INSTALL_MINICONDA"
        echo "Nginx: $INSTALL_NGINX"
        echo "Cloudflared: $INSTALL_CLOUDFLARED"
        echo "Monitoring: $INSTALL_MONITORING_TOOLS"
        echo "UFW: $SETUP_UFW"
        echo "SSH Hardened: $CONFIGURE_SSH"
        echo "Swap: $SETUP_SWAP ($SWAP_SIZE)"
        echo "Auto-updates: $SETUP_UNATTENDED_UPGRADES"
        echo ""
        echo "Succeeded: ${SUCCEEDED_COMPONENTS[*]:-none}"
        echo "Failed: ${FAILED_COMPONENTS[*]:-none}"
        echo "Skipped: ${SKIPPED_COMPONENTS[*]:-none}"
    } > "$LOGS_DIR/nexuscore_config.log"
    log_success "System logs saved to $LOGS_DIR"
}

# ============================================================================
# Main Operations — critical setup runs with set -e, optional components
# are isolated so a failure in one doesn't stop the rest.
# ============================================================================
run_main_operations() {
    print_banner

    # --- Critical pre-flight checks (must succeed) ---
    set -e
    check_os_compatibility

    log_info "Starting NexusCore Server Setup v3.3 for user: $ADMIN_USER"
    if [ "$RUNNING_AS_ROOT" = true ]; then
        log_info "Running as root. Administrative commands will run directly."
    else
        if [ "$HAS_NATIVE_SUDO" != true ]; then
            log_error "sudo is required when running as a non-root user."
            exit 1
        fi
    fi

    if [ "$RUNNING_AS_ROOT" != true ] && ! sudo -n true 2>/dev/null; then
        log_warning "Sudo access for $USER requires a password. You may be prompted multiple times."
    fi

    # Interactive component selection
    interactive_setup

    # --- Critical: System update & upgrade (must succeed) ---
    log_info "Updating package lists and upgrading existing packages..."
    log_info "(If another process is using the package manager, we will retry automatically.)"
    pkg_update
    pkg_upgrade
    log_success "System updated and upgraded."

    # --- Critical: Base packages (must succeed) ---
    log_info "Installing essential packages, development tools, and server utilities..."
    install_base_packages
    log_success "Essential packages installed."

    # --- Resolve tool versions (auto-detect latest LTS/stable after package lists are fresh) ---
    resolve_tool_versions

    set +e  # Disable exit-on-error — from here, optional components are isolated

    # --- Optional components (each isolated — failure in one doesn't stop others) ---

    # Server configuration
    if [ "$SETUP_HOSTNAME" = true ]; then
        run_component "Hostname" install_hostname
    fi

    if [ "$SETUP_TIMEZONE" = true ]; then
        run_component "Timezone" install_timezone
    fi

    if [ "$SETUP_SWAP" = true ]; then
        if [ -f /swapfile ]; then
            log_info "Swap file already exists. Skipping."
            SKIPPED_COMPONENTS+=("Swap File (already exists)")
        else
            run_component "Swap File" install_swap
        fi
    fi

    if [ "$CONFIGURE_SSH" = true ]; then
        run_component "SSH Hardening" install_ssh_hardening
    fi

    if [ "$SETUP_UFW" = true ]; then
        run_component "UFW Firewall" install_ufw
    fi

    # Security (always run, but non-fatal)
    run_component "Fail2ban" install_fail2ban

    # Development tools
    if [ "$INSTALL_PYTHON" = true ]; then
        run_component "Python 3" install_python
    fi

    if [ "$INSTALL_JAVA" = true ]; then
        run_component "Java (OpenJDK ${JAVA_VERSION})" install_java
    fi

    if [ "$INSTALL_CPP" = true ]; then
        run_component "C/C++ Toolchain" install_cpp
    fi

    if [ "$INSTALL_GO" = true ]; then
        if command -v go &> /dev/null; then
            log_info "Go already installed: $(go version). Skipping."
            SKIPPED_COMPONENTS+=("Go (already installed)")
        else
            run_component "Go ${GO_VERSION}" install_go
        fi
    fi

    if [ "$INSTALL_NODEJS" = true ]; then
        run_component "Node.js (NVM)" install_nodejs
    fi

    if [ "$INSTALL_DOCKER" = true ]; then
        run_component "Docker" install_docker
    fi

    if [ "$INSTALL_MINICONDA" = true ]; then
        run_component "Miniconda" install_miniconda
    fi

    # Server software
    if [ "$INSTALL_NGINX" = true ]; then
        run_component "Nginx" install_nginx
    fi

    if [ "$INSTALL_CLOUDFLARED" = true ]; then
        if command -v cloudflared &> /dev/null; then
            log_info "cloudflared already installed: $(cloudflared --version). Skipping."
            SKIPPED_COMPONENTS+=("Cloudflared (already installed)")
        else
            run_component "Cloudflared" install_cloudflared
        fi
    fi

    if [ "$INSTALL_MONITORING_TOOLS" = true ]; then
        run_component "Monitoring Tools" install_monitoring_tools
    fi

    if [ "$SETUP_UNATTENDED_UPGRADES" = true ]; then
        run_component "Unattended Upgrades" install_unattended_upgrades
    fi

    # System logs (always, non-fatal)
    run_component "System Logs" collect_system_logs
}


# --- Main Script Execution Control ---
main_entry_point() {
    # run_main_operations handles critical setup with set -e, and optional components
    # with run_component (isolated, non-fatal). It only fails if critical setup fails.
    if run_main_operations; then
        SCRIPT_SUCCESSFUL=true
        
        set +e # Disable exit on error for informational display
        
        # --- Component Summary ---
        echo
        log_info "==================== SETUP SUMMARY ===================="
        if [ ${#SUCCEEDED_COMPONENTS[@]} -gt 0 ]; then
            echo -e "\033[1;32m  ✓ Succeeded (${#SUCCEEDED_COMPONENTS[@]}):\033[0m"
            for c in "${SUCCEEDED_COMPONENTS[@]}"; do
                echo -e "    \033[1;32m✓\033[0m $c"
            done
        fi
        if [ ${#SKIPPED_COMPONENTS[@]} -gt 0 ]; then
            echo -e "\033[1;33m  → Skipped (${#SKIPPED_COMPONENTS[@]}):\033[0m"
            for c in "${SKIPPED_COMPONENTS[@]}"; do
                echo -e "    \033[1;33m→\033[0m $c"
            done
        fi
        if [ ${#FAILED_COMPONENTS[@]} -gt 0 ]; then
            echo -e "\033[1;31m  ✗ Failed (${#FAILED_COMPONENTS[@]}):\033[0m"
            for c in "${FAILED_COMPONENTS[@]}"; do
                echo -e "    \033[1;31m✗\033[0m $c"
            done
            echo
            log_warning "Some components failed. You can re-run the script — it will skip what's already installed and retry the rest."
        fi
        echo

        log_info "-------------------- SYSTEM INFORMATION --------------------"
        echo -e "\033[1;32mHostname:\033[0m $(hostname)"
        SERVER_IPS=$(hostname -I)
        echo -e "\033[1;32mServer IP Addresses:\033[0m $SERVER_IPS"
        echo -e "\033[1;32mTimezone:\033[0m $(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value 2>/dev/null || echo 'N/A')"
        if [ -f /swapfile ]; then
            echo -e "\033[1;32mSwap:\033[0m $(swapon --show=SIZE --noheadings 2>/dev/null || echo 'active')"
        fi
        echo
        if command -v neofetch &> /dev/null; then neofetch; else lsb_release -a 2>/dev/null; uname -a; fi

        log_info "-------------------- IMPORTANT NEXT STEPS --------------------"
        local step=1
        echo -e "\033[1;33m${step}. Reload your shell:\033[0m source ~/.bashrc"; ((step++))
        if [ "$INSTALL_DOCKER" = true ]; then
            echo -e "\033[1;33m${step}. Apply Docker group:\033[0m newgrp docker  (or log out and back in)"; ((step++))
        fi
        if [ "$CONFIGURE_SSH" = true ] && [ "$ENABLE_PASSWORD_AUTH" = false ]; then
            echo -e "   \033[1;31m⚠ Password auth is DISABLED. Ensure you have SSH key access before disconnecting!\033[0m"
            echo -e "\033[1;33m${step}. Setup SSH keys (from your local machine):\033[0m ssh-copy-id ${ADMIN_USER}@$(hostname -I | awk '{print $1}')"; ((step++))
        fi
        if [ "$INSTALL_NGINX" = true ]; then
            echo -e "\033[1;33m${step}. Nginx is running:\033[0m http://$(hostname -I | awk '{print $1}')"; ((step++))
        fi
        echo -e "\033[1;33m${step}. View system logs:\033[0m ls ~/system_logs/"; ((step++))

        echo
        if [ ${#FAILED_COMPONENTS[@]} -gt 0 ]; then
            log_warning "NexusCore Setup completed with ${#FAILED_COMPONENTS[@]} failed component(s). Review above."
        else
            log_success "NexusCore Setup completed successfully for user $USER!"
        fi

        REBOOT_PROMPT_MESSAGE="Reboot now to apply all changes? (y/N): "
        if [ "$INSTALL_DOCKER" = true ]; then
            REBOOT_PROMPT_MESSAGE="Reboot now to apply all changes (RECOMMENDED for Docker group changes)? (y/N): "
        fi
        read -p "$REBOOT_PROMPT_MESSAGE" -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rebooting system..."
            sudo reboot
        fi
    else
        # Critical setup failed (update/upgrade or base packages). Can't continue.
        log_error "NexusCore critical setup FAILED (system update or base packages)."
        log_error "Please check logs above. Fix the issue and re-run the script."
        exit 1
    fi
}

# --- Script Start ---
main_entry_point "$@"
