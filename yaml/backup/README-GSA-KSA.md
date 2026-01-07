## 取得目前 gke context
kubectl config get-contexts

## 獲取並設置 context
gcloud container clusters get-credentials gke-lab-cluster --region asia-east1 --project gcp-poc-384805 

## 查看目前 gke nodes
kubectl get nodes

## 查詢是否開啟 admission webhook: 託管式 k8s 預設開啟
kubectl api-versions | grep admissionregistration

>> 回應
admissionregistration.k8s.io/v1

## 啟用 workload identity


gcloud container clusters describe gke-lab-cluster --region asia-east1 --project gcp-poc-384805 --format="value(workloadIdentityConfig.workloadPool)"
>> gcp-poc-384805.svc.id.goog

gcloud container node-pools list --cluster=gke-lab-cluster --region asia-east1 --project gcp-poc-384805 --format="value(name)" | head -n1
>> e2m-spot-pool

gcloud container node-pools describe e2m-spot-pool --cluster=gke-lab-cluster --region asia-east1 --project gcp-poc-384805 --format="value(config.workloadMetadataConfig.mode)"

gcloud container clusters describe gke-lab-cluster --region asia-east1 --project gcp-poc-384805 | grep oauthScopes -A10 --color
>>
    oauthScopes:
    - https://www.googleapis.com/auth/devstorage.read_only
    - https://www.googleapis.com/auth/logging.write
    - https://www.googleapis.com/auth/monitoring
    - https://www.googleapis.com/auth/service.management.readonly
    - https://www.googleapis.com/auth/servicecontrol
    - https://www.googleapis.com/auth/trace.append


gcloud container clusters describe ecshopping-ae1  --region asia-east1 --project ecshopping | grep oauthScopes -A10 --color


```bash
# 設定環境變數
export PROJECT_ID="gcp-poc-384805"
export KEDA_GSA_NAME="keda-monitoring-gsa"

# 建立 GSA
gcloud iam service-accounts create ${KEDA_GSA_NAME} \
    --project=${PROJECT_ID} \
    --display-name="KEDA Monitoring Service Account"
```

## 授予 GSA 監控讀取權限
```bash
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${KEDA_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.viewer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${KEDA_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/pubsub.viewer"

# ROLE_NAMES="roles/monitoring.viewer roles/logging.viewer roles/pubsub.viewer"
# for ROLE_NAME in $ROLE_NAMES; do
#   gcloud projects add-iam-policy-binding $PROJECT_ID --member "serviceAccount:${KEDA_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --role "$ROLE_NAME"
# done
```

## 建立 GSA 與 KSA 的信任關係
```bash
# 設定環境變數
export KEDA_NAMESPACE="keda" # 預設安裝的命名空間
export KEDA_KSA_NAME="keda-operator" # KEDA 控制器使用的 KSA 名稱

gcloud iam service-accounts add-iam-policy-binding ${KEDA_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role="roles/iam.workloadIdentityUser" --project gcp-poc-384805 \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${KEDA_NAMESPACE}/${KEDA_KSA_NAME}]"
```

## 安裝 KEDA
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.18.2/keda-2.18.2.yaml

## 註釋 KSA
```bash
kubectl annotate serviceaccount ${KEDA_KSA_NAME} \
    --namespace ${KEDA_NAMESPACE} \
    "iam.gke.io/gcp-service-account=${KEDA_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

## 產生 Lab 環境
```bash
kubectl apply -f ./yaml/keda/php-test-files.yaml
kubectl apply -f ./yaml/keda/nginx-php-configmap.yaml
kubectl apply -f ./yaml/keda/nginx-deployment.yaml
kubectl apply -f ./yaml/keda/rule.yaml
kubectl apply -f ./yaml/keda/keda-scaledobject.yaml
```