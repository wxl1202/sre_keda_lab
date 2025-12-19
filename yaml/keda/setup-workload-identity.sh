#!/bin/bash
# AI生成
# 配置 KEDA 使用 Workload Identity 存取 GCP Monitoring API

set -e

# 定義顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 設定變數
PROJECT_ID="gcp-poc-384805"
GSA_NAME="keda-operator"
KSA_NAME="keda-operator"
NAMESPACE="keda"

echo -e "${GREEN}=== 配置 KEDA Workload Identity ===${NC}"
echo ""
echo "專案 ID: ${PROJECT_ID}"
echo "Google 服務帳戶: ${GSA_NAME}"
echo "Kubernetes 服務帳戶: ${KSA_NAME}"
echo "命名空間: ${NAMESPACE}"
echo ""

# 檢查 gcloud 認證
echo -e "${YELLOW}檢查 gcloud 認證...${NC}"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
    echo -e "${RED}錯誤: 請先執行 'gcloud auth login'${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 已認證${NC}"
echo ""

# 步驟 1: 創建 Google 服務帳戶
echo -e "${YELLOW}步驟 1/5: 創建 Google 服務帳戶...${NC}"
if gcloud iam service-accounts describe ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --project=${PROJECT_ID} &>/dev/null; then
    echo -e "${GREEN}✓ 服務帳戶已存在${NC}"
else
    gcloud iam service-accounts create ${GSA_NAME} \
        --project=${PROJECT_ID} \
        --display-name="KEDA Operator Service Account"
    echo -e "${GREEN}✓ 服務帳戶已創建${NC}"
fi
echo ""

# 步驟 2: 授予監控指標讀取權限
echo -e "${YELLOW}步驟 2/5: 授予監控權限...${NC}"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.viewer" \
    --condition=None 2>/dev/null || true
echo -e "${GREEN}✓ 已授予 roles/monitoring.viewer${NC}"
echo ""

# 步驟 3: 綁定 Workload Identity
echo -e "${YELLOW}步驟 3/5: 綁定 Workload Identity...${NC}"
gcloud iam service-accounts add-iam-policy-binding \
    ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --project=${PROJECT_ID} \
    --role=roles/iam.workloadIdentityUser \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"
echo -e "${GREEN}✓ Workload Identity 已綁定${NC}"
echo ""

# 步驟 4: 註解 Kubernetes 服務帳戶
echo -e "${YELLOW}步驟 4/5: 註解 Kubernetes 服務帳戶...${NC}"
kubectl annotate serviceaccount ${KSA_NAME} \
    -n ${NAMESPACE} \
    iam.gke.io/gcp-service-account=${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --overwrite
echo -e "${GREEN}✓ 服務帳戶已註解${NC}"
echo ""

# 步驟 5: 重啟 KEDA operator
echo -e "${YELLOW}步驟 5/5: 重啟 KEDA operator...${NC}"
kubectl rollout restart deployment keda-operator -n ${NAMESPACE}
kubectl rollout status deployment keda-operator -n ${NAMESPACE} --timeout=60s
echo -e "${GREEN}✓ KEDA operator 已重啟${NC}"
echo ""

# 驗證配置
echo -e "${GREEN}=== 驗證配置 ===${NC}"
echo ""
echo -e "${YELLOW}檢查服務帳戶註解:${NC}"
kubectl get sa ${KSA_NAME} -n ${NAMESPACE} -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' || echo "未找到註解"
echo ""
echo ""

echo -e "${YELLOW}等待 30 秒讓 KEDA 完全啟動...${NC}"
sleep 30

echo -e "${YELLOW}檢查 ScaledObject 狀態:${NC}"
kubectl get scaledobject -A
echo ""

echo -e "${GREEN}=== 配置完成! ===${NC}"
echo ""
echo "下一步："
echo "1. 等待幾分鐘讓配置生效"
echo "2. 檢查 KEDA operator 日誌："
echo "   kubectl logs -n keda -l app=keda-operator --tail=50"
echo "3. 檢查 HPA 狀態："
echo "   kubectl describe hpa keda-hpa-php-fpm-scaledobject"
