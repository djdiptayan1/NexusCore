# NexusCore Setup Script v3.1 for Ubuntu 24.04.2 LTS
# Simplified single-user setup with interactive prompts

# Exit on any error (globally, but main operations will be in a function with set -e),
# treat unset variables as an error, and ensure pipelines fail on error.
# set -euo pipefail # We will manage 'e' more granularly.
set -uo pipefail

# --- Configuration (defaults, overridden by interactive prompts) ---
ADMIN_USER="$USER"
JAVA_VERSION="17"
GO_VERSION="1.23.6"
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
    echo -e "\033[1;36mComplete Server Setup Script v3.1 for Ubuntu 24.04.2 LTS\033[0m"
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

    if ask_yes_no "  Install Java (OpenJDK $JAVA_VERSION)?"; then
        INSTALL_JAVA=true
    fi

    if ask_yes_no "  Install Go ($GO_VERSION)?"; then
        INSTALL_GO=true
    fi

    if ask_yes_no "  Install Node.js (via NVM)?"; then
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
    echo -e "  Swap ($SWAP_SIZE):        $SETUP_SWAP"
    echo -e "  SSH Hardening:     $CONFIGURE_SSH"
    echo -e "  UFW Firewall:      $SETUP_UFW"
    echo -e "  Auto-updates:      $SETUP_UNATTENDED_UPGRADES"
    echo -e "  \033[1;36m[Development]\033[0m"
    echo -e "  Python:            $INSTALL_PYTHON"
    echo -e "  Java:              $INSTALL_JAVA"
    echo -e "  Go:                $INSTALL_GO"
    echo -e "  Node.js:           $INSTALL_NODEJS"
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
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" ]]; then
            log_error "This script is designed for Ubuntu only. Detected: $ID"
            return 1
        fi
        
        if [[ ! "$VERSION_ID" =~ ^24\.04.* ]]; then
            log_warning "This script is optimized for Ubuntu 24.04. Detected: $VERSION_ID"
            read -p "Do you want to continue anyway? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    else
        log_error "Unable to determine OS. This script is designed for Ubuntu 24.04 LTS."
        return 1
    fi
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

# --- Main Operations Function ---
# This function will contain all the core setup logic.
# It will run with 'set -e' so any error triggers the ERR trap and then exits this function.
run_main_operations() {
    set -e # Critical: enable exit on error for this block

    print_banner
    check_os_compatibility # This function now returns 1 on failure

    log_info "Starting NexusCore Server Setup v3.1 for user: $ADMIN_USER"
    if [ "$(id -u)" = "0" ]; then
       log_error "This script should not be run as root. Run as a sudo-enabled user."
       exit 1
    fi

    if ! sudo -n true 2>/dev/null; then
        log_warning "Sudo access for $USER requires a password. You may be prompted multiple times."
    fi

    # Interactive component selection
    interactive_setup

    log_info "Updating package lists and upgrading existing packages..."
    sudo apt update
    sudo apt upgrade -y
    log_success "System updated and upgraded."

    # --- Install Basic Utilities & Build Tools ---
    log_info "Installing essential packages, development tools, and server utilities..."
    sudo apt install -y \
        git curl wget build-essential software-properties-common apt-transport-https \
        ca-certificates gnupg lsb-release unzip zip make cmake pkg-config autoconf automake \
        libtool gettext tree htop btop iotop iftop ncdu gnupg2 pass neofetch \
        tmux screen vim nano jq net-tools dnsutils rsync socat mtr-tiny nload \
        sysstat logrotate cron
    log_success "Essential packages, development tools, and server utilities installed."

    # --- Hostname Configuration ---
    if [ "$SETUP_HOSTNAME" = true ] && [ -n "$NEW_HOSTNAME" ]; then
        log_info "Setting hostname to '$NEW_HOSTNAME'..."
        local old_hostname
        old_hostname=$(hostname)
        sudo hostnamectl set-hostname "$NEW_HOSTNAME"
        # Update /etc/hosts if the old hostname is referenced
        if grep -qw "$old_hostname" /etc/hosts; then
            backup_file "/etc/hosts"
            sudo sed -i "s/\b${old_hostname}\b/$NEW_HOSTNAME/g" /etc/hosts
        fi
        add_cleanup_action_on_failure "log_warning 'Restoring hostname to $old_hostname'; sudo hostnamectl set-hostname '$old_hostname'"
        log_success "Hostname set to $NEW_HOSTNAME."
    fi

    # --- Timezone Configuration ---
    if [ "$SETUP_TIMEZONE" = true ]; then
        log_info "Configuring timezone (you will be prompted to select your timezone)..."
        sudo dpkg-reconfigure tzdata
        log_success "Timezone configured to $(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value)."
    fi

    # --- Swap File ---
    if [ "$SETUP_SWAP" = true ]; then
        if [ -f /swapfile ]; then
            log_info "Swap file already exists. Skipping swap creation."
        else
            log_info "Creating $SWAP_SIZE swap file..."
            sudo fallocate -l "$SWAP_SIZE" /swapfile
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
            sudo swapon /swapfile
            add_cleanup_action_on_failure "log_warning 'Removing swap file'; sudo swapoff /swapfile 2>/dev/null; sudo rm -f /swapfile"
            # Make swap persistent
            if ! grep -q '/swapfile' /etc/fstab; then
                backup_file "/etc/fstab"
                echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
            fi
            # Optimize swap settings
            if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
                echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf > /dev/null
                sudo sysctl vm.swappiness=10
            fi
            log_success "Swap file ($SWAP_SIZE) created and enabled."
        fi
    fi

    # --- SSH Hardening ---
    if [ "$CONFIGURE_SSH" = true ]; then
        log_info "Configuring SSH security..."
        local sshd_config="/etc/ssh/sshd_config"
        backup_file "$sshd_config"

        # Disable root login
        sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
        # Configure password authentication
        if [ "$ENABLE_PASSWORD_AUTH" = true ]; then
            sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$sshd_config"
        else
            sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
        fi
        # Disable empty passwords
        sudo sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$sshd_config"
        # Limit max auth tries
        sudo sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 5/' "$sshd_config"

        sudo systemctl restart sshd
        add_cleanup_action_on_failure "log_warning 'SSH config was modified; backup exists at ${sshd_config}.nexuscore_setup.bak.*'"
        log_success "SSH hardened (RootLogin=no, PasswordAuth=$ENABLE_PASSWORD_AUTH, EmptyPasswords=no, MaxAuthTries=5)."
    fi

    # --- Firewall (UFW) ---
    if [ "$SETUP_UFW" = true ]; then
        log_info "Setting up UFW (Uncomplicated Firewall)..."
        if ! command -v ufw &> /dev/null; then sudo apt install -y ufw; fi
        
        sudo ufw allow ssh
        add_cleanup_action_on_failure "sudo ufw delete allow ssh"
        sudo ufw allow 80/tcp
        add_cleanup_action_on_failure "sudo ufw delete allow 80/tcp"
        sudo ufw allow 443/tcp
        add_cleanup_action_on_failure "sudo ufw delete allow 443/tcp"
        
        # Store current UFW status to decide if we need to disable it on cleanup
        local ufw_was_active_before_enable=false
        if sudo ufw status | grep -qw active; then
            ufw_was_active_before_enable=true
        fi

        sudo ufw --force enable
        # If enable succeeded, but a later step fails:
        # Only disable UFW if it wasn't active before we enabled it.
        if [ "$ufw_was_active_before_enable" = false ]; then
            add_cleanup_action_on_failure "log_warning 'Disabling UFW as it was enabled by this script run.'; sudo ufw --force disable"
        else
            add_cleanup_action_on_failure "log_info 'UFW was active before this script run, not disabling it during cleanup.'"
        fi
        
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

    # Go
    if [ "$INSTALL_GO" = true ]; then
        log_info "Installing Go $GO_VERSION..."
        local go_tar="go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz"
        local go_tmp_path="/tmp/$go_tar"
        wget -O "$go_tmp_path" "https://go.dev/dl/$go_tar"
        add_cleanup_action_on_failure "log_warning 'Removing downloaded Go tarball'; rm -f '$go_tmp_path'"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "$go_tmp_path"
        add_cleanup_action_on_failure "log_warning 'Removing Go installation'; sudo rm -rf /usr/local/go"
        rm -f "$go_tmp_path"

        # Add Go to PATH in .bashrc if not already present
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
    fi
    
    # Node.js (via NVM) - for current user (assumed to be ADMIN_USER)
    if [ "$INSTALL_NODEJS" = true ]; then
        log_info "Installing Node.js via NVM for current user ($USER)..."
        export NVM_DIR="$HOME/.nvm" # Ensure NVM_DIR is set for the script's operations
        
        # Backup relevant shell configuration files before modification
        backup_file "$HOME/.bashrc" "$USER"
        if [ -f "$HOME/.zshrc" ]; then
            backup_file "$HOME/.zshrc" "$USER"
        fi

        if [ ! -d "$NVM_DIR" ]; then
            mkdir -p "$NVM_DIR" # NVM installer needs this
            # If mkdir fails, set -e will halt.
            add_cleanup_action_on_failure "log_warning 'Removing NVM directory for current user $USER'; rm -rf '$NVM_DIR'"
            
            # The NVM install script itself appends to rc files. The backup/restore handles this.
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
            # Source NVM for the current script session to install Node
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

            if command -v nvm &> /dev/null; then
                set +u # NVM scripts might use unbound variables
                nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
                set -u
                log_success "Node.js LTS installed via NVM and activated for this session."
            else 
                log_error "NVM installation command ran, but NVM command not found. NVM setup failed for current user."
                # This will cause script to exit due to set -e if nvm install returned error, or if we return 1
                return 1 # Explicitly fail
            fi
        else
            log_info "NVM already installed for current user. Sourcing and ensuring LTS Node.js."
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            set +u
            if ! nvm ls 'lts/*' &> /dev/null || ! (nvm current | grep -qE 'lts|node'); then
                nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
            elif ! (nvm current | grep -q 'lts'); then
                nvm use 'lts/*' && nvm alias default 'lts/*'
            fi
            set -u
            log_success "NVM sourced, Node.js LTS configured and activated for this session."
        fi
        
        # Global npm packages
        if command -v npm &> /dev/null; then
            log_info "Installing global npm packages: yarn, typescript, ts-node, nodemon, pm2..."
            ( # Subshell to keep NVM sourcing local if needed, though already sourced
              [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
              set +u 
              npm install -g yarn typescript ts-node nodemon pm2
              set -u
            )
            log_success "Installed global npm packages."
        else
            log_warning "npm command not found after NVM setup. Skipping global npm packages."
        fi
    fi

    # Docker & Docker Compose
    if [ "$INSTALL_DOCKER" = true ]; then
        log_info "Installing Docker and Docker Compose..."
        local docker_gpg_key_path="/etc/apt/keyrings/docker.gpg"
        local docker_repo_list_path="/etc/apt/sources.list.d/docker.list"
        local docker_group_created_by_script=false

        sudo install -m 0755 -d /etc/apt/keyrings
        if [ ! -f "$docker_gpg_key_path" ]; then
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o "$docker_gpg_key_path"
            sudo chmod a+r "$docker_gpg_key_path"
            add_cleanup_action_on_failure "log_warning 'Removing Docker GPG key'; sudo rm -f '$docker_gpg_key_path'"
        fi
        if [ ! -f "$docker_repo_list_path" ]; then
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=$docker_gpg_key_path] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              sudo tee "$docker_repo_list_path" > /dev/null
            add_cleanup_action_on_failure "log_warning 'Removing Docker apt repository list'; sudo rm -f '$docker_repo_list_path'"
            sudo apt update
        fi
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        # No specific cleanup for docker packages, too complex. If GPG/repo list were added, they'd be removed.
        
        if ! getent group docker > /dev/null; then
            sudo groupadd docker
            add_cleanup_action_on_failure "log_warning 'Removing docker group created by script'; sudo groupdel docker"
            docker_group_created_by_script=true # Track if we created it
            log_info "Created docker group."
        fi
        if id "$ADMIN_USER" &>/dev/null; then
            if ! groups "$ADMIN_USER" | grep -q '\bdocker\b'; then
                sudo usermod -aG docker "$ADMIN_USER"
                log_info "User $ADMIN_USER added to docker group."
            fi
        fi

        sudo systemctl enable --now docker
        add_cleanup_action_on_failure "log_warning 'Disabling and stopping Docker service'; sudo systemctl disable --now docker"
        log_success "Docker and Docker Compose installed and service enabled/started."
    fi

    # Miniconda - for current user (assumed to be ADMIN_USER)
    if [ "$INSTALL_MINICONDA" = true ]; then
        log_info "Installing Miniconda for current user ($USER)..."
        CONDA_DIR="$HOME/miniconda3"
        
        # Backup shell config files before Miniconda modifies them
        backup_file "$HOME/.bashrc" "$USER"
        if [ -f "$HOME/.zshrc" ]; then
            backup_file "$HOME/.zshrc" "$USER"
        fi

        if [ ! -d "$CONDA_DIR/bin" ]; then
            local miniconda_tmp_dir="$HOME/miniconda_tmp"
            mkdir -p "$miniconda_tmp_dir"
            add_cleanup_action_on_failure "log_warning 'Removing Miniconda temp download dir'; rm -rf '$miniconda_tmp_dir'"
            
            wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$miniconda_tmp_dir/miniconda_installer.sh"
            # If wget fails, set -e halts, cleanup for $miniconda_tmp_dir runs.
            
            bash "$miniconda_tmp_dir/miniconda_installer.sh" -b -u -p "$CONDA_DIR"
            # If bash installer fails, set -e halts. $CONDA_DIR might be partially created.
            add_cleanup_action_on_failure "log_warning 'Removing Miniconda directory for $USER'; rm -rf '$CONDA_DIR'"
            
            rm -rf "$miniconda_tmp_dir" # Clean up installer and temp dir now
            # We need to remove the cleanup action for miniconda_tmp_dir if we manually delete it.
            # Simpler: don't manually delete. Let cleanup handle it if script fails.
            # If script succeeds, SCRIPT_SUCCESSFUL=true prevents cleanup.
            # So, it's fine to leave the add_cleanup_action for miniconda_tmp_dir.

            eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
            "$CONDA_DIR/bin/conda" init bash
            if [ -f "$HOME/.zshrc" ]; then
                "$CONDA_DIR/bin/conda" init zsh
            fi
            log_success "Miniconda installed to $CONDA_DIR and shell initialised."
        else
            log_info "Miniconda already installed for current user. Sourcing for current session."
            eval "$("$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
        fi
        
        if command -v conda &> /dev/null; then
            conda config --set auto_activate_base false
            log_success "Configured conda to not auto-activate base environment for current user."
        else
            log_warning "Conda command not found. Could not set auto_activate_base for current user."
        fi
    fi

    # --- Monitoring Tools ---
    if [ "$INSTALL_MONITORING_TOOLS" = true ]; then
        log_info "Installing monitoring tools (glances, bpytop, nload, lm-sensors)..."
        sudo apt install -y glances bpytop nload lm-sensors
        log_success "Monitoring tools installed."
    fi

    # --- Install Nginx ---
    if [ "$INSTALL_NGINX" = true ]; then
        log_info "Installing Nginx web server..."
        sudo apt install -y nginx
        sudo systemctl enable --now nginx
        add_cleanup_action_on_failure "log_warning 'Disabling and stopping Nginx'; sudo systemctl disable --now nginx"
        # If UFW is active, ensure Nginx profile is allowed
        if [ "$SETUP_UFW" = true ] && sudo ufw status | grep -qw active; then
            sudo ufw allow 'Nginx Full'
        fi
        log_success "Nginx installed and running."
    fi

    # --- Install Cloudflared ---
    if [ "$INSTALL_CLOUDFLARED" = true ]; then
        log_info "Installing cloudflared..."
        if ! command -v cloudflared &> /dev/null; then
            ARCH=$(dpkg --print-architecture)
            CLOUDFLARED_LATEST_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"
            local cloudflared_deb_path="/tmp/cloudflared.deb"
            
            wget -O "$cloudflared_deb_path" "${CLOUDFLARED_LATEST_URL}"
            add_cleanup_action_on_failure "log_warning 'Removing downloaded cloudflared deb'; rm -f '$cloudflared_deb_path'"
            
            sudo dpkg -i "$cloudflared_deb_path"
            # If dpkg succeeds, register cleanup for the package
            add_cleanup_action_on_failure "log_warning 'Purging cloudflared package'; sudo apt-get purge -y cloudflared && sudo apt-get autoremove -y"

            sudo apt-get install -f -y # Install dependencies if any
            # rm "$cloudflared_deb_path" # Let cleanup handle or successful exit skip cleanup
            
            if command -v cloudflared &> /dev/null; then
                log_success "cloudflared $(cloudflared --version) installed."
            else
                log_error "cloudflared installation failed (command not found after dpkg)."
                return 1 # Explicitly fail
            fi
        else
            log_info "cloudflared already installed. Version: $(cloudflared --version)"
        fi
    fi

    # --- Security Improvements ---
    log_info "Installing and configuring additional security tools..."
    log_info "Installing fail2ban for SSH protection..."
    sudo apt install -y fail2ban
    sudo systemctl enable --now fail2ban
    add_cleanup_action_on_failure "log_warning 'Disabling and stopping fail2ban'; sudo systemctl disable --now fail2ban"
    # We won't try to uninstall fail2ban package itself.

    JAIL_LOCAL_CONF="/etc/fail2ban/jail.local"
    if [ ! -f "$JAIL_LOCAL_CONF" ] || ! grep -qE "^\s*\[sshd\]" "$JAIL_LOCAL_CONF"; then # Check for [sshd] at start of line
        log_info "Creating/updating fail2ban jail.local configuration for SSH..."
        backup_file "$JAIL_LOCAL_CONF" # Backup as root
        
        sudo bash -c "cat >> '$JAIL_LOCAL_CONF'" << EOF

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 5
bantime = 1h
findtime = 10m
EOF
        # If cat fails, backup is restored. If succeeds, restore action is armed.
        sudo systemctl restart fail2ban
        log_success "fail2ban configured to protect SSH via jail.local."
    else
        log_info "fail2ban sshd configuration seems to exist in $JAIL_LOCAL_CONF or is managed elsewhere. No changes made."
    fi

    # --- Unattended Upgrades (Automatic Security Updates) ---
    if [ "$SETUP_UNATTENDED_UPGRADES" = true ]; then
        log_info "Configuring automatic security updates (unattended-upgrades)..."
        sudo apt install -y unattended-upgrades apt-listchanges
        # Configure non-interactively
        echo 'APT::Periodic::Update-Package-Lists "1";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null
        echo 'APT::Periodic::Unattended-Upgrade "1";' | sudo tee -a /etc/apt/apt.conf.d/20auto-upgrades > /dev/null
        log_success "Automatic security updates enabled."
    fi

    # --- Create System Logs Directory for current user ---
    log_info "Creating system logs directory for current user ($USER)..."
    LOGS_DIR="$HOME/system_logs"
    mkdir -p "$LOGS_DIR"
    add_cleanup_action_on_failure "log_warning 'Removing system_logs directory for $USER'; rm -rf '$LOGS_DIR'"
    date > "$LOGS_DIR/setup_complete_date.log"
    uname -a > "$LOGS_DIR/system_info.log"
    cat /proc/cpuinfo > "$LOGS_DIR/cpu_info.log" 2>/dev/null
    free -h > "$LOGS_DIR/memory_info.log"
    df -h > "$LOGS_DIR/disk_info.log"
    ip addr > "$LOGS_DIR/network_info.log" 2>/dev/null
    if command -v docker &> /dev/null; then
        docker info > "$LOGS_DIR/docker_info.log" 2>/dev/null || true
    fi
    # Record what was installed
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
    } > "$LOGS_DIR/nexuscore_config.log"
    log_success "System logs directory created at $LOGS_DIR for user $USER"

    # If script reaches here, all main operations were successful
    # This is the "commit point" for the main operations.
    # Any errors after this point (in info display) should not trigger a full rollback.
}


# --- Main Script Execution Control ---
main_entry_point() {
    # All primary setup operations are in run_main_operations()
    # which runs with `set -e`. If it fails, ERR trap is triggered.
    if run_main_operations; then
        SCRIPT_SUCCESSFUL=true # Mark success to prevent cleanup_on_error from running
        log_success "All NexusCore setup operations completed successfully!"
        
        # Now, display final information. Errors here should not roll back the setup.
        set +e # Disable exit on error for purely informational commands
        
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
            echo -e "\033[1;33m${step}. Setup SSH keys (from your local machine):\033[0m ssh-copy-id your-user@$(hostname -I | awk '{print $1}')"; ((step++))
        fi
        if [ "$INSTALL_NGINX" = true ]; then
            echo -e "\033[1;33m${step}. Nginx is running:\033[0m http://$(hostname -I | awk '{print $1}')"; ((step++))
        fi
        echo -e "\033[1;33m${step}. View system logs:\033[0m ls ~/system_logs/"; ((step++))

        echo
        log_info "NexusCore Setup Process Completed for user $USER."

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
        # run_main_operations failed. ERR trap should have already run cleanup_on_error.
        # SCRIPT_SUCCESSFUL is still false.
        log_error "NexusCore Setup script FAILED. Please check logs above for details on errors and cleanup attempts."
        exit 1 # Ensure script exits with an error code
    fi
}

# --- Script Start ---
# Call the main entry point that controls operations and error handling.
main_entry_point "$@"