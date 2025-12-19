#!/bin/bash
# AI生成
# GKE + Google Managed Prometheus 一鍵部署腳本

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置變數（請根據實際情況修改）
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
CLUSTER_NAME="${CLUSTER_NAME:-nginx-php-cluster}"
ZONE="${GKE_ZONE:-us-central1-a}"
REGION="${GKE_REGION:-us-central1}"
NAMESPACE="${K8S_NAMESPACE:-default}"

echo -e "${GREEN}=========================================="
echo "GKE + GMP 完整部署腳本"
echo "==========================================${NC}"
echo ""
echo "配置資訊："
echo "  Project ID: $PROJECT_ID"
echo "  Cluster: $CLUSTER_NAME"
echo "  Zone: $ZONE"
echo "  Namespace: $NAMESPACE"
echo ""

# 函數：檢查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}錯誤: $1 未安裝${NC}"
        exit 1
    fi
}

# 函數：等待資源就緒
wait_for_resource() {
    local resource=$1
    local label=$2
    local timeout=${3:-300}
    
    echo -e "${YELLOW}等待 $resource 就緒...${NC}"
    kubectl wait --for=condition=ready $resource -l $label --timeout=${timeout}s || true
}

# 檢查必要工具
echo -e "${YELLOW}檢查必要工具...${NC}"
check_command gcloud
check_command kubectl
echo -e "${GREEN}✓ 工具檢查完成${NC}"
echo ""

# 步驟 1: 設置 GCP 項目
echo -e "${YELLOW}步驟 1/7: 設置 GCP 項目...${NC}"
gcloud config set project $PROJECT_ID
echo -e "${GREEN}✓ 項目設置完成${NC}"
echo ""

# 步驟 2: 創建或更新 GKE 集群
echo -e "${YELLOW}步驟 2/7: 檢查 GKE 集群...${NC}"
if gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE &> /dev/null; then
    echo "集群已存在，檢查 GMP 狀態..."
    
    # 確保 GMP 已啟用
    echo "啟用 Managed Prometheus..."
    gcloud container clusters update $CLUSTER_NAME \
        --enable-managed-prometheus \
        --zone=$ZONE || echo "GMP 可能已啟用"
else
    echo "創建新的 GKE 集群..."
    gcloud container clusters create $CLUSTER_NAME \
        --enable-managed-prometheus \
        --zone=$ZONE \
        --machine-type=e2-medium \
        --num-nodes=3 \
        --enable-autoscaling \
        --min-nodes=2 \
        --max-nodes=5 \
        --enable-autorepair \
        --enable-autoupgrade \
        --project=$PROJECT_ID
fi
echo -e "${GREEN}✓ GKE 集群就緒${NC}"
echo ""

# 步驟 3: 獲取集群憑證
echo -e "${YELLOW}步驟 3/7: 獲取集群憑證...${NC}"
gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone=$ZONE \
    --project=$PROJECT_ID
echo -e "${GREEN}✓ 憑證獲取完成${NC}"
echo ""

# 步驟 4: 驗證 GMP 組件
echo -e "${YELLOW}步驟 4/7: 驗證 GMP 組件...${NC}"
echo "檢查 gmp-system namespace..."
kubectl get namespace gmp-system &> /dev/null || kubectl create namespace gmp-system
echo "檢查 GMP Pods..."
kubectl get pods -n gmp-system
echo -e "${GREEN}✓ GMP 組件正常${NC}"
echo ""

# 步驟 5: 部署應用
echo -e "${YELLOW}步驟 5/7: 部署應用...${NC}"

# 確保在正確的 namespace
kubectl config set-context --current --namespace=$NAMESPACE

# 部署 ConfigMaps
echo "部署 ConfigMaps..."
kubectl apply -f yaml/nginx-php-configmap.yaml
kubectl apply -f yaml/php-test-files.yaml

# 部署主應用
echo "部署 Deployment 和 Services..."
kubectl apply -f yaml/nginx-deployment.yaml

# 等待 Pod 就緒
wait_for_resource "pod" "app=nginx" 300

echo -e "${GREEN}✓ 應用部署完成${NC}"
echo ""

# 步驟 6: 部署監控配置
echo -e "${YELLOW}步驟 6/7: 部署監控配置...${NC}"

# 部署 PodMonitor
echo "部署 PodMonitor..."
kubectl apply -f yaml/podmonitor.yaml

# 部署告警規則
echo "部署 PrometheusRule..."
kubectl apply -f yaml/prometheus-rules.yaml

echo -e "${GREEN}✓ 監控配置部署完成${NC}"
echo ""

# 步驟 7: 驗證部署
echo -e "${YELLOW}步驟 7/7: 驗證部署狀態...${NC}"
echo ""

echo "=== Pods 狀態 ==="
kubectl get pods -l app=nginx -o wide

echo ""
echo "=== Services 狀態 ==="
kubectl get services -l app=nginx

echo ""
echo "=== PodMonitor 狀態 ==="
kubectl get podmonitor

echo ""
echo "=== PrometheusRule 狀態 ==="
kubectl get prometheusrule

echo ""
echo -e "${GREEN}=========================================="
echo "部署完成！"
echo "==========================================${NC}"
echo ""

# 獲取訪問資訊
echo "訪問資訊："
echo ""

# LoadBalancer IP（可能需要等待）
echo -e "${YELLOW}正在獲取 LoadBalancer IP...${NC}"
EXTERNAL_IP=""
RETRY_COUNT=0
MAX_RETRIES=12

while [ -z "$EXTERNAL_IP" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    EXTERNAL_IP=$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -z "$EXTERNAL_IP" ]; then
        echo "等待 LoadBalancer IP 分配... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ -z "$EXTERNAL_IP" ]; then
    echo -e "${YELLOW}⚠ LoadBalancer IP 尚未分配${NC}"
    echo "請稍後執行查看："
    echo "  kubectl get service nginx-service"
else
    echo -e "${GREEN}✓ 外部 IP: $EXTERNAL_IP${NC}"
    echo ""
    echo "測試連結："
    echo "  - PHP 測試頁面: http://$EXTERNAL_IP/test.php"
    echo "  - 健康檢查: http://$EXTERNAL_IP/health.php"
    echo "  - PHP Info: http://$EXTERNAL_IP/index.php"
fi

echo ""
echo "監控資訊："
echo "  - Metrics Explorer: https://console.cloud.google.com/monitoring/metrics-explorer?project=$PROJECT_ID"
echo "  - Dashboards: https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo "  - Alerts: https://console.cloud.google.com/monitoring/alerting?project=$PROJECT_ID"
echo ""

# 測試指標端點
echo "測試指標端點："
POD_NAME=$(kubectl get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD_NAME" ]; then
    echo "  kubectl exec $POD_NAME -c php-fpm-exporter -- wget -qO- http://localhost:9253/metrics | grep phpfpm"
fi

echo ""
echo "查看 GMP 採集的指標（需等待 3-5 分鐘）："
echo "  gcloud monitoring time-series list \\"
echo "    --filter='metric.type=\"prometheus.googleapis.com/phpfpm_active_processes/gauge\"' \\"
echo "    --project=$PROJECT_ID \\"
echo "    --format=json"

echo ""
echo "有用的命令："
echo "  # 查看 Pod 日誌"
echo "  kubectl logs -l app=nginx -c php-fpm"
echo "  kubectl logs -l app=nginx -c php-fpm-exporter"
echo ""
echo "  # 查看 GMP collector 日誌"
echo "  kubectl logs -n gmp-system -l app.kubernetes.io/name=collector"
echo ""
echo "  # 端口轉發測試"
echo "  kubectl port-forward svc/nginx-service 8080:80"
echo "  kubectl port-forward svc/php-fpm-metrics 9253:9253"
echo ""

echo -e "${GREEN}✅ 所有步驟完成！${NC}"
