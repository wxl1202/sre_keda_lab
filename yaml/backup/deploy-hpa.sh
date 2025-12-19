#!/bin/bash
# AI生成
# HPA 自動擴展部署腳本

set -e

# 顏色定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Nginx + PHP-FPM HPA 部署腳本 ===${NC}\n"

# 檢查必要的命令
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}錯誤: $1 未安裝${NC}"
        exit 1
    fi
}

check_command kubectl
check_command jq

# 步驟 1: 檢查基礎部署
echo -e "${YELLOW}步驟 1/5: 檢查基礎部署${NC}"
if kubectl get deployment nginx-deployment &> /dev/null; then
    echo "✅ nginx-deployment 已存在"
else
    echo -e "${RED}錯誤: 請先部署 nginx-deployment${NC}"
    echo "執行: kubectl apply -f yaml/nginx-deployment.yaml"
    exit 1
fi

# 步驟 2: 檢查 Prometheus 或 GMP
echo -e "\n${YELLOW}步驟 2/5: 檢查監控系統${NC}"
echo "請選擇您的監控方式："
echo "  1) Google Managed Prometheus (GMP) - 適用於 GKE"
echo "  2) 自建 Prometheus - 適用於本地或其他 K8s"
read -p "請選擇 (1/2): " monitoring_choice

PROMETHEUS_URL=""
case $monitoring_choice in
    1)
        echo "使用 GMP，檢查 PodMonitor..."
        if kubectl get podmonitor nginx-php-podmonitor &> /dev/null; then
            echo "✅ GMP PodMonitor 已配置"
            PROMETHEUS_URL="https://monitoring.googleapis.com/v1/projects/YOUR_PROJECT_ID/location/global/prometheus"
        else
            echo -e "${YELLOW}⚠️  未找到 PodMonitor，建議執行:${NC}"
            echo "kubectl apply -f yaml/podmonitor.yaml"
        fi
        ;;
    2)
        read -p "請輸入 Prometheus 服務地址 (例如: http://prometheus.monitoring.svc:9090): " PROMETHEUS_URL
        ;;
    *)
        echo -e "${RED}無效選擇${NC}"
        exit 1
        ;;
esac

# 步驟 3: 部署 Prometheus Adapter
echo -e "\n${YELLOW}步驟 3/5: 部署 Prometheus Adapter${NC}"

# 創建 custom-metrics namespace
if ! kubectl get namespace custom-metrics &> /dev/null; then
    echo "創建 custom-metrics namespace..."
    kubectl create namespace custom-metrics
fi

# 如果提供了 Prometheus URL，更新配置
if [ ! -z "$PROMETHEUS_URL" ] && [ "$monitoring_choice" == "2" ]; then
    echo "更新 Prometheus Adapter 配置中的 Prometheus URL..."
    sed -i.bak "s|url:.*|url: $PROMETHEUS_URL|g" yaml/prometheus-adapter.yaml
    echo "✅ 已更新配置"
fi

echo "部署 Prometheus Adapter..."
kubectl apply -f yaml/prometheus-adapter.yaml

echo "等待 Prometheus Adapter 就緒..."
kubectl wait --for=condition=available --timeout=120s deployment/custom-metrics-apiserver -n custom-metrics

echo "✅ Prometheus Adapter 部署完成"

# 步驟 4: 驗證自定義指標
echo -e "\n${YELLOW}步驟 4/5: 驗證自定義指標${NC}"
sleep 10  # 等待指標註冊

echo "檢查 Custom Metrics API..."
if kubectl get apiservice v1beta1.custom.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' | grep -q "True"; then
    echo "✅ Custom Metrics API 可用"
else
    echo -e "${RED}⚠️  Custom Metrics API 未就緒${NC}"
    echo "請檢查 Prometheus Adapter 日誌："
    echo "kubectl logs -n custom-metrics deployment/custom-metrics-apiserver"
fi

echo -e "\n可用的自定義指標："
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq -r '.resources[].name' | grep phpfpm || echo "⚠️  暫無 phpfpm 指標"

# 步驟 5: 選擇並部署 HPA
echo -e "\n${YELLOW}步驟 5/5: 選擇 HPA 方案${NC}"
echo "請選擇 HPA 配置方案："
echo "  1) 基於進程利用率（推薦用於一般場景）"
echo "  2) 基於活躍進程數"
echo "  3) 混合指標（推薦用於生產環境）"
echo "  4) 基於請求隊列（推薦用於高流量場景）"
echo "  5) 基於請求率（推薦用於 API 微服務）"
echo "  6) 部署所有方案（測試用）"
read -p "請選擇 (1-6): " hpa_choice

HPA_NAME=""
case $hpa_choice in
    1)
        HPA_NAME="nginx-php-hpa-utilization"
        kubectl apply -f - <<EOF
$(sed -n '/nginx-php-hpa-utilization/,/^---$/p' yaml/hpa-custom-metrics.yaml | head -n -1)
EOF
        ;;
    2)
        HPA_NAME="nginx-php-hpa-active-processes"
        kubectl apply -f - <<EOF
$(sed -n '/nginx-php-hpa-active-processes/,/^---$/p' yaml/hpa-custom-metrics.yaml | head -n -1)
EOF
        ;;
    3)
        HPA_NAME="nginx-php-hpa-mixed"
        kubectl apply -f - <<EOF
$(sed -n '/nginx-php-hpa-mixed/,/^---$/p' yaml/hpa-custom-metrics.yaml | head -n -1)
EOF
        ;;
    4)
        HPA_NAME="nginx-php-hpa-queue"
        kubectl apply -f - <<EOF
$(sed -n '/nginx-php-hpa-queue/,/^---$/p' yaml/hpa-custom-metrics.yaml | head -n -1)
EOF
        ;;
    5)
        HPA_NAME="nginx-php-hpa-request-rate"
        kubectl apply -f - <<EOF
$(sed -n '/nginx-php-hpa-request-rate/,/^---$/p' yaml/hpa-custom-metrics.yaml | head -n -1)
EOF
        ;;
    6)
        echo "部署所有 HPA 方案..."
        kubectl apply -f yaml/hpa-custom-metrics.yaml
        HPA_NAME="所有 HPA"
        ;;
    *)
        echo -e "${RED}無效選擇${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}✅ HPA 部署完成！${NC}"

# 顯示 HPA 狀態
echo -e "\n${YELLOW}HPA 當前狀態：${NC}"
kubectl get hpa

# 提供後續操作建議
echo -e "\n${GREEN}=== 部署成功！後續操作建議 ===${NC}\n"

echo "📊 監控 HPA 狀態："
echo "  kubectl get hpa -w"
echo ""

echo "🔍 查看詳細資訊："
echo "  kubectl describe hpa $HPA_NAME"
echo ""

echo "📈 查看當前指標值："
if [ "$hpa_choice" == "1" ]; then
    echo '  kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/phpfpm_active_processes_utilization" | jq .'
elif [ "$hpa_choice" == "5" ]; then
    echo '  kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/phpfpm_request_rate" | jq .'
fi
echo ""

echo "🧪 壓力測試（觸發擴展）："
echo "  # 獲取服務地址"
echo "  SERVICE_IP=\$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  # 或對於 NodePort:"
echo "  SERVICE_IP=localhost:30080"
echo ""
echo "  # 使用 wrk 壓測"
echo "  wrk -t10 -c100 -d2m http://\$SERVICE_IP/test.php"
echo ""
echo "  # 或使用 ab"
echo "  ab -n 10000 -c 100 http://\$SERVICE_IP/test.php"
echo ""

echo "📚 詳細文檔："
echo "  yaml/HPA-GUIDE.md - HPA 完整指南"
echo "  yaml/README-GMP.md - 專案整體說明"
echo ""

echo "🔧 故障排查："
echo "  # 檢查 Prometheus Adapter 日誌"
echo "  kubectl logs -n custom-metrics deployment/custom-metrics-apiserver"
echo ""
echo "  # 檢查 HPA 事件"
echo "  kubectl get events --field-selector involvedObject.name=$HPA_NAME"
echo ""

echo -e "${GREEN}🎉 祝您擴展愉快！${NC}"
