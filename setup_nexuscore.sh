# NexusCore Setup Script v2.1 for Ubuntu 24.04.2 LTS
# With cleanup-on-failure mechanism

# Exit on any error (globally, but main operations will be in a function with set -e),
# treat unset variables as an error, and ensure pipelines fail on error.
# set -euo pipefail # We will manage 'e' more granularly.
set -uo pipefail

# --- Configuration ---
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

INSTALL_AMD_GPU_DRIVERS=true
AMD_GPU_INSTALLER_FULL_URL="https://repo.radeon.com/amdgpu-install/6.4.1/ubuntu/noble/amdgpu-install_6.4.60401-1_all.deb"
AMD_GPU_INSTALLER_FILENAME="amdgpu-install_6.4.60401-1_all.deb"

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
    echo -e "\033[1;36mAdvanced Server Setup Script v2.1 for Ubuntu 24.04.2 LTS\033[0m"
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

    log_info "Starting NexusCore Advanced Server Setup v2.1 for users: $ADMIN_USER and $ADDITIONAL_USER"
    log_info "This script should be run by the user who will be '$ADMIN_USER'."
    if [ "$(id -u)" = "0" ]; then
       log_error "This script should not be run as root. Run as a sudo-enabled user (preferably as '$ADMIN_USER')."
       exit 1 # Exit immediately, no cleanup needed from script itself.
    fi

    if [ "$USER" != "$ADMIN_USER" ]; then
        log_warning "You are running this script as user '$USER', but ADMIN_USER is set to '$ADMIN_USER'."
        log_warning "NVM and Miniconda for the current user ('$USER') will be set up. '$ADMIN_USER' will not get this specific setup unless '$USER' is '$ADMIN_USER'."
        log_warning "Consider running this script as '$ADMIN_USER', or manually run 'setup_user_environment \"$ADMIN_USER\"' later if needed."
        read -p "Continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1 # User chose to exit.
        fi
    fi

    if ! sudo -n true 2>/dev/null; then
        log_warning "Sudo access for $USER requires a password. You may be prompted multiple times."
    fi

    # Create the additional user early
    if [ -n "$ADDITIONAL_USER" ]; then
        create_restricted_sudo_user "$ADDITIONAL_USER" # This function will also use add_cleanup_action_on_failure
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
    # No specific cleanup for apt packages generally, too complex/risky.
    log_success "Essential packages, development tools, and neofetch installed."

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

    # --- Install AMD GPU Drivers (Optional) ---
    if [ "$INSTALL_AMD_GPU_DRIVERS" = true ]; then
        install_amd_gpu_drivers # This function should also manage its own cleanup registrations
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
        for user_to_add_docker_group in "$ADMIN_USER" "$ADDITIONAL_USER" "$USER"; do # Add current user too
            if [ -n "$user_to_add_docker_group" ] && id "$user_to_add_docker_group" &>/dev/null; then
                if ! groups "$user_to_add_docker_group" | grep -q '\bdocker\b'; then
                    sudo usermod -aG docker "$user_to_add_docker_group"
                    # Undoing usermod -aG is tricky; typically not done in simple cleanup.
                    # If the group itself was created by script and is removed, that's the main part.
                    log_info "User $user_to_add_docker_group added to docker group."
                fi
            fi
        done
        # Remove duplicates from the list of users for docker group
        # Handled by iterating unique users above.

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
        log_info "Installing additional monitoring tools (glances, bpytop, radeontop, lm-sensors)..."
        sudo apt install -y glances bpytop radeontop lm-sensors
        log_success "Additional monitoring tools installed."
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

    # --- Set up development environments for additional user ---
    if [ -n "$ADDITIONAL_USER" ] && id "$ADDITIONAL_USER" &>/dev/null; then
        setup_user_environment "$ADDITIONAL_USER" # This function also uses add_cleanup_action_on_failure
    else
        log_info "Skipping environment setup for ADDITIONAL_USER (not defined or does not exist)."
    fi

    # --- Create System Logs Directory for current user ---
    log_info "Creating system logs directory for current user ($USER)..."
    LOGS_DIR="$HOME/system_logs"
    mkdir -p "$LOGS_DIR"
    add_cleanup_action_on_failure "log_warning 'Removing system_logs directory for $USER'; rm -rf '$LOGS_DIR'"
    # Subsequent file creations in LOGS_DIR don't need individual cleanup if the dir is removed.
    date > "$LOGS_DIR/setup_complete_date.log"
    # ... other log files ...
    log_success "System logs directory created at $LOGS_DIR for user $USER"

    # If script reaches here, all main operations were successful
    # This is the "commit point" for the main operations.
    # Any errors after this point (in info display) should not trigger a full rollback.
}


# --- User Environment Setup Function (called for $USER and $ADDITIONAL_USER) ---
setup_user_environment() {
    local username="$1"
    local user_home
    user_home=$(eval echo "~$username") 
    
    if [ ! -d "$user_home" ]; then
        log_warning "Home directory for user $username ($user_home) not found. Skipping environment setup."
        return # Not a fatal error for the whole script usually
    fi

    log_info "Setting up development environment for user: $username"
    
    # NVM setup
    if [ "$INSTALL_NODEJS" = true ]; then
        log_info "Setting up NVM for user $username..."
        # Backup .bashrc and .zshrc before NVM script modifies them
        backup_file "$user_home/.bashrc" "$username"
        if sudo -u "$username" [ -f "$user_home/.zshrc" ]; then
            backup_file "$user_home/.zshrc" "$username"
        fi

        # NVM installation itself creates $NVM_DIR and modifies rc files.
        # The rc file changes are handled by backup/restore.
        # We need to add cleanup for the $NVM_DIR.
        sudo -u "$username" bash -e -u -o pipefail << EOF
export NVM_DIR="\$HOME/.nvm"
if [ ! -d "\$NVM_DIR" ]; then
    mkdir -p "\$NVM_DIR" # NVM installer expects this
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # Source NVM for this subshell to install Node
    [ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
    [ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
    if command -v nvm &> /dev/null; then
        set +u 
        nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
        set -u
    else
        echo "[ERROR_NVM_SUB] NVM command not found after install for $username" >&2
        exit 1 # Fail the subshell
    fi
else
    # NVM already exists, source and ensure LTS
    [ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
    set +u
    if ! nvm ls 'lts/*' &> /dev/null || ! (nvm current | grep -qE 'lts|node'); then
        nvm install --lts && nvm use --lts && nvm alias default 'lts/*'
    elif ! (nvm current | grep -q 'lts'); then
        nvm use 'lts/*' && nvm alias default 'lts/*'
    fi
    set -u
fi
EOF
        # Check if NVM directory was created (proxy for success of the subshell part)
        if sudo -u "$username" test -d "$user_home/.nvm"; then
            add_cleanup_action_on_failure "log_warning 'Removing NVM directory for $username'; sudo -u '$username' rm -rf '$user_home/.nvm'"
            log_success "NVM appears configured for $username. Shell rc files were backed up."
        else
            log_error "NVM setup for $username may have failed (NVM_DIR not found or subshell error)."
            # If subshell exited with 1, set -e in parent would catch it.
            # If subshell had echo "[ERROR_NVM_SUB]" but didn't exit 1, parent won't know unless we check output.
            # Assuming the subshell's set -e handles its failure.
        fi
    fi
    
    # Miniconda setup
    if [ "$INSTALL_MINICONDA" = true ]; then
        log_info "Setting up Miniconda for user $username..."
        backup_file "$user_home/.bashrc" "$username"
        if sudo -u "$username" [ -f "$user_home/.zshrc" ]; then
            backup_file "$user_home/.zshrc" "$username"
        fi
        
        sudo -u "$username" bash -e -u -o pipefail << EOF
CONDA_DIR="\$HOME/miniconda3"
if [ ! -d "\$CONDA_DIR/bin" ]; then
    MINICONDA_TMP_DIR="\$HOME/miniconda_tmp_user_$username" # Unique temp dir name
    mkdir -p "\$MINICONDA_TMP_DIR"
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "\$MINICONDA_TMP_DIR/miniconda_installer.sh"
    bash "\$MINICONDA_TMP_DIR/miniconda_installer.sh" -b -u -p "\$CONDA_DIR"
    rm -rf "\$MINICONDA_TMP_DIR"

    eval "\$("\$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
    "\$CONDA_DIR/bin/conda" init bash
    if [ -f "\$HOME/.zshrc" ]; then
        "\$CONDA_DIR/bin/conda" init zsh
    fi
else
    eval "\$("\$CONDA_DIR/bin/conda" 'shell.bash' 'hook')"
fi
PATH="\$CONDA_DIR/bin:\$PATH" # Ensure conda is available for config
if command -v conda &> /dev/null; then
    conda config --set auto_activate_base false
else
    echo "[ERROR_CONDA_SUB] Conda command not found after install for $username" >&2
    exit 1 # Fail the subshell
fi
EOF
        if sudo -u "$username" test -d "$user_home/miniconda3"; then
            add_cleanup_action_on_failure "log_warning 'Removing Miniconda directory for $username'; sudo -u '$username' rm -rf '$user_home/miniconda3'"
            # The temp dir MINICONDA_TMP_DIR is cleaned by the subshell. If subshell fails before rm, it's orphaned.
            # This is harder to clean from parent unless we make its path predictable and add cleanup from parent.
            # For now, accept small risk of orphaned temp dir on subshell failure.
            log_success "Miniconda appears configured for $username. Shell rc files were backed up."
        else
            log_error "Miniconda setup for $username may have failed (CONDA_DIR not found or subshell error)."
        fi
    fi
    
    # Create system logs directory for the user
    sudo -u "$username" mkdir -p "$user_home/system_logs"
    add_cleanup_action_on_failure "log_warning 'Removing system_logs for $username'; sudo -u '$username' rm -rf '$user_home/system_logs'"
    
    log_success "Development environment set up for user: $username"
}

# --- Restricted Sudo User Creation ---
create_restricted_sudo_user() {
    local username="$1"
    local user_created_by_this_script=false
    local sudoers_file_path="/etc/sudoers.d/${username}_restricted"
    
    log_info "Creating user '$username' with restricted sudo privileges..."
    
    if ! id "$username" &>/dev/null; then
        sudo adduser --disabled-password --gecos "" "$username"
        # Check if adduser succeeded
        if ! id "$username" &>/dev/null; then
            log_error "Failed to create user $username"
            return 1 # Triggers ERR trap
        fi
        user_created_by_this_script=true
        # Only add userdel to cleanup if this script created the user
        add_cleanup_action_on_failure "log_warning 'Removing user $username (created by this script run)'; sudo userdel --remove '$username'"
        log_info "User '$username' created."
        
        echo "Please set a password for user '$username':"
        sudo passwd "$username"
        sudo chage -d 0 "$username" # Force password change on first login
    else
        log_info "User '$username' already exists."
    fi
    
    sudo usermod -aG sudo "$username" # Add to sudo group
    # Undoing usermod -aG is complex (gpasswd -d user group), usually not done in basic cleanup.

    if [ "$INSTALL_DOCKER" = true ] && getent group docker > /dev/null; then
        sudo usermod -aG docker "$username"
    fi
    
    # Create the sudoers restriction file
    backup_file "$sudoers_file_path" # Backup if it exists, though usually it won't
    sudo tee "$sudoers_file_path" > /dev/null << EOF
Cmnd_Alias USERMOD_CMDS = /usr/sbin/adduser, /usr/sbin/useradd, /usr/sbin/userdel, /usr/sbin/usermod, /usr/sbin/deluser
Cmnd_Alias USER_PASSWD_CMDS = /usr/bin/passwd [A-Za-z0-9_]*, !/usr/bin/passwd $username, /usr/sbin/chpasswd, /usr/sbin/newusers
$username ALL=(ALL:ALL) ALL, !USERMOD_CMDS, !USER_PASSWD_CMDS
EOF
    if [ ! -f "$sudoers_file_path" ]; then # Check if tee command succeeded
        log_error "Failed to create sudoers file $sudoers_file_path"
        return 1
    fi
    # The backup_file function already added a restore for this. If the file didn't exist,
    # backup_file does nothing, so we need a specific rm for the newly created file.
    # To simplify: if backup_file's restore runs, it tries to mv a non-existent backup if file was new.
    # Let's add a direct rm and rely on LIFO. If backup existed and was restored, this rm fails harmlessly.
    # If file was new, this rm cleans it.
    add_cleanup_action_on_failure "log_warning 'Removing sudoers file $sudoers_file_path'; sudo rm -f '$sudoers_file_path'"

    sudo chmod 440 "$sudoers_file_path"
    
    if sudo visudo -c -f "$sudoers_file_path"; then # Check specific file
        log_success "Sudoers file syntax is valid for ${username}_restricted."
    else
        log_error "Sudoers file syntax error for ${username}_restricted. This will cause script failure and cleanup."
        # The 'rm' action for sudoers_file_path is already registered.
        # set -e will ensure visudo failure (exit code 1) halts the script.
        return 1 
    fi
    
    log_success "User '$username' configured with restricted sudo privileges."
}


# --- AMD GPU Driver Installation ---
install_amd_gpu_drivers() {
    log_info "Starting AMD GPU Driver (ROCm) installation..."
    # This function is complex. Full cleanup of a failed driver install is beyond simple scripting.
    # We will focus on cleaning up downloaded files.

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$VERSION_CODENAME" != "noble" ]]; then
            log_error "AMD GPU ROCm installation is for Ubuntu 24.04 (noble). Detected: $VERSION_CODENAME. Skipping."
            return 1 # Signal error to halt if this is critical path
        fi
    else
        log_error "Cannot determine OS version. Skipping AMD GPU ROCm installation."
        return 1
    fi

    log_info "Installing prerequisites for AMD GPU drivers..."
    sudo apt update
    sudo apt install -y python3-setuptools python3-wheel # If these fail, script halts.
    log_success "Prerequisites installed."

    local amd_installer_tmp_path="/tmp/${AMD_GPU_INSTALLER_FILENAME}"
    log_info "Downloading AMD GPU installer: ${AMD_GPU_INSTALLER_FILENAME}..."
    wget --progress=bar:force -O "$amd_installer_tmp_path" "${AMD_GPU_INSTALLER_FULL_URL}"
    # If wget fails, set -e halts. Add cleanup for the potentially partial download.
    add_cleanup_action_on_failure "log_warning 'Removing AMD GPU installer download'; rm -f '$amd_installer_tmp_path'"
    log_success "AMD GPU installer downloaded."

    log_info "Installing AMD GPU installer script package..."
    # This installs the 'amdgpu-install' package.
    sudo apt install -y "$amd_installer_tmp_path" 
    # If this install fails, script halts. Cleanup for downloaded .deb runs.
    # If it succeeds, we could add a cleanup to 'apt remove amdgpu-install', but that's getting into
    # package management rollback which we're trying to avoid for complexity.
    # For now, we'll assume if this step succeeds, the 'amdgpu-install' package is there.
    # The downloaded .deb itself can be cleaned.
    # rm "$amd_installer_tmp_path" # Let this be handled by cleanup action or successful script completion.

    log_info "Running amdgpu-install for workstation drivers and ROCm..."
    log_warning "This step can take a significant amount of time."
    sudo apt update 
    sudo amdgpu-install -y --usecase=workstation,rocm
    # If amdgpu-install fails, it can leave the system in a complex state.
    # A simple 'apt remove' might not be sufficient or correct.
    # The script will halt here. User intervention might be needed for deeper cleanup of ROCm.
    log_success "amdgpu-install process completed."

    log_info "Adding users to 'render' and 'video' groups..."
    # Adding users to groups is generally safe and low-risk to leave even if script fails later.
    # Reversing 'usermod -aG' is 'gpasswd -d user group', but usually not done.
    for user_to_add_gpu_groups in "$ADMIN_USER" "$ADDITIONAL_USER" "$USER"; do # Include current user
        if id "$user_to_add_gpu_groups" &>/dev/null; then
            sudo usermod -aG render "$user_to_add_gpu_groups"
            sudo usermod -aG video "$user_to_add_gpu_groups"
            log_info "User $user_to_add_gpu_groups added to 'render' and 'video' groups."
        fi
    done
    log_success "Users configured for GPU groups."
    log_warning "A SYSTEM REBOOT IS REQUIRED for AMD GPU drivers."
    log_success "AMD GPU Driver (ROCm) installation script part finished."
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
        # ... (all the neofetch, df, ip addr, etc. calls) ...
        echo -e "\033[1;32mHostname:\033[0m $(hostname)"
        SERVER_IPS=$(hostname -I)
        echo -e "\033[1;32mServer IP Addresses:\033[0m $SERVER_IPS"
        # (Continue with all informational outputs from the original script)
        if command -v neofetch &> /dev/null; then neofetch; else lsb_release -a; uname -a; fi
        # ... and so on for all final logs ...

        log_info "-------------------- IMPORTANT NEXT STEPS --------------------"
        # ... (all next steps messages) ...

        echo
        log_info "NexusCore Setup Process Completed for user $USER. Primary admin user is '$ADMIN_USER'."
        # ... (final user status message) ...

        REBOOT_PROMPT_MESSAGE="Reboot now to apply all changes? (y/N): "
        if [ "$INSTALL_AMD_GPU_DRIVERS" = true ] || [ "$INSTALL_DOCKER" = true ]; then
            REBOOT_PROMPT_MESSAGE="Reboot now to apply all changes (RECOMMENDED for Docker group changes and/or AMD GPU drivers)? (y/N): "
        fi
        read -p "$REBOOT_PROMPT_MESSAGE" -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rebooting system..."
            sudo reboot
        fi
    else
        # run_main_operations failed. ERR trap should have already run cleanup_on_error.
        # SCRIPT_SUCCESSFUL is still false.
        log_error "NexusCore Advanced Setup script FAILED. Please check logs above for details on errors and cleanup attempts."
        exit 1 # Ensure script exits with an error code
    fi
}

# --- Script Start ---
# Call the main entry point that controls operations and error handling.
main_entry_point "$@"