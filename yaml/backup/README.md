## 創建 GKE cluster

```bash
./startup_gke_regional.sh
```

## 安裝 KEDA
```bash
# 取得目前 gke context
kubectl config get-contexts

# 獲取並設置 context
gcloud container clusters get-credentials gke-lab-cluster --region asia-east1 --project gcp-poc-384805 

# 查看目前 gke nodes
kubectl get nodes

# 查詢是否開啟 admission webhook: 託管式 k8s 預設開啟
kubectl api-versions | grep admissionregistration

>> 回應
admissionregistration.k8s.io/v1

# 安裝 KEDA
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.18.2/keda-2.18.2.yaml

```
### 安裝完畢
- namespace keda 下出現 3 個 deployment
![KEDA 安裝完成後的 Deployment 狀態](./source/keda_installed_deployment.png)

[Deploying KEDA using the YAML files](https://keda.sh/docs/2.18/deploy/#yaml)

```bash
kubectl get pods -n keda
NAME                                      READY   STATUS    RESTARTS       AGE
keda-admission-5b8bdbf8c7-v2csv           1/1     Running   0              6m15s
keda-metrics-apiserver-85fbbf7977-knhxl   1/1     Running   0              6m15s
keda-operator-55855f6586-gxtgm            1/1     Running   1 (6m2s ago)   6m15s
```

### 安裝 resource model for Custom Metrics
```bash
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/k8s-stackdriver/master/custom-metrics-stackdriver-adapter/deploy/production/adapter_new_resource_model.yaml
```

[Custom Metrics - Stackdriver Adapter](https://github.com/GoogleCloudPlatform/k8s-stackdriver/tree/master/custom-metrics-stackdriver-adapter)


## 啟用 GKE cluster Workload Identity - 預設未啟用
```bash
export PROJECT_NAME=gke-poc
export CLUSTER_NAME=${PROJECT_NAME}-cluster
export INSTANCE_REGION=asia-east1
export PROJECT_ID=gcp-poc-384805
export NODEPOOL_NAME=e2m-spot-pool

# enable Workload Identity
gcloud container clusters update ${CLUSTER_NAME} \
    --location=${INSTANCE_REGION} --project ${PROJECT_ID} \
    --workload-pool=${PROJECT_ID}.svc.id.goog 
```

## 啟用 GKE Node Workload Identity - 預設未啟用
```bash
gcloud container node-pools update ${NODEPOOL_NAME} \
    --cluster=${CLUSTER_NAME} \
    --location=${INSTANCE_REGION} --project ${PROJECT_ID} \
    --workload-metadata=GKE_METADATA

gcloud container node-pools update e2m-spot-pool \
    --cluster=gke-lab-cluster \
    --location=asia-east1 --project gcp-poc-384805 \
    --workload-metadata=GKE_METADATA
```

[從 GKE 工作負載向 Google Cloud API 驗證身分](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/workload-identity?hl=zh-tw)


## 建立 Google Cloud Service Account (GSA)
```bash
# 設定環境變數
export PROJECT_ID="gcp-poc-384805"
export KEDA_GSA_NAME="monitoring-gsa"

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

## 註釋 KSA
```bash
kubectl annotate serviceaccount ${KEDA_KSA_NAME} \
    --namespace ${KEDA_NAMESPACE} \
    "iam.gke.io/gcp-service-account=${KEDA_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

## 重啟 KEDA 控制器 Pod
```bash
# 找到 KEDA Operator Deployment
kubectl rollout restart deployment keda-operator -n ${KEDA_NAMESPACE}
```

[Google Managed Prometheus](https://keda.sh/docs/2.18/scalers/prometheus/#example-google-managed-prometheus)


## 測試
```bash
hey -z 1m -c 10 http://<EXTERNAL-IP>

hey -z 1m -c 10 http://35.194.204.199
```


## 安裝 KEDA http add-on
```bash
kubectl apply -f https://github.com/kedacore/http-add-on/releases/download/v0.11.1/keda-add-ons-http-0.11.1.yaml
```

NOTE: 資源成本偏高，需要轉發。

[Compatibility Table](https://kedacore.github.io/http-add-on/install.html)

[Mastering Auto-Scaling with KEDA HTTP Add-on](https://medium.com/@chillcaley/mastering-auto-scaling-with-keda-http-add-on-ea3a737d2a91)

## 負載測試
```bash
cat source/load_test.txt | vegeta attack -rate=10/s -duration=30s | vegeta report
```


---

## 問題處理

```bash
# 出現錯誤
  Warning  FailedGetExternalMetric  3s (x11 over 93s)  horizontal-pod-autoscaler  unable to get external metric default/prometheus.googleapis.com|job:phpfpm_process_utilization:ratio|gauge/nil: unable to fetch metrics from external metrics API: the server could not find the requested resource (get prometheus.googleapis.com|job:phpfpm_process_utilization:ratio|gauge.external.metrics.k8s.io)

# 需確保已安裝 custom-metrics-stackdriver-adapter，否則 hpa 無法存取 external metrics
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/k8s-stackdriver/master/custom-metrics-stackdriver-adapter/deploy/production/adapter_new_resource_model.yaml

# 正常執行完 deployment 會出現，此時 hpa 應可正常存取 external metrics
 custom-metrics-stackdriver-adapter 
```

