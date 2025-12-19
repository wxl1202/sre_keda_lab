# KEDA 與 GCP Managed Prometheus 整合指南

## AI生成

本指南說明如何配置 KEDA 以使用 GCP Managed Prometheus (GMP) 指標進行自動擴展。

## 重要更新

**⚠️ gcp-stackdriver scaler 已棄用**

KEDA 官方已棄用 `gcp-stackdriver`、`gcp-pubsub` 和 `gcp-cloudtasks` scalers，建議改用 **Prometheus scaler** 直接查詢 GCP Monitoring Prometheus API。

- 棄用公告：https://keda.sh/blog/2025-09-15-gcp-deprecations
- GCP 在 2024 年棄用 MQL，改用 PromQL API
- 現有 scaler 仍可使用，但強烈建議遷移

## 問題說明

當 KEDA 嘗試從 GMP 讀取指標時，需要適當的 GCP 認證。錯誤訊息：
```
google application credentials not found
```

## 解決方案

有兩種方法可以讓 KEDA 存取 GMP：

### 方案 1：使用服務帳戶金鑰（簡單方式）

**優點：**
- 設置簡單快速
- 不需要配置 Workload Identity
- 適合測試和開發環境

**缺點：**
- 需要管理金鑰檔案
- 金鑰需要定期輪換
- 安全性較 Workload Identity 低

#### 設置步驟

執行自動化腳本：
```bash
./yaml/keda/setup-sa-key.sh
```

或手動執行以下步驟：

**1. 創建 GCP 服務帳戶並授權**
```bash
export PROJECT_ID="gcp-poc-384805"
export GSA_NAME="keda-gcp-sa"

# 創建服務帳戶
gcloud iam service-accounts create ${GSA_NAME} \
    --project=${PROJECT_ID}

# 授予監控權限
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.viewer"

# 創建金鑰
gcloud iam service-accounts keys create keda-gcp-key.json \
    --iam-account=${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
```

**2. 創建 Kubernetes Secret**
```bash
kubectl create secret generic keda-gcp-credentials \
    -n keda \
    --from-file=key.json=keda-gcp-key.json

# 清理本地金鑰檔案
rm keda-gcp-key.json
```

**3. 創建 TriggerAuthentication**
```bash
kubectl apply -f - <<EOF
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: gcp-prometheus-auth
  namespace: default
spec:
  secretTargetRef:
  - parameter: GoogleApplicationCredentials
    name: keda-gcp-credentials
    key: key.json
EOF
```

**4. 使用範例配置**
```bash
kubectl apply -f ./yaml/keda/keda-scaledobject-with-sa.yaml
```

### 方案 2：使用 Workload Identity（生產環境推薦）

**優點：**
- 不需要管理金鑰
- 自動輪換憑證
- 更高的安全性
- GKE 最佳實踐

**缺點：**
- 設置相對複雜
- 需要 GKE Workload Identity 功能啟用

#### 步驟 1：創建 Google 服務帳戶

```bash
# 設定變數
export PROJECT_ID="gcp-poc-384805"
export GSA_NAME="keda-operator"
export KSA_NAME="keda-operator"
export NAMESPACE="keda"

# 創建 Google 服務帳戶
gcloud iam service-accounts create ${GSA_NAME} \
    --project=${PROJECT_ID} \
    --display-name="KEDA Operator Service Account"

# 授予監控指標讀取權限
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.viewer"

# 綁定 Workload Identity
gcloud iam service-accounts add-iam-policy-binding \
    ${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser --project ${PROJECT_ID} \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"

# 註解 Kubernetes 服務帳戶
kubectl annotate serviceaccount ${KSA_NAME} \
    -n ${NAMESPACE} \
    iam.gke.io/gcp-service-account=${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --overwrite

# 重啟 KEDA operator
kubectl rollout restart deployment keda-operator -n keda
```

#### 步驟 2：驗證配置

```bash
# 檢查服務帳戶註解
kubectl get sa -n keda keda-operator -o yaml | grep "iam.gke.io"

# 檢查 KEDA operator 日誌
kubectl logs -n keda -l app=keda-operator --tail=50
```

### 方案 2：暫時使用 CPU 觸發器（簡單方案）

如果只是測試，可以暫時只使用 CPU 觸發器，不依賴 GMP：

```yaml
# 編輯 keda-scaledobject.yaml，移除 gcp-stackdriver trigger
# 只保留 CPU trigger
```

## 指標查詢說明

### GMP 指標格式

GMP 中的 Prometheus 指標格式：
```
prometheus.googleapis.com/<metric_name>/gauge
```

範例：
- 原始 Prometheus 指標：`job:phpfpm_process_utilization:ratio`
- GMP 格式：`prometheus.googleapis.com/job:phpfpm_process_utilization:ratio/gauge`

### 過濾條件

`filter` 參數用於選擇特定的資源：
```yaml
filter: 'resource.type="k8s_pod"'
filter: 'resource.type="k8s_pod" AND resource.labels.namespace_name="default"'
```

### 完整配置範例

#### 新版本（推薦）：使用 Prometheus Scaler

```yaml
triggers:
  - type: prometheus
    metadata:
      # GCP Monitoring Prometheus API 端點
      serverAddress: https://monitoring.googleapis.com/v1/projects/gcp-poc-384805/location/global/prometheus
      # Prometheus 查詢（使用 GMP 標籤格式）
      query: '{"__name__"="prometheus.googleapis.com/job:phpfpm_process_utilization:ratio/gauge","monitored_resource"="k8s_pod"}'
      threshold: "0.7"
      activationThreshold: "0.5"
      credentialsFromEnv: GOOGLE_APPLICATION_CREDENTIALS
```

#### 舊版本（已棄用）：gcp-stackdriver

```yaml
triggers:
  - type: gcp-stackdriver  # ⚠️ 已棄用
    metadata:
      projectId: "gcp-poc-384805"
      metricType: "prometheus.googleapis.com/job:phpfpm_process_utilization:ratio/gauge"
      filter: 'resource.type="k8s_pod"'
      targetValue: "0.7"
```

## Pub/Sub backlog（subscription 長度）直接用 PromQL 查

你說得對：Pub/Sub 的 backlog 指標在 Cloud Monitoring 是「既有指標」，在 GMP/Cloud Monitoring 的 PromQL API 也能直接查詢，
不需要另外部署 exporter。

### 常用 backlog 指標

Cloud Monitoring metric type（概念名稱）：
- `pubsub.googleapis.com/subscription/num_undelivered_messages`

在 PromQL 中通常會被正規化為底線命名（常見型態）：
- `pubsub_googleapis_com_subscription_num_undelivered_messages`

### PromQL 查詢範例

1) 先不加任何 label 過濾，確認能查到資料（也用來觀察有哪些 labels）：

```promql
topk(5, pubsub_googleapis_com_subscription_num_undelivered_messages)
```

2) 加上 subscription 篩選（label 名稱請依你第 1 步回傳的 labels 為準；常見是 `subscription_id`）：

```promql
sum(
    pubsub_googleapis_com_subscription_num_undelivered_messages{subscription_id="YOUR_SUBSCRIPTION_ID"}
)
```

### 套用到 KEDA

已在 [yaml/keda/keda-scaledobject.yaml](yaml/keda/keda-scaledobject.yaml) 加上「觸發器 3」範例（Prometheus scaler）。
你只需要把 `YOUR_SUBSCRIPTION_ID` 與（必要時）label key 調整成實際值即可。

## 驗證 GMP 指標

### 檢查指標是否存在

```bash
# 使用 gcloud 查詢指標
gcloud monitoring time-series list \
    --filter='metric.type="prometheus.googleapis.com/job:phpfpm_process_utilization:ratio/gauge"' \
    --project=gcp-poc-384805 \
    --format=json

# 檢查 PodMonitoring 狀態
kubectl get podmonitoring -A
kubectl describe podmonitoring custom-metrics-exporter
```

## 故障排除

### 1. 檢查 KEDA 權限

```bash
# 查看 KEDA operator pod
kubectl get pods -n keda

# 查看日誌
kubectl logs -n keda <keda-operator-pod-name>
```

### 2. 驗證 Workload Identity

```bash
# 進入 KEDA operator pod
kubectl exec -n keda <keda-operator-pod-name> -- env | grep GOOGLE

# 測試 GCP API 存取
kubectl exec -n keda <keda-operator-pod-name> -- \
    curl -H "Metadata-Flavor: Google" \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
```

### 3. 檢查指標值

```bash
# 使用 kubectl 查看 HPA
kubectl get hpa

# 查看詳細資訊
kubectl describe hpa keda-hpa-php-fpm-scaledobject
```

## 參考資料

- [KEDA GCP Stackdriver Scaler](https://keda.sh/docs/latest/scalers/gcp-stackdriver/)
- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Google Managed Prometheus](https://cloud.google.com/stackdriver/docs/managed-prometheus)
