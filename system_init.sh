# ##############################################################################
# # SERVICE RESTART & SYSTEM DIAGNOSTICS - ENHANCED EDITION #
# ##############################################################################
# # Author: Diptayan Jash                                                     #
# # Version: 2.0 - NEXUS CORE ENHANCED                                        #
# # Description: Advanced service management with visual enhancements         #
# ##############################################################################

# --- Configuration: Services to Restart ---
SERVICES_TO_RESTART=(
    "cloudflared.service"         # Cloudflared tunnel service
    # "docker-api-wrapper.service"  # Custom Node.js API wrapper
    # "nginx.service"             # Web server (uncomment if needed)
    # "postgresql.service"        # Database service (uncomment if needed)
)

# Service restart order (dependencies first)
RESTART_ORDER=(
    "cloudflared.service"
    # "postgresql.service"
    # "docker-api-wrapper.service"
    # "nginx.service"
)

# --- Enhanced ANSI Color Codes & Effects ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'
RESET='\033[0m'

# Gradient colors for effects
NEON_BLUE='\033[38;5;39m'
NEON_GREEN='\033[38;5;46m'
NEON_PINK='\033[38;5;200m'
ELECTRIC_BLUE='\033[38;5;27m'

# --- Enhanced Helper Functions ---
print_header() {
    echo -e "${NEON_BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                              ║"
    printf "║%*s%*s║\n" $(((78+${#1})/2)) "$1" $(((78-${#1})/2)) ""
    echo "║                                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    sleep 0.8
}

print_subheader() {
    echo -e "\n${ELECTRIC_BLUE}${BOLD}┌─────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${ELECTRIC_BLUE}${BOLD}│ $1${RESET}${ELECTRIC_BLUE}${BOLD}$(printf "%*s" $((58-${#1})) "")│${RESET}"
    echo -e "${ELECTRIC_BLUE}${BOLD}└─────────────────────────────────────────────────────────────┘${RESET}"
    sleep 0.5
}

progress_bar() {
    local duration=$1
    local description=$2
    local width=50
    
    echo -ne "${CYAN}$description${RESET}\n"
    echo -ne "${GRAY}["
    
    for ((i=0; i<=width; i++)); do
        local percent=$((i * 100 / width))
        
        # Color gradient based on progress
        if [ $percent -lt 30 ]; then
            color="${RED}"
        elif [ $percent -lt 70 ]; then
            color="${YELLOW}"
        else
            color="${GREEN}"
        fi
        
        echo -ne "\r${GRAY}[${color}"
        printf "%*s" $i | tr ' ' '█'
        echo -ne "${GRAY}"
        printf "%*s" $((width-i)) | tr ' ' '░'
        echo -ne "${GRAY}] ${WHITE}${percent}%${RESET}"
        
        sleep $(echo "scale=3; $duration / $width" | bc -l 2>/dev/null || echo "0.1")
    done
    echo -e "\n"
}

animated_spinner() {
    local duration=$1
    local message=$2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local temp
    
    echo -ne "${CYAN}$message${RESET} "
    
    for ((i=0; i<duration*10; i++)); do
        temp=${spinstr#?}
        printf "${NEON_GREEN}[%c]${RESET}" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b"
    done
    printf "   \b\b\b"
    echo -e "${GREEN}✓ Complete${RESET}"
}

service_status_display() {
    local service_name="$1"
    local show_details="${2:-false}"
    
    if ! systemctl list-units --full -all | grep -Fq "${service_name}"; then
        echo -e "  ${RED}✗ Service '${service_name}' not found${RESET}"
        return 1
    fi
    
    local is_active is_enabled status_icon status_color enabled_icon enabled_color
    local main_pid memory_usage cpu_usage uptime_info
    
    # Get service status
    if systemctl is-active --quiet "$service_name"; then
        is_active="ACTIVE"
        status_icon="●"
        status_color="${NEON_GREEN}"
    else
        is_active="INACTIVE"
        status_icon="○"
        status_color="${RED}"
    fi
    
    if systemctl is-enabled --quiet "$service_name"; then
        is_enabled="ENABLED"
        enabled_icon="⚡"
        enabled_color="${GREEN}"
    else
        is_enabled="DISABLED"
        enabled_icon="⚠"
        enabled_color="${YELLOW}"
    fi
    
    # Basic display
    echo -e "  ${CYAN}┌─ Service: ${WHITE}${BOLD}${service_name}${RESET}"
    echo -e "  ${CYAN}├─ Status:  ${status_color}${status_icon} ${is_active}${RESET}"
    echo -e "  ${CYAN}└─ Startup: ${enabled_color}${enabled_icon} ${is_enabled}${RESET}"
    
    # Detailed display
    if [ "$show_details" = "true" ] && [ "$is_active" = "ACTIVE" ]; then
        main_pid=$(systemctl show "$service_name" --property=MainPID --value 2>/dev/null)
        if [ "$main_pid" != "0" ] && [ -n "$main_pid" ]; then
            memory_usage=$(ps -o rss= -p "$main_pid" 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
            cpu_usage=$(ps -o pcpu= -p "$main_name" 2>/dev/null | awk '{print $1"%"}')
            uptime_info=$(ps -o etime= -p "$main_pid" 2>/dev/null | tr -d ' ')
            
            echo -e "  ${GRAY}    ├─ PID: ${main_pid}${RESET}"
            [ -n "$memory_usage" ] && echo -e "  ${GRAY}    ├─ Memory: ${memory_usage}${RESET}"
            [ -n "$uptime_info" ] && echo -e "  ${GRAY}    └─ Runtime: ${uptime_info}${RESET}"
        fi
    fi
    echo
}

restart_service_enhanced() {
    local service="$1"
    local step_num="$2"
    local total_steps="$3"
    
    echo -e "${NEON_PINK}${BOLD}[STEP $step_num/$total_steps]${RESET} ${WHITE}Processing: ${CYAN}${BOLD}$service${RESET}"
    echo -e "${GRAY}────────────────────────────────────────────────────────${RESET}"
    
    # Pre-restart status
    echo -e "${YELLOW}► Pre-restart status:${RESET}"
    service_status_display "$service" "false"
    
    # Check dependencies
    local dependencies
    dependencies=$(systemctl list-dependencies "$service" --reverse --plain 2>/dev/null | grep -v "$service" | head -3)
    if [ -n "$dependencies" ]; then
        echo -e "${CYAN}► Dependent services detected:${RESET}"
        echo "$dependencies" | while read -r dep; do
            [ -n "$dep" ] && echo -e "  ${GRAY}├─ $dep${RESET}"
        done
        echo
    fi
    
    # Restart sequence
    echo -e "${YELLOW}► Initiating restart sequence...${RESET}"
    animated_spinner 2 "Stopping service"
    
    if sudo systemctl stop "$service" 2>/dev/null; then
        echo -e "  ${GREEN}✓ Service stopped successfully${RESET}"
    else
        echo -e "  ${YELLOW}⚠ Force stopping service${RESET}"
        sudo systemctl kill "$service" 2>/dev/null
        sleep 1
    fi
    
    animated_spinner 1 "Preparing restart"
    
    echo -e "${YELLOW}► Starting service...${RESET}"
    if sudo systemctl start "$service"; then
        animated_spinner 3 "Verifying service startup"
        
        # Post-restart verification
        sleep 2
        echo -e "${GREEN}► Post-restart verification:${RESET}"
        service_status_display "$service" "true"
        
        # Health check
        if systemctl is-active --quiet "$service"; then
            echo -e "  ${NEON_GREEN}${BOLD}🚀 RESTART SUCCESSFUL${RESET}"
            
            # Check if service is responding (for web services)
            if [[ "$service" == *"nginx"* ]] || [[ "$service" == *"apache"* ]]; then
                echo -e "  ${CYAN}► Running connectivity test...${RESET}"
                if curl -s --connect-timeout 5 http://localhost >/dev/null 2>&1; then
                    echo -e "  ${GREEN}✓ Service responding to HTTP requests${RESET}"
                else
                    echo -e "  ${YELLOW}⚠ Service may not be accepting HTTP connections${RESET}"
                fi
            fi
        else
            echo -e "  ${RED}${BOLD}❌ RESTART FAILED${RESET}"
            echo -e "  ${YELLOW}► Recent logs:${RESET}"
            sudo journalctl -u "$service" -n 5 --no-pager --output=short-precise | sed 's/^/    /'
        fi
    else
        echo -e "  ${RED}${BOLD}❌ FAILED TO START SERVICE${RESET}"
        echo -e "  ${YELLOW}► Error details:${RESET}"
        sudo journalctl -u "$service" -n 10 --no-pager --output=short-precise | sed 's/^/    /'
    fi
    
    echo -e "${GRAY}════════════════════════════════════════════════════════${RESET}\n"
}

display_installed_packages() {
    local packages=(
        "bash" "systemd" "curl" "wget" "git" "vim" "nano" "tmux"
        "htop" "btop" "python3" "python3-pip" "nodejs" "npm"
        "docker" "docker-ce" "nginx" "cloudflared" "fail2ban" "ufw" "firewalld"
    )
    local found_any=false

    echo -e "${CYAN}Installed package versions:${RESET}"

    if command -v dpkg-query >/dev/null 2>&1; then
        for pkg in "${packages[@]}"; do
            local version
            version=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)
            if [ -n "$version" ]; then
                printf "  %-20s %s\n" "$pkg" "$version"
                found_any=true
            fi
        done
    elif command -v rpm >/dev/null 2>&1; then
        for pkg in "${packages[@]}"; do
            local version
            version=$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$pkg" 2>/dev/null || true)
            if [ -n "$version" ] && [ "$version" != "package $pkg is not installed" ]; then
                printf "  %-20s %s\n" "$pkg" "$version"
                found_any=true
            fi
        done
    else
        echo -e "${YELLOW}  No supported package query tool found (dpkg/rpm).${RESET}"
        return
    fi

    if [ "$found_any" = false ]; then
        echo -e "${YELLOW}  None of the tracked packages were detected on this system.${RESET}"
    fi
}

# --- Main Script Enhancements ---

clear
print_header "NEXUS CORE v2.0 - SYSTEM INIT"
echo -e "${CYAN}► User: ${YELLOW}${BOLD}$(whoami)${RESET}"
echo -e "${GRAY}► Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}\n"

# System diagnostics
print_subheader "SYSTEM DIAGNOSTICS"
HOSTNAME_INFO=$(hostname)
OS_INFO=$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "N/A")
KERNEL_INFO=$(uname -r)
UPTIME_INFO=$(uptime -p)
IP_ADDRESS_INFO=$(ip route get 1.1.1.1 | awk '{print $7; exit}' 2>/dev/null || echo "N/A")
ARCH_INFO=$(uname -m)
CPU_MODEL=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "N/A")
CPU_CORES=$(nproc 2>/dev/null || echo "N/A")

echo -e "${CYAN}┌─ System Identity ─────────────────────────────────────────┐${RESET}"
echo -e "${CYAN}│${RESET} Hostname        : ${WHITE}$HOSTNAME_INFO${RESET}$(printf "%*s" $((40-${#HOSTNAME_INFO})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} OS              : ${WHITE}$OS_INFO${RESET}$(printf "%*s" $((40-${#OS_INFO})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} Kernel          : ${WHITE}$KERNEL_INFO${RESET}$(printf "%*s" $((40-${#KERNEL_INFO})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} Architecture    : ${WHITE}$ARCH_INFO${RESET}$(printf "%*s" $((40-${#ARCH_INFO})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} CPU Model       : ${WHITE}$CPU_MODEL${RESET}$(printf "%*s" $((40-${#CPU_MODEL})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} CPU Cores       : ${WHITE}$CPU_CORES${RESET}$(printf "%*s" $((40-${#CPU_CORES})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} Uptime          : ${GREEN}$UPTIME_INFO${RESET}$(printf "%*s" $((40-${#UPTIME_INFO})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} Primary IP      : ${GREEN}$IP_ADDRESS_INFO${RESET}$(printf "%*s" $((40-${#IP_ADDRESS_INFO})) "")${CYAN}│${RESET}"
echo -e "${CYAN}└───────────────────────────────────────────────────────────┘${RESET}"

echo

# Software update check
print_subheader "PACKAGE STATUS"
if command -v apt &> /dev/null; then
    progress_bar 3 "Synchronizing package database"
    sudo apt update -qq >/dev/null 2>&1 
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Package database synchronized${RESET}"
        echo -e "${CYAN}Package manager: apt${RESET}"
        
        progress_bar 2 "Checking for available upgrades"
        UPGRADABLE_PACKAGES=$(apt list --upgradable 2>/dev/null | grep -v "Listing...")
        
        if [ -z "$UPGRADABLE_PACKAGES" ]; then
            echo -e "${GREEN}All installed packages are up to date.${RESET}"
        else
            NUM_UPGRADABLE=$(echo "$UPGRADABLE_PACKAGES" | wc -l)
            echo -e "${YELLOW}${BOLD}Upgrades available: ${NUM_UPGRADABLE} package(s)${RESET}"
            echo -e "${CYAN}┌─ Upgradable Packages (Name | Candidate Version | Current Version) ──────────┐${RESET}"
            echo "$UPGRADABLE_PACKAGES" | head -10 | awk -F'/' '{split($2,a," "); current=a[5]; gsub(/]/,"",current); printf "│ %-20s | %-24s | %-20s │\n", $1, a[2], current}' | sed "s/^/\${CYAN}/" | sed "s/$/\${RESET}/"
            if [ $NUM_UPGRADABLE -gt 10 ]; then
                echo -e "${CYAN}│ ... and $((NUM_UPGRADABLE-10)) more packages$(printf "%*s" $((38-${#NUM_UPGRADABLE})) "") │${RESET}"
            fi
            echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${RESET}"
            echo -e "${WHITE}Run: ${NEON_BLUE}${BOLD}sudo apt upgrade${RESET}"
        fi
    else
        echo -e "${RED}✗ Failed to synchronize package database${RESET}"
    fi
elif command -v dnf &> /dev/null; then
    progress_bar 3 "Synchronizing package database"
    UPGRADABLE_PACKAGES=$(sudo dnf check-update 2>/dev/null | grep -E '^\S+\s+\S+\s+\S+' || true)
    
    echo -e "${GREEN}✓ Package database synchronized${RESET}"
    echo -e "${CYAN}Package manager: dnf${RESET}"
    
    if [ -z "$UPGRADABLE_PACKAGES" ]; then
        echo -e "${GREEN}All installed packages are up to date.${RESET}"
    else
        NUM_UPGRADABLE=$(echo "$UPGRADABLE_PACKAGES" | wc -l)
        echo -e "${YELLOW}${BOLD}Upgrades available: ${NUM_UPGRADABLE} package(s)${RESET}"
        echo -e "${CYAN}┌─ Upgradable Packages (Name | Version) ─────────────────────────────────────┐${RESET}"
        echo "$UPGRADABLE_PACKAGES" | head -10 | awk '{printf "│ %-30s | %-36s │\n", $1, $2}' | sed "s/^/\${CYAN}/" | sed "s/$/\${RESET}/"
        if [ $NUM_UPGRADABLE -gt 10 ]; then
            echo -e "${CYAN}│ ... and $((NUM_UPGRADABLE-10)) more packages$(printf "%*s" $((38-${#NUM_UPGRADABLE})) "") │${RESET}"
        fi
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────┘${RESET}"
        echo -e "${WHITE}Run: ${NEON_BLUE}${BOLD}sudo dnf upgrade${RESET}"
    fi
else
    echo -e "${YELLOW}⚠ No supported package manager detected (apt/dnf)${RESET}"
fi

echo
print_subheader "INSTALLED PACKAGE VERSIONS"
display_installed_packages

echo

# Enhanced Service Restart Sequence
print_subheader "SERVICE ORCHESTRATION"

if [ ${#SERVICES_TO_RESTART[@]} -eq 0 ]; then
    echo -e "${YELLOW}${BOLD}⚠ NO SERVICES CONFIGURED FOR QUANTUM RESTART${RESET}"
    echo -e "${GRAY}Configure services in SERVICES_TO_RESTART array${RESET}"
else
    # Filter services that actually exist and are in the restart list
    EXISTING_SERVICES=()
    for service in "${SERVICES_TO_RESTART[@]}"; do
        if systemctl list-units --full -all | grep -Fq "${service}"; then
            EXISTING_SERVICES+=("$service")
        fi
    done
    
    if [ ${#EXISTING_SERVICES[@]} -eq 0 ]; then
        echo -e "${RED}${BOLD}❌ No configured services found on this system${RESET}"
    else
        total_services=${#EXISTING_SERVICES[@]}
        echo -e "${NEON_PINK}${BOLD}Starting service restart sequence${RESET}"
        echo -e "${CYAN}► Services to process: ${WHITE}${BOLD}$total_services${RESET}"
        echo -e "${CYAN}► Estimated completion: ${WHITE}${BOLD}$((total_services * 15)) seconds${RESET}\n"
        
        step_counter=1
        for service in "${EXISTING_SERVICES[@]}"; do
            restart_service_enhanced "$service" "$step_counter" "$total_services"
            ((step_counter++))
            
            # Brief pause between services
            if [ $step_counter -le $total_services ]; then
                echo -e "${GRAY}► Preparing next service...${RESET}"
                sleep 1
            fi
        done
    fi
fi

# Enhanced Final Status Report
print_subheader "FINAL SYSTEM STATUS"

echo -e "${NEON_BLUE}${BOLD}Final system summary${RESET}\n"

if [ ${#EXISTING_SERVICES[@]} -gt 0 ]; then
    ACTIVE_COUNT=0
    echo -e "${CYAN}► Service Status Overview:${RESET}"
    
    for service in "${EXISTING_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "  ${GREEN}✓ ${service}${RESET}"
            ((ACTIVE_COUNT++))
        else
            echo -e "  ${RED}✗ ${service}${RESET}"
        fi
    done
    
    echo
    SUCCESS_RATE=$(echo "scale=1; $ACTIVE_COUNT * 100 / ${#EXISTING_SERVICES[@]}" | bc -l 2>/dev/null || echo "0")
    
    echo -e "${CYAN}┌─ Orchestration Results ────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} Services Processed  : ${WHITE}${BOLD}${#EXISTING_SERVICES[@]}${RESET}$(printf "%*s" $((35-${#EXISTING_SERVICES[@]})) "")${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} Services Active     : ${GREEN}${BOLD}${ACTIVE_COUNT}${RESET}$(printf "%*s" $((35-${#ACTIVE_COUNT})) "")${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} Success Rate        : ${NEON_GREEN}${BOLD}${SUCCESS_RATE}%${RESET}$(printf "%*s" $((33-${#SUCCESS_RATE})) "")${CYAN}│${RESET}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${RESET}"
fi

# System metrics
LOAD_AVG=$(uptime | awk -F'load average: ' '{print $2}')
FREE_MEM=$(free -m | awk '/^Mem:/{print $4}')
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
DISK_SPACE=$(df -h / | awk 'NR==2{print $4 " / " $2 " (" $5 " used)"}')

echo -e "\n${CYAN}┌─ System Metrics ───────────────────────────────────────────┐${RESET}"
echo -e "${CYAN}│${RESET} Load Average        : ${WHITE}${LOAD_AVG}${RESET}$(printf "%*s" $((35-${#LOAD_AVG})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} Memory (Free/Total) : ${WHITE}${FREE_MEM}MB / ${TOTAL_MEM}MB${RESET}$(printf "%*s" $((23-${#FREE_MEM}-${#TOTAL_MEM})) "")${CYAN}│${RESET}"
echo -e "${CYAN}│${RESET} Disk Space (Root)   : ${WHITE}${DISK_SPACE}${RESET}$(printf "%*s" $((35-${#DISK_SPACE})) "")${CYAN}│${RESET}"
echo -e "${CYAN}└─────────────────────────────────────────────────────────────┘${RESET}"

echo
print_header "NEXUS CORE v2.0: INITIALIZATION COMPLETE"
echo -e "${NEON_GREEN}${BOLD}System initialization completed.${RESET}"
echo -e "${CYAN}${BOLD}Review the package and status sections above for details.${RESET}"
echo
