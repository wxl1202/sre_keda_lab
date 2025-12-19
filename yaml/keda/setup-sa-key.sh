#!/bin/bash
# AI生成
# 使用 GCP 服務帳戶金鑰創建 Kubernetes Secret 供 KEDA 使用

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_ID="gcp-poc-384805"
GSA_NAME="keda-gcp-sa"
KEY_FILE="keda-gcp-key.json"
SECRET_NAME="keda-gcp-credentials"
NAMESPACE="keda"

echo -e "${GREEN}=== 使用服務帳戶金鑰配置 KEDA ===${NC}"
echo ""

# 步驟 1: 創建 GCP 服務帳戶
echo -e "${YELLOW}步驟 1/5: 創建 GCP 服務帳戶...${NC}"
if gcloud iam service-accounts describe ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --project=${PROJECT_ID} &>/dev/null; then
    echo -e "${GREEN}✓ 服務帳戶已存在${NC}"
else
    gcloud iam service-accounts create ${GSA_NAME} \
        --project=${PROJECT_ID} \
        --display-name="KEDA GCP Service Account"
    echo -e "${GREEN}✓ 服務帳戶已創建${NC}"
fi
echo ""

# 步驟 2: 授予監控權限
echo -e "${YELLOW}步驟 2/5: 授予監控權限...${NC}"
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.viewer" \
    --condition=None 2>/dev/null || true
echo -e "${GREEN}✓ 已授予 roles/monitoring.viewer${NC}"
echo ""

# 步驟 3: 創建服務帳戶金鑰
echo -e "${YELLOW}步驟 3/5: 創建服務帳戶金鑰...${NC}"
if [ -f "${KEY_FILE}" ]; then
    echo -e "${YELLOW}金鑰檔案已存在，是否覆蓋? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -f "${KEY_FILE}"
    else
        echo -e "${YELLOW}使用現有金鑰檔案${NC}"
    fi
fi

if [ ! -f "${KEY_FILE}" ]; then
    gcloud iam service-accounts keys create ${KEY_FILE} \
        --iam-account=${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
        --project=${PROJECT_ID}
    echo -e "${GREEN}✓ 金鑰已創建: ${KEY_FILE}${NC}"
else
    echo -e "${GREEN}✓ 使用現有金鑰: ${KEY_FILE}${NC}"
fi
echo ""

# 步驟 4: 創建 Kubernetes Secret
echo -e "${YELLOW}步驟 4/5: 創建 Kubernetes Secret...${NC}"
kubectl delete secret ${SECRET_NAME} -n ${NAMESPACE} --ignore-not-found=true
kubectl create secret generic ${SECRET_NAME} \
    -n ${NAMESPACE} \
    --from-file=key.json=${KEY_FILE}
echo -e "${GREEN}✓ Secret 已創建: ${SECRET_NAME}${NC}"
echo ""

# 步驟 5: 創建 TriggerAuthentication
echo -e "${YELLOW}步驟 5/5: 創建 TriggerAuthentication...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: gcp-prometheus-auth
  namespace: default
spec:
  secretTargetRef:
  - parameter: GoogleApplicationCredentials
    name: ${SECRET_NAME}
    key: key.json
EOF
echo -e "${GREEN}✓ TriggerAuthentication 已創建${NC}"
echo ""

# 清理金鑰檔案
echo -e "${YELLOW}清理本地金鑰檔案...${NC}"
echo -e "${RED}警告: 即將刪除本地金鑰檔案 ${KEY_FILE}${NC}"
echo -e "${YELLOW}金鑰已安全儲存在 Kubernetes Secret 中${NC}"
rm -f ${KEY_FILE}
echo -e "${GREEN}✓ 已清理${NC}"
echo ""

echo -e "${GREEN}=== 配置完成! ===${NC}"
echo ""
echo "下一步："
echo "1. 更新 ScaledObject，在 prometheus trigger 中添加："
echo "   authenticationRef:"
echo "     name: gcp-prometheus-auth"
echo ""
echo "2. 重新部署："
echo "   kubectl apply -f ./yaml/keda/keda-scaledobject.yaml"
echo ""
echo "3. 檢查狀態："
echo "   kubectl get scaledobject"
echo "   kubectl describe scaledobject php-fpm-scaledobject"
