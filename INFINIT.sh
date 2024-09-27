#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/infinit.sh"

# 更新系统并安装 unzip 工具
sudo apt update
sudo apt install -y unzip

# 卸载旧版 Node.js
function uninstall_old_node() {
    if command -v node &> /dev/null; then
        echo "正在卸载旧版 Node.js..."
        sudo apt remove -y nodejs
    fi
}

# 卸载功能
function uninstall() {
    echo "正在卸载 Infinit..."
    rm -rf infinit
    echo "卸载完成，所有文件已被移除。"
}

# 主菜单函数
function main_menu() {
    while true; do
        clear
        echo "==============================================================="
        echo "欢迎使用 Infinit 安装脚本！"
        echo "若需退出脚本，请按键盘 ctrl+c 进行退出"
        echo "请选择要执行的操作:"
        echo "1) 部署合约"
        echo "2) 卸载 Infinit"
        echo "3) 退出"

        read -p "请输入选择: " choice

        case $choice in
            1)
                deploy_contract
                ;;
            2)
                uninstall
                ;;
            3)
                echo "正在退出脚本..."
                exit 0
                ;;
            *)
                echo "无效选择，请重试"
                ;;
        esac
        read -n 1 -s -r -p "按任意键继续..."
    done
}

# 检查并安装命令
function check_install() {
    command -v "$1" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "$1 未安装，正在进行安装..."
        eval "$2"
    else
        echo "$1 已安装"
    fi
}

# 让用户选择 RPC URL
function select_rpc() {
    echo "请选择 RPC URL（选择数字并按 Enter 确认）:"
    PS3="请选择一个选项: "
    options=("https://1rpc.io/holesky" "https://endpoints.omniatech.io/v1/eth/holesky/public" "https://ethereum-holesky-rpc.publicnode.com")
    
    select opt in "${options[@]}"; do
        case $opt in
            "${options[0]}"|"${options[1]}"|"${options[2]}")
                echo "您选择的 RPC URL: $opt"
                sed -i "s|rpc_url: .*|rpc_url: '$opt'|" /root/infinit/src/infinit.config.yaml
                break
                ;;
            *) echo "无效选择，请重试." ;;
        esac
    done
}

# 部署合约
function deploy_contract() {
    uninstall_old_node

    # 安装 NVM 和最新的 Node.js
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash
        source "$NVM_DIR/nvm.sh"
    fi

    # 安装最新的 Node.js
    nvm install node
    nvm alias default node
    nvm use default

    echo "正在安装 Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    export PATH="$HOME/.foundry/bin:$PATH"
    sleep 5
    source ~/.bashrc
    foundryup
    
    # 检查并安装 Bun
    if ! command -v bun &> /dev/null; then
        curl -fsSL https://bun.sh/install | bash
        export PATH="$HOME/.bun/bin:$PATH"
        sleep 5
        source "$HOME/.bashrc"
    fi

    if ! command -v bun &> /dev/null; then
        echo "Bun 未安装，安装可能失败，请检查安装步骤"
        exit 1
    fi

    # 创建并初始化 Bun 项目
    mkdir -p infinit && cd infinit || exit
    bun init -y
    bun add @infinit-xyz/cli

    echo "正在初始化 Infinit CLI 并生成账户..."
    bunx infinit init
    bunx infinit account generate

    read -p "请输入您的钱包地址（请参考上面步骤中的地址） : " WALLET
    read -p "请输入您的账户 ID （在上面的步骤中输入） : " ACCOUNT_ID

    echo "请复制以下私钥并妥善保存，这是该钱包的私钥"
    bunx infinit account export $ACCOUNT_ID

    sleep 5

    # 移除旧的 deployUniswapV3Action 脚本（如果存在）
    rm -rf src/scripts/deployUniswapV3Action.script.ts

cat <<EOF > src/scripts/deployUniswapV3Action.script.ts
import { DeployUniswapV3Action, type actions } from '@infinit-xyz/uniswap-v3/actions'
import type { z } from 'zod'

type Param = z.infer<typeof actions['init']['paramsSchema']>

const params: Param = {
  "nativeCurrencyLabel": 'ETH',
  "proxyAdminOwner": '$WALLET',
  "factoryOwner": '$WALLET',
  "wrappedNativeToken": '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'
}

const signer = {
  "deployer": "$ACCOUNT_ID"
}

export default { params, signer, Action: DeployUniswapV3Action }
EOF

    # 让用户选择 RPC
    select_rpc

    echo "正在执行 UniswapV3 Action 脚本..."
    bunx infinit script execute deployUniswapV3Action.script.ts

    read -p "按任意键返回主菜单..."
}

# 启动主菜单
main_menu
