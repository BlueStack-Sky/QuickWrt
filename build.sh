#!/usr/bin/env bash
set -euo pipefail  # 严格的安全设置

# =============================================================================
# 颜色和样式配置
# =============================================================================
readonly RED_COLOR='\033[1;31m'
readonly GREEN_COLOR='\033[1;32m'
readonly YELLOW_COLOR='\033[1;33m'
readonly BLUE_COLOR='\033[1;34m'
readonly MAGENTA_COLOR='\033[1;35m'
readonly CYAN_COLOR='\033[1;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# =============================================================================
# 全局常量定义
# =============================================================================
readonly SCRIPT_NAME="OpenWRT 构建系统"
readonly SCRIPT_VERSION="1.0.0"
readonly AUTHOR="OPPEN321"
readonly BLOG="www.kejizero.online"
readonly MIRROR="https://raw.githubusercontent.com/BlueStack-Sky/QuickWrt/refs/heads/master"
readonly SUPPORTED_ARCHITECTURES=("rockchip" "x86_64")
readonly REQUIRED_USER="zhao"

# =============================================================================
# 全局变量
# =============================================================================
GROUP_FLAG=false
START_TIME=$(date +%s)
CPU_CORES=$(( $(nproc --all) + 1 ))

# =============================================================================
# 函数定义
# =============================================================================

# 打印带颜色的消息
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${RESET}"
}

# 打印错误消息并退出
error_exit() {
    print_color "$RED_COLOR" "❌ 错误: $1"
    exit 1
}

# 打印警告消息
print_warning() {
    print_color "$YELLOW_COLOR" "⚠️  警告: $1"
}

# 打印成功消息
print_success() {
    print_color "$GREEN_COLOR" "✅ $1"
}

# 打印信息消息
print_info() {
    print_color "$BLUE_COLOR" "ℹ️  信息: $1"
}

# 验证必需的环境变量
validate_environment() {
    if [[ "$(whoami)" != "$REQUIRED_USER" ]] && [[ -z "${git_name:-}" || -z "${git_password:-}" ]]; then
        error_exit "未授权访问。请设置认证信息后再执行此脚本。"
    fi
}

# 显示使用帮助
show_usage() {
    echo -e "\n${BOLD}使用方法:${RESET}"
    echo -e "  bash $0 <version> <architecture>"
    echo -e "\n${BOLD}支持的架构:${RESET}"
    for arch in "${SUPPORTED_ARCHITECTURES[@]}"; do
        echo -e "  • ${GREEN_COLOR}$arch${RESET}"
    done
    echo -e "\n${BOLD}示例:${RESET}"
    echo -e "  bash $0 v24 x86_64"
    echo -e "  bash $0 v24 rockchip"
}

# 验证参数
validate_arguments() {
    local version="$1"
    local arch="$2"
    
    if [[ -z "$version" ]]; then
        error_exit "未指定版本号"
    fi
    
    if [[ -z "$arch" ]]; then
        error_exit "未指定目标架构"
    fi
    
    local valid_arch=false
    for supported_arch in "${SUPPORTED_ARCHITECTURES[@]}"; do
        if [[ "$arch" == "$supported_arch" ]]; then
            valid_arch=true
            break
        fi
    done
    
    if [[ "$valid_arch" == false ]]; then
        error_exit "不支持的架构: '$arch'"
    fi
}

# 显示横幅
show_banner() {
    clear
    echo -e ""
    echo -e "${BOLD}${BLUE_COLOR}╔══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}║${RESET}                       OpenWRT 自动化构建系统                     ${BOLD}${BLUE_COLOR}║${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}╠══════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}║${RESET}  🛠️   ${BOLD}开发者:${RESET} $AUTHOR                                            ${BOLD}${BLUE_COLOR}║${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}║${RESET}  🌐   ${BOLD}博客:${RESET} $BLOG                                  ${BOLD}${BLUE_COLOR}║${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}║${RESET}  💡   ${BOLD}理念:${RESET} 开源 · 定制化 · 高性能                               ${BOLD}${BLUE_COLOR}║${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}║${RESET}  📦   ${BOLD}版本:${RESET} $SCRIPT_VERSION                                                ${BOLD}${BLUE_COLOR}║${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}╠══════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}║${RESET}  🔧 ${GREEN_COLOR}构建开始:${RESET} $(date '+%Y-%m-%d %H:%M:%S')                                ${BOLD}${BLUE_COLOR}║${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}║${RESET}  ⚡ ${GREEN_COLOR}处理器核心:${RESET} $CPU_CORES 个                                           ${BOLD}${BLUE_COLOR}║${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}║${RESET}  🐧 ${GREEN_COLOR}系统用户:${RESET} $(whoami)                                               ${BOLD}${BLUE_COLOR}║${RESET}"
    echo -e "${BOLD}${BLUE_COLOR}╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
}

# 初始化构建环境
setup_build_environment() {
    if [[ "$(id -u)" == "0" ]]; then
        export FORCE_UNSAFE_CONFIGURE=1
        export FORCE=1
        print_warning "以 root 权限运行，已启用强制不安全配置"
    fi
}

# 设置下载进度条
setup_curl_progress() {
    if curl --help | grep -q progress-bar; then
        CURL_OPTIONS="--progress-bar"
    else
        CURL_OPTIONS="--silent"
    fi
    export CURL_OPTIONS
}

# 编译脚本
compilation_script() {
    print_info "开始查询最新 OpenWRT 版本..."
    tag_version="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | sed -n '/[2-9][4-9]/p' | sed -n 1p | sed 's/v//g' | sed 's/.tar.gz//g')"
    export tag_version="$tag_version"
    print_success "检测到最新版本: $tag_version"

    print_info "开始克隆源代码仓库..."
    git -c advice.detachedHead=false clone --depth=1 --quiet https://github.com/openwrt/openwrt -b "v$tag_version"
    git clone --depth=1 --quiet -b openwrt-24.10 https://github.com/immortalwrt/immortalwrt
    git clone --depth=1 --quiet -b openwrt-24.10 https://github.com/openwrt/openwrt openwrt_snap

    print_info "正在进行源代码处理..."
    find openwrt/package/* -maxdepth 0 ! -name 'firmware' ! -name 'kernel' ! -name 'base-files' ! -name 'Makefile' -exec rm -rf {} +
    rm -rf ./openwrt_snap/package/firmware ./openwrt_snap/package/kernel ./openwrt_snap/package/base-files ./openwrt_snap/package/Makefile
    cp -rf ./openwrt_snap/package/* ./openwrt/package/
    cp -rf ./openwrt_snap/feeds.conf.default ./openwrt/feeds.conf.default

    print_info "为 Rockchip 架构替换 ImmortalWRT 组件以增强设备兼容性..."
    rm -rf openwrt/package/boot/{rkbin,uboot-rockchip,arm-trusted-firmware-rockchip}
    rm -rf openwrt/target/linux/rockchip
    cp -rf immortalwrt/target/linux/rockchip openwrt/target/linux/rockchip
    cp -rf immortalwrt/package/boot/uboot-rockchip openwrt/package/boot/uboot-rockchip
    cp -rf immortalwrt/package/boot/arm-trusted-firmware-rockchip openwrt/package/boot/arm-trusted-firmware-rockchip

    print_info "正在克隆 OpenBox 仓库以支持后续编译"
    git clone --depth=1 --quiet -b main https://github.com/BlueStack-Sky/OpenBox

    print_info "正在复制密钥文件..."
    if [ -d "openwrt" ]; then
        cd openwrt || { printf "%b\n" "${RED_COLOR}进入 openwrt 目录失败${RES}"; exit 1; }

        if cp -rf ../OpenBox/key.tar.gz ./key.tar.gz; then
            if tar zxf key.tar.gz; then
                rm -f key.tar.gz
                print_info "密钥已复制并解压完成"
            else
                printf "%b\n" "${RED_COLOR}解压 key.tar.gz 失败${RES}"
                exit 1
            fi
        else
            printf "%b\n" "${RED_COLOR}复制 key.tar.gz 失败${RES}"
            exit 1
        fi
    else
        printf "%b\n" "${RED_COLOR}未找到 openwrt 源码目录，下载源码失败${RES}"
        exit 1
    fi

    print_info "正在更新软件源 feeds..."
    echo -e "${BLUE_COLOR}├─ 更新软件包列表...${RESET}"
    if ./scripts/feeds update -a > /dev/null 2>&1; then
        echo -e "${GREEN_COLOR}├─ 软件包列表更新成功${RESET}"
    else
        error_exit "feeds 更新失败"
    fi
    
    echo -e "${BLUE_COLOR}├─ 安装软件包依赖...${RESET}"
    if ./scripts/feeds install -a > /dev/null 2>&1; then
        echo -e "${GREEN_COLOR}└─ 软件包依赖安装完成${RESET}"
        print_success "Feeds 更新和安装完成"
    else
        error_exit "feeds 安装失败"
    fi
    
    print_info "下载并执行构建脚本..."
    local scripts=(
        00-prepare_base.sh
        01-prepare_package.sh
        02-rockchip_target_only.sh
        02-x86_64_target_only.sh
    )

    # 下载所有脚本
    echo -e "${BLUE_COLOR}├─ 下载构建脚本...${RESET}"
    for script in "${scripts[@]}"; do
        if curl -sO "$MIRROR/scripts/$script"; then
            echo -e "${GREEN_COLOR}│   ✓ 已下载: $script${RESET}"
        else
            error_exit "下载脚本 $script 失败"
        fi
    done

    echo -e "${BLUE_COLOR}├─ 设置脚本执行权限...${RESET}"
    if chmod 0755 ./*.sh; then
        echo -e "${GREEN_COLOR}│   ✓ 权限设置完成${RESET}"
    else
        error_exit "设置脚本权限失败"
    fi

    # 执行基础准备脚本
    echo -e "${BLUE_COLOR}├─ 执行基础环境准备...${RESET}"
    local base_scripts=(
        "00-prepare_base.sh"
        "01-prepare_package.sh" 
    )

    for script in "${base_scripts[@]}"; do
        echo -e "${BLUE_COLOR}│   ├─ 执行: $script${RESET}"
        if bash "$script" > /dev/null 2>&1; then
            echo -e "${GREEN_COLOR}│   │   ✓ 完成${RESET}"
        else
            error_exit "脚本 $script 执行失败"
        fi
    done

    # 执行架构特定脚本
    echo -e "${BLUE_COLOR}├─ 执行架构特定配置...${RESET}"
    if [[ "$1" == "rockchip" ]]; then
        echo -e "${BLUE_COLOR}│   ├─ 配置 Rockchip 架构${RESET}"
        if bash 02-rockchip_target_only.sh > /dev/null 2>&1; then
            export core=arm64
            echo -e "${GREEN_COLOR}│   │   ✓ Rockchip 架构配置完成${RESET}"
            print_success "Rockchip 架构配置完成"
        else
            error_exit "Rockchip 架构配置脚本执行失败"
        fi
    elif [[ "$1" == "x86_64" ]]; then
        echo -e "${BLUE_COLOR}│   ├─ 配置 x86_64 架构${RESET}"
        if bash 02-x86_64_target_only.sh > /dev/null 2>&1; then
            export core=amd64
            echo -e "${GREEN_COLOR}│   │   ✓ x86_64 架构配置完成${RESET}"
            print_success "x86_64 架构配置完成"
        else
            error_exit "x86_64 架构配置脚本执行失败"
        fi
    fi

    # 清理临时脚本文件
    echo -e "${BLUE_COLOR}├─ 清理临时文件...${RESET}"
    if rm -f 0*-*.sh; then
        echo -e "${GREEN_COLOR}└─ ✓ 临时文件清理完成${RESET}"
    else
        print_warning "清理临时文件时出现警告，但可继续执行"
    fi

    print_success "构建环境准备完成"

    # 加载配置文件
    print_info "加载配置文件..."
    if [[ "$1" == "rockchip" ]]; then
        echo -e "${BLUE_COLOR}├─ 选择 Rockchip 架构配置${RESET}"
        if cp -rf ../OpenBox/Config/Rockchip.config ./.config; then
            echo -e "${GREEN_COLOR}└─ ✓ Rockchip 配置文件加载完成${RESET}"
            print_success "Rockchip 架构配置文件已加载"
        else
            error_exit "Rockchip 配置文件加载失败"
        fi
    elif [[ "$1" == "x86_64" ]]; then
        echo -e "${BLUE_COLOR}├─ 选择 x86_64 架构配置${RESET}"
        if cp -rf ../OpenBox/Config/X86_64.config ./.config; then
            echo -e "${GREEN_COLOR}└─ ✓ x86_64 配置文件加载完成${RESET}"
            print_success "x86_64 架构配置文件已加载"
        else
            error_exit "x86_64 配置文件加载失败"
        fi
    fi
}

# 缓存工具链
cache_toolchain() {
    print_info "下载工具链..."
    echo -e "${BLUE_COLOR}├─ 检测系统信息...${RESET}"
    
    # 检测系统信息
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo -e "${GREEN_COLOR}│   ✓ 检测到系统: $PRETTY_NAME${RESET}"
    else
        echo -e "${YELLOW_COLOR}│   ⚠ 无法检测系统信息${RESET}"
    fi
    
    echo -e "${BLUE_COLOR}├─ 下载工具链文件...${RESET}"
    local TOOLCHAIN_URL="https://github.com/BlueStack-Sky/QuickWrt/releases/download/openwrt-24.10"
    local toolchain_file="toolchain_musl_${toolchain_arch}_gcc-13.tar.zst"
    
    if curl -L ${TOOLCHAIN_URL}/${toolchain_file} -o toolchain.tar.zst ${CURL_OPTIONS}; then
        echo -e "${GREEN_COLOR}│   ✓ 工具链下载完成${RESET}"
    else
        error_exit "工具链下载失败"
    fi
    
    echo -e "${BLUE_COLOR}├─ 解压工具链...${RESET}"
    if tar -I "zstd" -xf toolchain.tar.zst; then
        echo -e "${GREEN_COLOR}│   ✓ 工具链解压完成${RESET}"
    else
        error_exit "工具链解压失败"
    fi
    
    echo -e "${BLUE_COLOR}├─ 清理临时文件...${RESET}"
    if rm -f toolchain.tar.zst; then
        echo -e "${GREEN_COLOR}│   ✓ 临时文件清理完成${RESET}"
    else
        print_warning "清理临时文件时出现警告"
    fi
    
    echo -e "${BLUE_COLOR}├─ 创建目录结构...${RESET}"
    if mkdir -p bin; then
        echo -e "${GREEN_COLOR}│   ✓ 目录创建完成${RESET}"
    else
        error_exit "创建目录失败"
    fi
    
    echo -e "${BLUE_COLOR}├─ 更新文件时间戳...${RESET}"
    if find ./staging_dir/ -name '*' -exec touch {} \; >/dev/null 2>&1 && \
       find ./tmp/ -name '*' -exec touch {} \; >/dev/null 2>&1; then
        echo -e "${GREEN_COLOR}└─ ✓ 文件时间戳更新完成${RESET}"
    else
        print_warning "更新文件时间戳时出现警告"
    fi
    
    print_success "工具链缓存完成"
}

# 生成 Config 文件
generate_config_file() {
    print_info "生成 Config 文件..."
    
    echo -e "${BLUE_COLOR}├─ 清理临时目录...${RESET}"
    if [ -d tmp ]; then
        if rm -rf tmp/*; then
            echo -e "${GREEN_COLOR}│   ✓ 临时目录已清理${RESET}"
        else
            print_warning "清理临时目录时出现警告"
        fi
    else
        echo -e "${YELLOW_COLOR}│   ⚠ 未找到 tmp 目录，跳过清理${RESET}"
    fi

    echo -e "${BLUE_COLOR}├─ 执行 make defconfig...${RESET}"
    if make defconfig; then
        echo -e "${GREEN_COLOR}└─ ✓ Config 文件生成完成${RESET}"
    else
        error_exit "执行 make defconfig 失败"
    fi

    print_success "Config 文件生成完成"
}

# 开始编译
compile_openwrt() {
    starttime=`date +'%Y-%m-%d %H:%M:%S'`

    if [ "$BUILD_TOOLCHAIN" = "y" ]; then
        print_info "缓存工具链..."
        echo -e "${BLUE_COLOR}├─ 编译工具链...${RESET}"
        if make -j"$cores" toolchain/compile || make -j"$cores" toolchain/compile V=s; then
            echo -e "${GREEN_COLOR}│   ✓ 工具链编译完成${RESET}"
        else
            error_exit "工具链编译失败"
        fi

        echo -e "${BLUE_COLOR}├─ 打包工具链缓存...${RESET}"
        if mkdir -p toolchain-cache && \
           tar -I "zstd -19 -T$(nproc --all)" -cf "toolchain-cache/toolchain_musl_${toolchain_arch}_gcc-13.tar.zst" \
                ./build_dir ./dl ./staging_dir ./tmp; then
            echo -e "${GREEN_COLOR}│   ✓ 工具链缓存完成${RESET}"
        else
            error_exit "工具链缓存打包失败"
        fi

        echo -e "${GREEN_COLOR}└─ ✓ 工具链任务完成${RESET}"
        exit 0
    else
        print_info "开始编译 OpenWrt..."
        echo -e "${BLUE_COLOR}├─ 执行 make 编译...${RESET}"
        if make -j"$cores" IGNORE_ERRORS="n m"; then
            echo -e "${GREEN_COLOR}│   ✓ 编译过程完成${RESET}"
        else
            error_exit "OpenWrt 编译失败"
        fi
    fi

    # Compile time
    endtime=`date +'%Y-%m-%d %H:%M:%S'`
    start_seconds=$(date --date="$starttime" +%s)
    end_seconds=$(date --date="$endtime" +%s)
    SEC=$((end_seconds-start_seconds))

    echo -e "${BLUE_COLOR}├─ 检查编译结果...${RESET}"
    if [ -f bin/targets/*/*/sha256sums ]; then
        echo -e "${GREEN_COLOR}│   ✓ Build success! ${RESET}"
    else
        echo -e "${RED_COLOR}│   ✗ Build error... ${RESET}"
        echo -e "${BLUE_COLOR}└─ 编译耗时: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s${RESET}"
        exit 1
    fi

    echo -e "${BLUE_COLOR}└─ 编译耗时: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s${RESET}"
}

# =============================================================================
# 主程序逻辑
# =============================================================================
main() {
    local version="${1:-}"
    local architecture="${2:-}"
    
    # 参数验证
    validate_arguments "$version" "$architecture"
    
    # 显示横幅
    show_banner
    
    # 环境验证
    validate_environment
    
    # 环境设置
    setup_build_environment
    setup_curl_progress

    # 根据架构设置工具链类型
    case "$architecture" in
        rockchip)
            toolchain_arch="aarch64_generic"
            ;;
        x86_64)
            toolchain_arch="x86_64"
            ;;
    esac
    export toolchain_arch
    
    print_success "初始化完成，开始构建 $architecture 架构的 $version 版本"
    
    # 记录开始时间
    START_TIME=$(date +%s)
    
    # 执行编译脚本
    compilation_script "$architecture"

    # 缓存工具链
    cache_toolchain "$toolchain_arch"

    # 生成 Config 文件
    generate_config_file
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 如果没有提供足够的参数，显示使用帮助
    if [[ $# -lt 2 ]]; then
        show_usage
        error_exit "参数不足，需要指定版本号和目标架构"
    fi
    
    # 执行主程序
    main "$@"
fi
