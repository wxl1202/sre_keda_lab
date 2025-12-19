#!/bin/bash
# AI生成
# Nginx + PHP-FPM 快速部署腳本

set -e

echo "=========================================="
echo "Nginx + PHP-FPM 部署腳本"
echo "=========================================="
echo ""

# 檢查 kubectl 是否可用
if ! command -v kubectl &> /dev/null; then
    echo "錯誤: kubectl 命令未找到，請先安裝 kubectl"
    exit 1
fi

# 檢查是否連接到 K8s 集群
if ! kubectl cluster-info &> /dev/null; then
    echo "錯誤: 無法連接到 Kubernetes 集群"
    exit 1
fi

echo "✓ Kubernetes 集群連接正常"
echo ""

# 步驟 1: 部署 ConfigMaps
echo "步驟 1/3: 部署 ConfigMaps..."
kubectl apply -f yaml/nginx-php-configmap.yaml
kubectl apply -f yaml/php-test-files.yaml
echo "✓ ConfigMaps 部署完成"
echo ""

# 步驟 2: 部署 Deployment 和 Services
echo "步驟 2/3: 部署 Deployment 和 Services..."
kubectl apply -f yaml/nginx-deployment.yaml
echo "✓ Deployment 和 Services 部署完成"
echo ""

# 步驟 3: 等待 Pod 就緒
echo "步驟 3/3: 等待 Pod 就緒..."
kubectl wait --for=condition=ready pod -l app=nginx --timeout=300s
echo "✓ Pod 已就緒"
echo ""

# 顯示部署狀態
echo "=========================================="
echo "部署狀態"
echo "=========================================="
echo ""

echo "Pods:"
kubectl get pods -l app=nginx
echo ""

echo "Services:"
kubectl get services -l app=nginx
echo ""

# 取得 LoadBalancer IP
echo "=========================================="
echo "獲取外部 IP..."
echo "=========================================="
echo ""

echo "等待 LoadBalancer 分配外部 IP（這可能需要幾分鐘）..."
EXTERNAL_IP=""
RETRY_COUNT=0
MAX_RETRIES=30

while [ -z "$EXTERNAL_IP" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    EXTERNAL_IP=$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -z "$EXTERNAL_IP" ]; then
        echo "等待中... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ -z "$EXTERNAL_IP" ]; then
    echo "⚠ 警告: LoadBalancer 尚未分配外部 IP"
    echo "請稍後使用以下命令查看: kubectl get service nginx-service"
else
    echo "✓ 外部 IP: $EXTERNAL_IP"
    echo ""
    echo "測試連結:"
    echo "  - PHP 資訊: http://$EXTERNAL_IP/index.php"
    echo "  - 基本測試: http://$EXTERNAL_IP/test.php"
    echo "  - 健康檢查: http://$EXTERNAL_IP/health.php"
fi

echo ""
echo "=========================================="
echo "部署完成！"
echo "=========================================="
