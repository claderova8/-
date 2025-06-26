#!/bin/bash
# Security Tools Installation Script
# 用于安装和管理常用的渗透测试和安全研究工具
# Author: Security Tools Installer
# Version: 4.17 - 增强二进制和Git工具的可执行权限验证

# --- 初始化与基本设置 ---
set -e          # 遇到错误时立即退出
set -o pipefail # 管道中的命令失败也视为失败

# 强制检查是否为Bash shell
if [ -z "$BASH_VERSION" ]; then
    echo -e "\033[0;31m\033[1m[✗]\033[0m \033[0;31m此脚本建议使用Bash shell运行。请尝试使用 'bash $0' 运行。\033[0m"
    exit 1
fi

# --- 样式与符号定义 ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'

CHECK_MARK="✓"; CROSS_MARK="✗"; ARROW="➤"; STAR="★"; GEAR="⚙"; ROCKET="🚀"; SHIELD="🛡️"; HAMMER="🔨"; PACKAGE="📦"; TRASH="🗑️"

# --- 全局变量 ---
PROXY_URL=""
declare -a TOOLS_TO_INSTALL # 记录所有用户选择安装/管理的工具，用于最终验证报告
MODE="install"              # 'install' or 'uninstall'
NON_INTERACTIVE=false
SELECTIONS_CMD=""
LOG_FILE=""
TEMP_DIR=""

# --- 配置区域 ---
# Go 环境变量配置
GOPATH_DIR="$HOME/go"
GO_BIN_DIR="$GOPATH_DIR/bin"
GO_PATH_EXPORTS=('export GOPATH=$HOME/go' 'export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin')
GF_CONFIG_DIR="$HOME/.gf" # gf 配置文件目录

# --- 工具定义 ---
declare -A BINARY_TOOLS=(
    ["waybackurls"]="tomnomnom/waybackurls|https://github.com/tomnomnom/waybackurls/releases/download/v{{version}}/waybackurls-linux-{{arch}}-{{version}}.tgz|waybackurls"
    ["qsreplace"]="tomnomnom/qsreplace|https://github.com/tomnomnom/qsreplace/releases/download/v{{version}}/qsreplace-linux-{{arch}}-{{version}}.tgz|qsreplace"
    ["nuclei"]="projectdiscovery/nuclei|https://github.com/projectdiscovery/nuclei/releases/download/v{{version}}/nuclei_{{version}}_linux_{{arch}}.zip|nuclei"
    ["subfinder"]="projectdiscovery/subfinder|https://github.com/projectdiscovery/subfinder/releases/download/v{{version}}/subfinder_{{version}}_linux_{{arch}}.zip|subfinder"
    ["gau"]="lc/gau|https://github.com/lc/gau/releases/download/v{{version}}/gau_{{version}}_linux_{{arch}}.tar.gz|gau"
    ["katana"]="projectdiscovery/katana|https://github.com/projectdiscovery/katana/releases/download/v{{version}}/katana_{{version}}_linux_{{arch}}.zip|katana"
    ["ffuf"]="ffuf/ffuf|https://github.com/ffuf/ffuf/releases/download/v{{version}}/ffuf_{{version}}_linux_{{arch}}.tar.gz|ffuf"
    ["naabu"]="projectdiscovery/naabu|https://github.com/projectdiscovery/naabu/releases/download/v{{version}}/naabu_{{version}}_linux_{{arch}}.zip|naabu"
    ["URLFinder"]="pingc0y/URLFinder|https://github.com/pingc0y/URLFinder/releases/download/{{version}}/URLFinder_Linux_{{arch_full}}.tar.gz|URLFinder"
    ["httpx"]="projectdiscovery/httpx|https://github.com/projectdiscovery/httpx/releases/download/v{{version}}/httpx_{{version}}_linux_{{arch}}.zip|httpx" # Added httpx
)
declare -A GO_INSTALL_TOOLS=( ["gf"]="github.com/tomnomnom/gf@latest" )
declare -A PIPX_TOOLS=( ["uro"]="uro" ) 
declare -A GIT_CLONE_TOOLS=( ["ghauri"]="r0oth3x49/ghauri|/opt/ghauri|ghauri/ghauri.py|ghauri" )
declare -A APT_TOOLS=( ["dirsearch"]="dirsearch" ["sqlmap"]="sqlmap" ["proxychains4"]="proxychains4" ["fail2ban"]="fail2ban" ["jq"]="jq" ) # Added jq for robust JSON parsing
declare -A SNAP_TOOLS=( ["dalfox"]="dalfox" )

# --- 辅助函数 ---
get_term_width() { tput cols 2>/dev/null || echo 80; }
print_separator() { char="${1:-=}"; printf "${BLUE}%*s${NC}\n" "$(get_term_width)" | tr ' ' "$char"; }
print_center() { text="$1"; color="${2:-$WHITE}"; padding=$(( ($(get_term_width) - ${#text}) / 2 )); printf "%*s${color}${BOLD}%s${NC}\n" "$padding" "" "$text"; }
print_title() { title="$1"; color="${2:-$CYAN}"; print_separator "="; echo; print_center "$title" "$color"; echo; print_separator "="; }
print_step() { step="$1"; color="${2:-$PURPLE}"; echo; echo -e "${color}${BOLD}${ARROW} $step${NC}"; print_separator "-"; }
log_info() { echo -e "${GREEN}${BOLD}[${CHECK_MARK}]${NC} ${WHITE}$1${NC}"; }
log_warn() { echo -e "${YELLOW}${BOLD}[${STAR}]${NC} ${YELLOW}$1${NC}"; }
log_error() { echo -e "${RED}${BOLD}[${CROSS_MARK}]${NC} ${RED}$1${NC}" >&2; }
log_progress() { echo -e "${BLUE}${BOLD}[${GEAR}]${NC} ${CYAN}$1${NC}"; }
log_install() { echo -e "${PURPLE}${BOLD}[${PACKAGE}]${NC} ${WHITE}正在安装: ${BOLD}$1${NC}"; }
log_uninstall() { echo -e "${RED}${BOLD}[${TRASH}]${NC} ${WHITE}正在卸载: ${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}${BOLD}[${ROCKET}]${NC} ${GREEN}$1${NC}"; }
log_skip() { echo -e "${CYAN}${BOLD}[${GEAR}]${NC} ${WHITE}$1${NC} ${YELLOW}(已${MODE}, 跳过)${NC}"; }

# 检查网络连接
check_internet_connection() {
    local host="baidu.com" # 可以替换为其他可靠的公共IP或域名
    local count=3
    local timeout=5
    log_progress "正在检查网络连接..."
    if ping -c "$count" -W "$timeout" "$host" >/dev/null 2>&1; then
        log_info "网络连接正常。"
        return 0
    else
        log_error "无法连接到互联网。请检查您的网络设置。"
        return 1
    fi
}

# --- 命令行参数解析 ---
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --uninstall) MODE="uninstall";;
            --proxy) PROXY_URL="https://ghproxy.com/";;
            --non-interactive) NON_INTERACTIVE=true;;
            --all) NON_INTERACTIVE=true; SELECTIONS_CMD="all";;
            --select) NON_INTERACTIVE=true; SELECTIONS_CMD="$2"; shift;;
            -h|--help) show_help; exit 0;;
            *) log_error "未知参数: $1"; show_help; exit 1;;
        esac
        shift
    done
}

show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  --uninstall         进入卸载模式"
    echo "  --proxy             启用下载代理 (ghproxy.com)"
    echo "  --non-interactive   使用非交互模式 (需要 --all 或 --select)"
    echo "  --all               (非交互) 选择所有工具类别"
    echo "  --select \"1 3 4\"  (非交互) 选择指定的工具类别"
    echo "  -h, --help          显示此帮助信息"
}

# --- 环境准备 ---
show_welcome() {
    clear
    local title_text="${SHIELD} Security Tools Manager v4.17 ${SHIELD}" # Updated version
    local mode_text="(当前模式: ${BOLD}${YELLOW}${MODE^^}${NC})"
    print_title "$title_text" "$CYAN"
    print_center "$mode_text"
    echo
}

show_selection_menu() {
    local prompt_text="选择要 ${MODE} 的工具类别"
    print_step "$prompt_text"
    
    options=(
        "Go 二进制工具 (${!BINARY_TOOLS[*]})"
        "Go 源码工具 (${!GO_INSTALL_TOOLS[*]})"
        "Python 工具 (pipx) (${!PIPX_TOOLS[*]})"
        "Python 工具 (git clone) (${!GIT_CLONE_TOOLS[*]})"
        "APT 包管理器工具 (${!APT_TOOLS[*]})"
        "Snap 包管理器工具 (${!SNAP_TOOLS[*]})"
    )

    INSTALL_FUNCS=()
    UNINSTALL_FUNCS=()
    local selections_input

    if [ "$NON_INTERACTIVE" = true ]; then
        selections_input=($SELECTIONS_CMD)
    else
        echo -e "${YELLOW}请输入数字选择一个或多个类别 (例如: 1 3 4), 或输入 'all' 操作所有工具:${NC}"
        for i in "${!options[@]}"; do
            echo -e "  ${CYAN}${BOLD}$((i+1)))${NC} ${options[$i]}"
        done
        echo
        read -p "$(echo -e "${YELLOW}${BOLD}你的选择是: ${NC}")" -a selections_input
    fi

    if [[ " ${selections_input[*]} " =~ " all " ]] || [[ " ${selections_input[*]} " =~ " ALL " ]]; then
        selections_input=("1" "2" "3" "4" "5" "6")
    fi
    
    for choice in "${selections_input[@]}"; do
        case $choice in
            1) INSTALL_FUNCS+=("install_binary_tools"); UNINSTALL_FUNCS+=("uninstall_binary_tools");;
            2) INSTALL_FUNCS+=("install_go_tools"); UNINSTALL_FUNCS+=("uninstall_go_tools");;
            3) INSTALL_FUNCS+=("install_python_tools"); UNINSTALL_FUNCS+=("uninstall_python_tools");;
            4) INSTALL_FUNCS+=("install_git_clone_tools"); UNINSTALL_FUNCS+=("uninstall_git_clone_tools");;
            5) INSTALL_FUNCS+=("install_apt_tools"); UNINSTALL_FUNCS+=("uninstall_apt_tools");;
            6) INSTALL_FUNCS+=("install_snap_tools"); UNINSTALL_FUNCS+=("uninstall_snap_tools");;
            *) log_warn "无效的选择: $choice, 将被忽略";;
        esac
    done

    local funcs_to_run=(${INSTALL_FUNCS[@]})
    if [ ${#funcs_to_run[@]} -eq 0 ]; then log_error "未选择任何有效的操作类别，脚本退出。"; exit 1; fi
}

# Helper to populate TOOLS_TO_INSTALL based on selected categories
populate_tools_to_check() {
    TOOLS_TO_INSTALL=() # Reset the array
    for func_name in "${INSTALL_FUNCS[@]}"; do
        case "$func_name" in
            install_binary_tools) for name in "${!BINARY_TOOLS[@]}"; do TOOLS_TO_INSTALL+=("$name"); done ;;
            install_go_tools) 
                for name in "${!GO_INSTALL_TOOLS[@]}"; do TOOLS_TO_INSTALL+=("$name"); done 
                # Add gf-patterns and gf-examples to the list if gf is selected
                if [[ " ${TOOLS_TO_INSTALL[*]} " =~ " gf " ]]; then
                    TOOLS_TO_INSTALL+=("gf-patterns" "gf-examples")
                fi
                ;;
            install_python_tools) for name in "${!PIPX_TOOLS[@]}"; do TOOLS_TO_INSTALL+=("$name"); done ;;
            install_git_clone_tools) 
                for name in "${!GIT_CLONE_TOOLS[@]}"; do 
                    IFS='|' read -r _ _ _ binary_name <<< "${GIT_CLONE_TOOLS[$name]}"
                    binary_name=${binary_name:-$name}
                    TOOLS_TO_INSTALL+=("$binary_name")
                done 
                ;;
            install_apt_tools) for name in "${!APT_TOOLS[@]}"; do TOOLS_TO_INSTALL+=("$name"); done ;;
            install_snap_tools) for name in "${!SNAP_TOOLS[@]}"; do TOOLS_TO_INSTALL+=("$name"); done ;;
        esac
    done
    # Remove duplicates and sort for consistent reporting order
    TOOLS_TO_INSTALL=($(printf "%s\n" "${TOOLS_TO_INSTALL[@]}" | sort -u))
}


# 依赖检查与自动安装
dependency_check_and_install() {
    print_step "检查并安装基础依赖"
    
    # 确保网络连接正常
    if ! check_internet_connection; then
        log_error "网络连接失败，无法继续安装依赖。请检查网络后重试。"
        exit 1
    fi

    log_progress "更新APT包列表..."
    local retry_count=3
    local current_retry=0
    while ! _run_and_log "sudo apt-get update -y"; do
        current_retry=$((current_retry + 1))
        if [ "$current_retry" -ge "$retry_count" ]; then
            log_error "APT包列表更新失败，已达到最大重试次数。请检查网络或APT源配置。"
            exit 1
        fi
        log_warn "APT包列表更新失败，正在重试 ($current_retry/$retry_count)..."
        sleep 5 # 等待5秒后重试
    done
    log_success "APT包列表更新完成。"
    
    # 增加对Python开发依赖和构建工具的检查
    local commands_to_check=("git" "curl" "wget" "unzip" "python3" "pipx" "go" "sudo" "apt-get" "snap" "jq" "build-essential" "python3-dev" "python3-venv")
    local has_error=false

    for cmd in "${commands_to_check[@]}"; do
        # Use a more reliable check for Go and Pipx which might not be in the default PATH yet
        local cmd_path=""
        if [[ "$cmd" == "go" ]]; then cmd_path="/usr/local/go/bin/go"; fi
        if [[ "$cmd" == "pipx" ]]; then cmd_path="$HOME/.local/bin/pipx"; fi

        if command -v "$cmd" >/dev/null 2>&1 || [ -f "$cmd_path" ]; then
            log_info "依赖存在: $cmd"
            continue
        fi

        log_warn "依赖缺失: $cmd，正在尝试自动安装..."
        case "$cmd" in
            go)
                log_progress "正在安装 Go..."
                local go_arch; go_arch=$(uname -m)
                case $go_arch in x86_64) go_arch="amd64" ;; aarch64) go_arch="arm64" ;; *) log_error "不支持的架构: $go_arch for Go"; has_error=true; continue ;; esac
                
                log_progress "正在从 go.dev 获取最新的 Go 版本信息..."
                local go_filename
                # 完全依赖 jq 获取版本
                if ! command -v jq >/dev/null 2>&1; then
                    log_error "jq 未安装，无法可靠地获取 Go 版本。请手动安装 jq 或检查依赖安装流程。"
                    has_error=true
                    continue
                fi
                go_filename=$(curl -m 10 --silent 'https://go.dev/dl/?mode=json' | jq -r '.[0].files[] | select(.os=="linux" and .arch=="'"${go_arch}"'") | .filename' | head -1)
                
                if [ -z "$go_filename" ]; then log_error "无法解析最新的Go文件名。请检查网络或 go.dev 页面结构。"; has_error=true; continue; fi
                
                local go_url="https://go.dev/dl/${go_filename}"
                log_info "找到最新的 Go 下载链接: $go_url"
                
                if ! _run_and_log "wget -q --show-progress -O \"$go_filename\" \"$go_url\""; then log_error "下载Go失败。"; has_error=true; continue; fi
                
                if [ -d "/usr/local/go" ]; then _run_and_log "sudo rm -rf /usr/local/go"; fi
                if ! _run_and_log "sudo tar -C /usr/local -xzf \"$go_filename\""; then log_error "解压Go失败。"; has_error=true; continue; fi
                
                log_success "Go 安装成功。"
                rm "$go_filename"
                ;;
            pipx)
                log_progress "正在安装 pipx..."
                if ! _run_and_log "sudo apt-get install -y pipx"; then
                    log_warn "使用 apt 安装 pipx 失败, 尝试使用 pip (用户模式)..."
                    if ! command -v pip3 >/dev/null 2>&1; then
                        if ! _run_and_log "sudo apt-get install -y python3-pip"; then log_error "安装python3-pip失败。"; has_error=true; continue; fi
                    fi
                    if ! _run_and_log "python3 -m pip install --user pipx"; then log_error "使用 pip 安装 pipx 失败。"; has_error=true; continue; fi
                fi
                
                if ! _run_and_log "$HOME/.local/bin/pipx ensurepath"; then
                    log_warn "pipx ensurepath 命令执行失败，可能需要手动将 ~/.local/bin 添加到 PATH。请确保您已重启终端或 'source ~/.bashrc' (或 ~/.zshrc)。"
                fi
                log_success "pipx 安装成功。"
                ;;
            snap)
                log_progress "正在安装 snapd..."
                if ! _run_and_log "sudo apt-get install -y snapd"; then log_error "安装snapd失败。"; has_error=true; continue; fi
                log_success "snapd 安装成功。"
                ;;
            git|curl|wget|unzip|python3|jq|build-essential|python3-dev|python3-venv) # Added new dependencies here
                if ! _run_and_log "sudo apt-get install -y $cmd"; then log_error "安装 $cmd 失败。"; has_error=true; continue; fi
                log_success "$cmd 安装成功。"
                ;;
            *)
                log_error "无法自动安装关键依赖: $cmd"
                has_error=true
                ;;
        esac
    done

    if [ "$has_error" = true ]; then
        log_error "部分基础依赖自动安装失败，请检查上述错误后重试。"
        exit 1
    fi
    log_success "所有基础依赖都已准备就绪。"
}


setup_environment() {
    print_step "创建工作环境"
    TEMP_DIR=$(mktemp -d)
    LOG_FILE="$TEMP_DIR/install.log"
    touch "$LOG_FILE"
    log_info "临时目录: $TEMP_DIR"
    log_info "日志文件: $LOG_FILE"
    trap cleanup EXIT INT TERM
    cd "$TEMP_DIR" || { log_error "无法进入临时目录"; exit 1; }
}

cleanup() {
    cd - >/dev/null 2>&1
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log_progress "清理临时文件..."
        rm -rf "$TEMP_DIR"
        log_info "清理完成。"
    fi
}

# --- 核心安装/卸载逻辑 ---

_run_and_log() {
    local cmd_output_stdout
    local cmd_output_stderr
    local exit_code

    # 使用进程替换捕获 stdout 和 stderr
    exec 3>&1 # 将 fd 3 重定向到 stdout
    cmd_output_stdout=$( { cmd_output_stderr=$(eval "$@" 2>&1 >&3); } 2>&1 ) # 捕获 stderr 到 cmd_output_stderr，stdout 到 cmd_output_stdout
    exec 3>&- # 关闭 fd 3
    exit_code=$?

    echo "--- Running command: $@ ---" >> "$LOG_FILE"
    echo "--- STDOUT ---" >> "$LOG_FILE"
    echo "$cmd_output_stdout" >> "$LOG_FILE"
    echo "--- STDERR ---" >> "$LOG_FILE"
    echo "$cmd_output_stderr" >> "$LOG_FILE"
    echo "--- Exit code: $exit_code ---" >> "$LOG_FILE"

    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}--- 命令失败: $@ ---${NC}" >&2
        echo -e "${RED}--- 错误详情 (请查看完整日志文件: $LOG_FILE) ---${NC}" >&2
        if [ -n "$cmd_output_stderr" ]; then
            echo "$cmd_output_stderr" | tail -n 10 >&2 # 只显示 stderr 的最后10行
        elif [ -n "$cmd_output_stdout" ]; then
            echo "$cmd_output_stdout" | tail -n 10 >&2 # 如果没有 stderr，显示 stdout 的最后10行
        fi
        echo -e "${RED}--------------------------------------------------${NC}" >&2
    fi
    return $exit_code
}


## --- 通用安装函数 ---
install_go_env() {
    print_step "配置Go开发环境"
    if ! [ -f "/usr/local/go/bin/go" ]; then log_error "Go is not installed. Please install it first."; return 1; fi
    log_info "当前Go版本: $(/usr/local/go/bin/go version)"
    for line in "${GO_PATH_EXPORTS[@]}"; do
        if ! grep -qF -- "$line" "$HOME/.bashrc"; then echo "$line" >> "$HOME/.bashrc"; fi
        if [ -f "$HOME/.zshrc" ] && ! grep -qF -- "$line" "$HOME/.zshrc"; then echo "$line" >> "$HOME/.zshrc"; fi
    done
    # 立即应用环境变量，但提醒用户重启终端
    eval "$(printf "%s;" "${GO_PATH_EXPORTS[@]}")"
    mkdir -p "$GOPATH_DIR" # 确保GOPATH目录存在
    mkdir -p "$GO_BIN_DIR" # 确保GOPATH/bin目录存在
    log_success "Go环境配置完成。请重启终端或 source ~/.bashrc 使其生效。"
}

# Setup gf patterns and examples with retries
setup_gf_patterns() {
    print_step "配置 gf 模式和示例"
    mkdir -p "$GF_CONFIG_DIR" # Ensure ~/.gf exists

    local git_retry_count=3
    local git_current_retry=0
    local clone_success=false

    # Install Gf-Patterns
    local gf_patterns_repo="https://github.com/1ndianl33t/Gf-Patterns.git"
    local gf_patterns_dir="$HOME/Gf-Patterns-temp" # Use a temporary clone dir to avoid conflicts
    
    if [ -d "$gf_patterns_dir" ]; then
        log_warn "检测到旧的 Gf-Patterns 临时目录，正在删除..."
        rm -rf "$gf_patterns_dir"
    fi

    log_progress "正在克隆 Gf-Patterns 仓库..."
    clone_success=false
    git_current_retry=0
    while [ "$git_current_retry" -lt "$git_retry_count" ]; do
        if _run_and_log "git clone ${PROXY_URL}${gf_patterns_repo} $gf_patterns_dir"; then
            clone_success=true
            break
        else
            git_current_retry=$((git_current_retry + 1))
            if [ "$git_current_retry" -lt "$git_retry_count" ]; then
                log_warn "克隆 Gf-Patterns 失败，正在重试 ($git_current_retry/$git_retry_count)..."
                sleep 5
            fi
        fi
    done

    if [ "$clone_success" = true ]; then
        log_progress "正在复制 Gf-Patterns 到 ${GF_CONFIG_DIR}..."
        if _run_and_log "cp -f \"$gf_patterns_dir\"/*.json \"$GF_CONFIG_DIR\"/"; then
            log_success "Gf-Patterns 模式安装成功。"
        else
            log_error "复制 Gf-Patterns 模式失败。"
        fi
        rm -rf "$gf_patterns_dir" # Clean up temporary clone
    else
        log_error "克隆 Gf-Patterns 仓库失败，已达到最大重试次数。"
    fi

    # Install gf examples
    local gf_examples_repo="https://github.com/tomnomnom/gf.git"
    local gf_examples_dir="$HOME/gf-examples-temp" # Use a temporary clone dir
    
    if [ -d "$gf_examples_dir" ]; then
        log_warn "检测到旧的 gf 示例临时目录，正在删除..."
        rm -rf "$gf_examples_dir"
    fi

    log_progress "正在克隆 gf 示例仓库..."
    clone_success=false
    git_current_retry=0
    while [ "$git_current_retry" -lt "$git_retry_count" ]; do
        if _run_and_log "git clone ${PROXY_URL}${gf_examples_repo} $gf_examples_dir"; then
            clone_success=true
            break
        else
            git_current_retry=$((git_current_retry + 1))
            if [ "$git_current_retry" -lt "$git_retry_count" ]; then
                log_warn "克隆 gf 示例失败，正在重试 ($git_current_retry/$git_retry_count)..."
                sleep 5
            fi
        fi
    done

    if [ "$clone_success" = true ]; then
        log_progress "正在复制 gf 示例到 ${GF_CONFIG_DIR}..."
        # Ensure the examples directory within .gf exists
        mkdir -p "${GF_CONFIG_DIR}/examples"
        if _run_and_log "cp -r \"$gf_examples_dir\"/examples/* \"$GF_CONFIG_DIR\"/examples/"; then
            log_success "gf 示例安装成功。"
        else
            log_error "复制 gf 示例失败。"
        fi
        rm -rf "$gf_examples_dir" # Clean up temporary clone
    else
        log_error "克隆 gf 示例仓库失败，已达到最大重试次数。"
    fi
}


_install_binary_tool() {
    local name="$1"; local repo_info="$2"
    IFS='|' read -r repo url_pattern binary_name <<< "$repo_info"; binary_name=${binary_name:-$name}
    
    if command -v "$binary_name" >/dev/null 2>&1; then 
        log_skip "$name"
        return 0
    fi
    
    log_install "$name"
    
    api_url="https://api.github.com/repos/$repo/releases/latest"
    # 完全依赖 jq 获取版本
    version=$(curl -m 10 --silent "${PROXY_URL}${api_url}" | jq -r '.tag_name' | sed 's/^v//')
    
    if [ -z "$version" ]; then log_error "无法获取 ${name} (${repo}) 的最新版本号。"; return 1; fi
    log_progress "检测到 ${name} 最新版本: ${version}"
    
    arch=$(uname -m); arch_full=$arch
    case $arch in x86_64) arch_alias="amd64" ;; aarch64) arch_alias="arm64" ;; *) log_error "不支持的架构: $arch for $name"; return 1 ;; esac
    
    url=$(echo "$url_pattern" | sed "s/{{version}}/$version/g" | sed "s/{{arch}}/$arch_alias/g" | sed "s/{{arch_full}}/$arch_full/g")
    download_url="${PROXY_URL}${url}"; filename=$(basename "$url")
    
    if ! wget -q --show-progress --timeout=60 --connect-timeout=20 -O "$filename" "$download_url"; then 
        log_error "下载失败: $name from $download_url"
        return 1
    fi
    
    log_progress "解压并安装 $name..."
    local extract_success=false
    case "$filename" in 
        *.zip) unzip -o "$filename" -d . >> "$LOG_FILE" 2>&1 && extract_success=true ;; 
        *.tar.gz|*.tgz) tar -xzf "$filename" >> "$LOG_FILE" 2>&1 && extract_success=true ;; 
        *) log_error "未知压缩格式: $filename";; 
    esac

    if [ "$extract_success" != true ]; then
        log_error "解压 $name 失败。"
        rm -rf "$filename" # 清理下载的文件
        return 1
    fi
    
    binary_path=$(find . -maxdepth 2 -type f -name "$binary_name" | head -n 1) # 增加 maxdepth 限制搜索深度
    if [ -z "$binary_path" ]; then 
        log_error "解压后未找到二进制文件: $binary_name"
        rm -rf "$filename" ./*${name}* ./*${repo##*/}* LICENSE* README* # 确保清理解压后的文件
        return 1 
    fi
    
    # 如果二进制文件不在当前目录，移动过来并检查是否成功
    if [ ! -f "$binary_name" ]; then 
        if ! mv "$binary_path" .; then
            log_error "移动解压后的二进制文件 $binary_path 到当前目录失败。"
            rm -rf "$filename" ./*${name}* ./*${repo##*/}* LICENSE* README*
            return 1
        fi
    fi
    
    # 确保目标目录存在并移动二进制文件，检查是否成功
    sudo mkdir -p "/usr/local/bin/"
    if ! sudo mv "$binary_name" "/usr/local/bin/"; then
        log_error "移动二进制文件 $binary_name 到 /usr/local/bin/ 失败。"
        rm -rf "$filename" ./*${name}* ./*${repo##*/}* LICENSE* README*
        return 1
    fi
    sudo chmod +x "/usr/local/bin/$binary_name"
    # Verify executable permission
    if [ ! -x "/usr/local/bin/$binary_name" ]; then
        log_error "设置 ${binary_name} 可执行权限失败。"
        return 1
    fi
    
    log_success "$name 安装成功。"
    # 清理下载和解压的临时文件
    rm -rf "$filename" ./*${name}* ./*${repo##*/}* LICENSE* README*
    return 0 # 返回成功
}


install_binary_tools() {
    print_step "安装Go二进制工具 (串行)"
    for name in "${!BINARY_TOOLS[@]}"; do
        _install_binary_tool "$name" "${BINARY_TOOLS[$name]}" || true # 允许单个工具失败，不中断整个循环
    done
}


install_go_tools() { 
    print_step "安装Go源码工具"
    for name in "${!GO_INSTALL_TOOLS[@]}"; do 
        if command -v "$name" >/dev/null 2>&1 && [ -f "$GO_BIN_DIR/$name" ]; then 
            log_skip "$name"
        else 
            log_install "$name"
            # 确保在执行go install时，GOPATH和PATH是正确的
            if _run_and_log "PATH=$PATH:$GO_BIN_DIR:/usr/local/go/bin GOPATH=$GOPATH_DIR /usr/local/go/bin/go install ${GO_INSTALL_TOOLS[$name]}"; then
                log_success "$name 安装成功。"
                # If gf is installed successfully, set up its patterns and examples
                if [ "$name" == "gf" ]; then
                    setup_gf_patterns
                fi
            else 
                log_error "$name 安装失败。"
            fi
        fi
    done
}

install_python_tools() { 
    print_step "安装Python工具 (pipx)"
    for name in "${!PIPX_TOOLS[@]}"; do 
        if $HOME/.local/bin/pipx list 2>/dev/null | grep -q "$name"; then 
            log_skip "$name"
        else 
            log_install "$name"
            if _run_and_log "$HOME/.local/bin/pipx install ${PIPX_TOOLS[$name]}"; then
                log_success "$name 安装成功。"
                # Explicitly ensure pipx paths are updated after installation of a tool
                log_progress "正在更新 pipx 环境路径..."
                if ! _run_and_log "$HOME/.local/bin/pipx ensurepath"; then
                    log_warn "pipx ensurepath 命令执行失败，可能需要手动将 ~/.local/bin 添加到 PATH。请确保您已重启终端或 'source ~/.bashrc' (或 ~/.zshrc)。"
                fi
            else 
                log_error "$name 安装失败。"
            fi
        fi
    done
}

install_git_clone_tools() { 
    print_step "安装Python Git工具"
    for name in "${!GIT_CLONE_TOOLS[@]}"; do 
        IFS='|' read -r repo install_dir entry_point binary_name <<< "${GIT_CLONE_TOOLS[$name]}"
        binary_name=${binary_name:-$name}
        if [ -f "/usr/local/bin/$binary_name" ]; then 
            log_skip "$name"
            continue
        fi
        log_install "$name"
        if [ -d "$install_dir" ]; then
            log_warn "检测到旧的安装目录 ${install_dir}，正在删除..."
            sudo rm -rf "$install_dir"
        fi
        if ! _run_and_log "sudo git clone https://github.com/${repo}.git $install_dir"; then 
            log_error "${name} 克隆失败。"
            continue
        fi
        if [ -f "${install_dir}/requirements.txt" ]; then 
            log_progress "正在为 ${name} 安装Python依赖..."
            if ! _run_and_log "sudo python3 -m pip install --break-system-packages -r ${install_dir}/requirements.txt"; then 
                log_error "${name} 依赖安装失败。"
                sudo rm -rf "$install_dir" # 清理失败的安装
                continue
            fi
        fi
        # 确保软链接创建成功
        if ! sudo ln -s "${install_dir}/${entry_point}" "/usr/local/bin/${binary_name}"; then
            log_error "创建 ${name} 的软链接失败。"
            sudo rm -rf "$install_dir"
            continue
        fi
        sudo chmod +x "${install_dir}/${entry_point}"
        log_success "${name} 安装成功。"
    done
}

install_apt_tools() { 
    print_step "安装系统工具 (APT)"
    for name in "${!APT_TOOLS[@]}"; do 
        if command -v "$name" >/dev/null 2>&1; then 
            log_skip "$name"
        else 
            log_install "$name"
            local apt_retry_count=3
            local apt_current_retry=0
            local install_success=false
            while [ "$apt_current_retry" -lt "$apt_retry_count" ]; do
                if _run_and_log "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${APT_TOOLS[$name]}"; then
                    log_success "$name 安装成功。"
                    install_success=true
                    break
                else 
                    apt_current_retry=$((apt_current_retry + 1))
                    if [ "$apt_current_retry" -lt "$apt_retry_count" ]; then
                        log_warn "$name 安装失败，正在重试 ($apt_current_retry/$apt_retry_count)..."
                        sleep 5
                    fi
                fi
            done
            if [ "$install_success" = false ]; then
                log_error "$name 安装失败，已达到最大重试次数。"
            fi
        fi
    done
}

install_snap_tools() { 
    print_step "安装Snap工具"
    for name in "${!SNAP_TOOLS[@]}"; do 
        if snap list 2>/dev/null | grep -q "$name"; then 
            log_skip "$name"
        else 
            log_install "$name"
            if _run_and_log "sudo snap install ${SNAP_TOOLS[$name]}"; then
                log_success "$name 安装成功。"
            else 
                log_error "$name 安装失败。"
            fi
        fi
    done
}


## --- 卸载函数 ---
uninstall_go_env() {
    print_step "清理Go环境变量"
    local config_files=("$HOME/.bashrc" "$HOME/.zshrc")
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            log_progress "正在从 $file 移除Go环境变量..."
            local modified=false
            for line in "${GO_PATH_EXPORTS[@]}"; do
                if grep -qF -- "$line" "$file"; then
                    sed -i "/^$(echo "$line" | sed 's/[\/&]/\\&/g')$/d" "$file"
                    modified=true
                fi
            done
            if [ "$modified" = true ]; then
                log_success "Go环境变量已从 $file 移除。"
            else
                log_info "Go环境变量未在 $file 中找到，无需移除。"
            fi
        fi
    done
    if [ -d "$GOPATH_DIR" ]; then
        log_progress "正在删除 GOPATH 目录: $GOPATH_DIR..."
        rm -rf "$GOPATH_DIR"
        log_success "GOPATH 目录已删除。"
    fi
    if [ -d "/usr/local/go" ]; then
        log_progress "正在删除 Go 安装目录: /usr/local/go..."
        sudo rm -rf "/usr/local/go"
        log_success "Go 安装目录已删除。"
    fi
}

# Uninstall gf patterns and examples
uninstall_gf_patterns() {
    print_step "清理 gf 模式和示例"
    if [ -d "$GF_CONFIG_DIR" ]; then
        log_progress "正在删除 gf 配置目录: ${GF_CONFIG_DIR}..."
        rm -rf "$GF_CONFIG_DIR"
        log_success "gf 配置目录已删除。"
    else
        log_info "gf 配置目录 ${GF_CONFIG_DIR} 不存在，无需清理。"
    fi
    if [ -d "$HOME/Gf-Patterns-temp" ]; then
        log_progress "正在删除旧的 Gf-Patterns 临时目录..."
        rm -rf "$HOME/Gf-Patterns-temp"
        log_success "Gf-Patterns 临时目录已删除。"
    fi
    if [ -d "$HOME/gf-examples-temp" ]; then
        log_progress "正在删除旧的 gf 示例临时目录..."
        rm -rf "$HOME/gf-examples-temp"
        log_success "gf 示例临时目录已删除。"
    fi
}

uninstall_binary_tools() { print_step "卸载Go二进制工具"; for name in "${!BINARY_TOOLS[@]}"; do IFS='|' read -r _ _ binary_name <<< "${BINARY_TOOLS[$name]}"; binary_name=${binary_name:-$name}; if command -v "$binary_name" >/dev/null 2>&1; then log_uninstall "$binary_name"; sudo rm -f "/usr/local/bin/$binary_name"; log_success "${binary_name} 卸载成功。"; else log_skip "$binary_name"; fi; done; }
uninstall_go_tools() { print_step "卸载Go源码工具"; for name in "${!GO_INSTALL_TOOLS[@]}"; do if [ -f "$GO_BIN_DIR/$name" ]; then log_uninstall "$name"; rm -f "$GO_BIN_DIR/$name"; log_success "${name} 卸载成功。"; else log_skip "$name"; fi; done; uninstall_go_env; uninstall_gf_patterns; } # Added uninstall_gf_patterns
uninstall_python_tools() { print_step "卸载Python工具 (pipx)"; for name in "${!PIPX_TOOLS[@]}"; do if $HOME/.local/bin/pipx list 2>/dev/null | grep -q "$name"; then log_uninstall "$name"; $HOME/.local/bin/pipx uninstall "$name" >> "$LOG_FILE" 2>&1; log_success "${name} 卸载成功。"; else log_skip "$name"; fi; done; }
uninstall_git_clone_tools() { print_step "卸载Python Git工具"; for name in "${!GIT_CLONE_TOOLS[@]}"; do IFS='|' read -r _ install_dir _ binary_name <<< "${GIT_CLONE_TOOLS[$name]}"; binary_name=${binary_name:-$name}; if [ -f "/usr/local/bin/$binary_name" ]; then log_uninstall "$name"; sudo rm -f "/usr/local/bin/$binary_name"; sudo rm -rf "$install_dir"; log_success "${name} 卸载成功。"; else log_skip "$name"; fi; done; }
uninstall_apt_tools() { print_step "卸载系统工具 (APT)"; for name in "${!APT_TOOLS[@]}"; do if command -v "$name" >/dev/null 2>&1; then log_uninstall "$name"; sudo apt-get remove --purge -y "$name" >> "$LOG_FILE" 2>&1; log_success "${name} 卸载成功。"; else log_skip "$name"; fi; done; }
uninstall_snap_tools() { print_step "卸载Snap工具"; for name in "${!SNAP_TOOLS[@]}"; do if snap list 2>/dev/null | grep -q "$name"; then log_uninstall "$name"; sudo snap remove "$name"; log_success "${name} 卸载成功。"; else log_skip "$name"; fi; done; }

# --- 验证与收尾 ---
verify_installation() {
    print_step "验证安装结果"
    if [ ${#TOOLS_TO_INSTALL[@]} -eq 0 ]; then
        log_warn "本次没有安装任何新工具。"
        return
    fi
    
    # all_tools_checked 现在直接使用 TOOLS_TO_INSTALL，因为它已经包含了所有用户选择的工具
    local all_tools_checked=($(printf "%s\n" "${TOOLS_TO_INSTALL[@]}" | sort -u)) 
    local installed_count=0
    local total_tools=${#all_tools_checked[@]}

    echo -e "${WHITE}${BOLD}检查本次操作的工具:${NC}"
    for tool in "${all_tools_checked[@]}"; do
        # Special handling for gf patterns and examples, as they are not executable commands
        if [[ "$tool" == "gf-patterns" ]]; then
            if [ -d "$GF_CONFIG_DIR" ] && [ "$(find "$GF_CONFIG_DIR" -maxdepth 1 -name "*.json" | wc -l)" -gt 0 ]; then
                echo -e "  ${GREEN}${CHECK_MARK}${NC} $tool"
                installed_count=$((installed_count + 1))
            else
                echo -e "  ${RED}${CROSS_MARK}${NC} $tool"
            fi
            continue # Skip further checks for gf-patterns as it's not a command
        fi
        if [[ "$tool" == "gf-examples" ]]; then
            if [ -d "${GF_CONFIG_DIR}/examples" ] && [ "$(find "${GF_CONFIG_DIR}/examples" -maxdepth 1 -type f | wc -l)" -gt 0 ]; then
                echo -e "  ${GREEN}${CHECK_MARK}${NC} $tool"
                installed_count=$((installed_count + 1))
            else
                echo -e "  ${RED}${CROSS_MARK}${NC} $tool"
            fi
            continue # Skip further checks for gf-examples as it's not a command
        fi

        if command -v "$tool" >/dev/null 2>&1 || [ -f "$GO_BIN_DIR/$tool" ]; then
            echo -e "  ${GREEN}${CHECK_MARK}${NC} $tool"
            installed_count=$((installed_count + 1))
        elif $HOME/.local/bin/pipx list 2>/dev/null | grep -q "$tool"; then
            echo -e "  ${GREEN}${CHECK_MARK}${NC} $tool (via pipx)"
            installed_count=$((installed_count + 1))
        else
            echo -e "  ${RED}${CROSS_MARK}${NC} $tool"
        fi
    done
    echo
    if [ "$installed_count" -eq "$total_tools" ]; then
        log_success "所有选择的工具都已成功安装！ ($installed_count/$total_tools)"
    else
        log_warn "部分工具安装失败或未找到。 ($installed_count/$total_tools)"
        log_warn "请检查上面的错误详情或完整的日志文件: $LOG_FILE"
    fi
}

show_completion() {
    print_title "${ROCKET} 操作完成 ${ROCKET}" "$GREEN"
    if [ "$MODE" == "install" ]; then
        echo -e "${WHITE}${BOLD}后续步骤:${NC}"
        echo -e "  ${BLUE}1.${NC} ${BOLD}请务必重启终端${NC}，或运行 ${CYAN}source ~/.bashrc${NC} (或 ~/.zshrc) 来使所有环境变量生效。"
    else
        echo -e "${GREEN}所有选择的工具都已卸载。"
    fi
    echo
    echo -e "${WHITE}${BOLD}完整的日志文件位于:${NC} ${LOG_FILE}"
    print_separator
    echo -e "${GREEN}${BOLD}${STAR} 感谢使用Security Tools Manager! ${STAR}${NC}"
    print_separator
}

# --- 主函数 ---
main() {
    # Sudo 权限检查
    if ! sudo -v; then
        log_error "您没有 sudo 权限或未正确输入密码。请确保您是 sudo 用户。"
        exit 1
    fi
    
    parse_args "$@"
    show_welcome
    show_selection_menu
    
    # Populate TOOLS_TO_INSTALL based on user selection
    populate_tools_to_check
    
    # 非交互模式下直接启用代理
    if [ "$NON_INTERACTIVE" = false ]; then
        if [ "$MODE" == "install" ]; then
            read -p "$(echo -e "${YELLOW}是否使用下载代理 (ghproxy.com)? (y/N): ${NC}")" -n 1 -r REPLY; echo
            if [[ "$REPLY" =~ ^[Yy]$ ]]; then PROXY_URL="https://ghproxy.com/"; fi
        fi
        read -p "$(echo -e "${YELLOW}${BOLD}确认执行 ${MODE^^} 操作吗? (y/N): ${NC}")" -n 1 -r REPLY; echo
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then echo "用户取消操作。"; exit 0; fi
    fi
    
    if [ -n "$PROXY_URL" ]; then log_info "已启用下载代理: ${PROXY_URL}"; fi

    setup_environment
    
    local funcs_to_run=()
    if [ "$MODE" == "install" ]; then
        dependency_check_and_install
        
        # Re-source bashrc to make sure `go` and `pipx` are in PATH for the rest of the script
        # Note: This only affects the current script's environment. User still needs to re-source their shell.
        if [ -f "$HOME/.bashrc" ]; then source "$HOME/.bashrc"; fi
        if [ -f "$HOME/.zshrc" ]; then source "$HOME/.zshrc"; fi

        print_title "${HAMMER} 开始安装过程 ${HAMMER}" "$YELLOW"
        install_go_env # Go环境配置应在Go工具安装前进行
        funcs_to_run=("${INSTALL_FUNCS[@]}")
    else
        print_title "${HAMMER} 开始卸载过程 ${HAMMER}" "$YELLOW"
        funcs_to_run=("${UNINSTALL_FUNCS[@]}")
    fi

    for func in "${funcs_to_run[@]}"; do
        $func
    done
    
    if [ "$MODE" == "install" ]; then
        verify_installation
    fi
    show_completion
}

# Run main function, passing all command line arguments to it
main "$@"
