#!/bin/bash
# AI生成
# KEDA 部署腳本 - 用於部署或刪除 KEDA 相關資源

set -e

# 定義顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 取得腳本所在目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 定義要部署的檔案順序
FILES=(
    "nginx-php-configmap.yaml"
    "php-test-files.yaml"
    "nginx-deployment.yaml"
    "rule.yaml"
    "keda-scaledobject.yaml"
)

# 顯示使用說明
usage() {
    echo "使用方式: $0 [apply|delete|status]"
    echo ""
    echo "選項:"
    echo "  apply   - 部署所有 KEDA 資源"
    echo "  delete  - 刪除所有 KEDA 資源"
    echo "  status  - 查看所有資源狀態"
    echo ""
    exit 1
}

# 檢查檔案是否存在
check_files() {
    echo -e "${YELLOW}檢查檔案...${NC}"
    for file in "${FILES[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$file" ]; then
            echo -e "${RED}錯誤: 找不到檔案 $file${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓${NC} $file"
    done
    echo ""
}

# 部署資源
apply_resources() {
    echo -e "${GREEN}開始部署 KEDA 資源...${NC}"
    echo ""
    
    check_files
    
    for file in "${FILES[@]}"; do
        echo -e "${YELLOW}部署: $file${NC}"
        kubectl apply -f "$SCRIPT_DIR/$file"
        echo ""
    done
    
    echo -e "${GREEN}✓ 所有資源部署完成!${NC}"
    echo ""
    echo "執行以下命令查看狀態:"
    echo "  kubectl get deployment nginx-deployment"
    echo "  kubectl get scaledobject php-fpm-scaledobject"
    echo "  kubectl get hpa"
}

# 刪除資源
delete_resources() {
    echo -e "${RED}開始刪除 KEDA 資源...${NC}"
    echo ""
    
    # 反向順序刪除
    for ((i=${#FILES[@]}-1; i>=0; i--)); do
        file="${FILES[$i]}"
        if [ -f "$SCRIPT_DIR/$file" ]; then
            echo -e "${YELLOW}刪除: $file${NC}"
            kubectl delete -f "$SCRIPT_DIR/$file" --ignore-not-found=true
            echo ""
        fi
    done
    
    echo -e "${GREEN}✓ 所有資源已刪除!${NC}"
}

# 查看資源狀態
show_status() {
    echo -e "${YELLOW}KEDA 資源狀態:${NC}"
    echo ""
    
    echo -e "${GREEN}=== Deployments ===${NC}"
    kubectl get deployment nginx-deployment -o wide 2>/dev/null || echo "未找到 deployment"
    echo ""
    
    echo -e "${GREEN}=== ScaledObjects ===${NC}"
    kubectl get scaledobject php-fpm-scaledobject 2>/dev/null || echo "未找到 scaledobject"
    echo ""
    
    echo -e "${GREEN}=== HPA (由 KEDA 創建) ===${NC}"
    kubectl get hpa 2>/dev/null || echo "未找到 HPA"
    echo ""
    
    echo -e "${GREEN}=== Pods ===${NC}"
    kubectl get pods -l app=nginx-php -o wide 2>/dev/null || echo "未找到 pods"
    echo ""
    
    echo -e "${GREEN}=== ConfigMaps ===${NC}"
    kubectl get configmap nginx-config php-test-files 2>/dev/null || echo "未找到 configmaps"
    echo ""
    
    echo -e "${GREEN}=== PrometheusRule ===${NC}"
    kubectl get prometheusrule phpfpm-rules 2>/dev/null || echo "未找到 prometheusrule"
}

# 主程式
main() {
    if [ $# -eq 0 ]; then
        usage
    fi
    
    case "$1" in
        apply)
            apply_resources
            ;;
        delete)
            delete_resources
            ;;
        status)
            show_status
            ;;
        *)
            echo -e "${RED}錯誤: 未知的選項 '$1'${NC}"
            echo ""
            usage
            ;;
    esac
}

main "$@"
