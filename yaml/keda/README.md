## 創建 GKE cluster

```bash
./startup_gke_regional.sh
```

## GKE 環境設定
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

#--- 創建 GKE 使用的 Service Account - 避免直接使用 GCE Service Account 權限
# 設定環境變數
export PROJECT_ID="gcp-poc-384805"
export GKE_GSA_NAME="gke-lab-gsa"

# 建立 GSA
gcloud iam service-accounts create ${GKE_GSA_NAME} \
    --project=${PROJECT_ID} \
    --display-name="GKE Lab Service Account"

# 列出現有 GSA 權限
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:serviceAccount:${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# 授權 GSA
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/artifactregistry.reader"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/compute.networkViewer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/opsconfigmonitoring.resourceMetadata.writer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.objectViewer"

# 另加，讓 PodMonitoring 可以存取 metrics
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.viewer" --condition=None

```   

## 啟用 GKE cluster Workload Identity - 預設未啟用
```bash
export PROJECT_NAME=gke-lab
export CLUSTER_NAME=${PROJECT_NAME}-cluster
export INSTANCE_REGION=asia-east1
export PROJECT_ID=gcp-poc-384805
export NODEPOOL_NAME=e2m-spot-pool

# enable Workload Identity
gcloud container clusters update ${CLUSTER_NAME} \
    --location=${INSTANCE_REGION} --project ${PROJECT_ID} \
    --workload-pool=${PROJECT_ID}.svc.id.goog 
```

## 啟用 GKE Node Workload Identity - 預設未啟用 - 若要指定 Service Account 就需要重建新的 node pool
```bash
gcloud container node-pools update ${NODEPOOL_NAME} \
    --cluster=${CLUSTER_NAME} \
    --location=${INSTANCE_REGION} --project ${PROJECT_ID} \
    --workload-metadata=GKE_METADATA

## 範例
gcloud container node-pools update e2m-spot-pool \
    --cluster=gke-lab-cluster \
    --location=asia-east1 --project gcp-poc-384805 \
    --workload-metadata=GKE_METADATA
```

## 創建指定 service account 的 node pool
```bash
export NEW_NODEPOOL_NAME="e2m-spot-pool-gsa"
export PROJECT_NAME=gke-lab
export CLUSTER_NAME=${PROJECT_NAME}-cluster
export INSTANCE_REGION=asia-east1
export PROJECT_ID=gcp-poc-384805
export GKE_GSA_NAME="gke-lab-gsa"

gcloud container node-pools create ${NEW_NODEPOOL_NAME} \
    --cluster=${CLUSTER_NAME} \
    --location=${INSTANCE_REGION} \
    --project=${PROJECT_ID} \
    --machine-type e2-medium \
    --service-account=${GKE_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --workload-metadata=GKE_METADATA \
    --enable-autoscaling --min-nodes 0 --max-nodes 1 \
    --spot \
    --scopes cloud-platform

# NOTE: 如果有既有的 node pool 沒有套用 service account 需要刪除。
```



# 建立一個 GSA 供 KEDA 使用
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
    --role="roles/monitoring.viewer" \
    --condition=None

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${KEDA_GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/pubsub.viewer" \
    --condition=None

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


# !!!! 注意此範例使用 workloadIdentity 進行授權給 KSA keda-operator

- 此方法不建議在 production 環境使用，建議使用上面所述 GSA + KSA

```bash
# (Ref) https://docs.cloud.google.com/kubernetes-engine/docs/how-to/workload-identity#configure-authz-principals
export PROJECT_ID="gcp-poc-384805"
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format 'get(projectNumber)')

gcloud projects add-iam-policy-binding projects/${PROJECT_ID} \
     --role roles/monitoring.viewer \
     --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/keda/sa/keda-operator


(Ref) [使用 KEDA 將資源縮減為零](https://docs.cloud.google.com/kubernetes-engine/docs/tutorials/scale-to-zero-using-keda?hl=zh-tw#kubectl)
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

## 產生 Lab 環境
```bash
kubectl apply -f ./yaml/keda/php-test-files.yaml
kubectl apply -f ./yaml/keda/nginx-php-configmap.yaml
kubectl apply -f ./yaml/keda/nginx-deployment.yaml
kubectl apply -f ./yaml/keda/rule.yaml
kubectl apply -f ./yaml/keda/keda-scaledobject.yaml
```

## 查看 php-fpm exporter metrics page
```bash
# 啟用 port forward 到本機
curl -s http://127.0.0.1:9253/metrics | grep processes | grep -v '#'
phpfpm_active_processes{pool="www",scrape_uri="unix:///run/php/php-fpm.sock;/fpm_status"} 1
phpfpm_idle_processes{pool="www",scrape_uri="unix:///run/php/php-fpm.sock;/fpm_status"} 9
phpfpm_max_active_processes{pool="www",scrape_uri="unix:///run/php/php-fpm.sock;/fpm_status"} 20
phpfpm_total_processes{pool="www",scrape_uri="unix:///run/php/php-fpm.sock;/fpm_status"} 10
```

## Pub/Sub 授權給 keda-operator （此方式 KEDA 不建議再使用）
```bash
# !!!! 如果使用 prometheus 查詢 gcp metrics 則不需要此授權，僅 roles/monitoring.viewer 即可。
export PROJECT_ID="gcp-poc-384805"
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format 'get(projectNumber)')

# topic
gcloud pubsub topics create keda-echo --project $PROJECT_ID
gcloud pubsub subscriptions create keda-echo-read --topic=keda-echo --project $PROJECT_ID

# 授權
gcloud projects add-iam-policy-binding projects/${PROJECT_ID}  \
    --role=roles/monitoring.viewer \
  --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/keda/sa/keda-operator \
  --condition=None

gcloud projects add-iam-policy-binding projects/${PROJECT_ID}  \
    --role=roles/pubsub.viewer \
  --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/keda/sa/keda-operator \
  --condition=None
```

# 其他除錯紀錄

## 查看是否正確開啟 Workload Identity 支援
```bash
# 方法一
gcloud container node-pools list \
    --cluster=gke-lab-cluster \
    --region=asia-east1 --project gcp-poc-384805 \
    --format="table(name, config.workloadMetadataConfig.mode)"

gcloud container node-pools describe e2m-spot-pool \
  --cluster gke-lab-cluster \
  --region asia-east1 \
  --project gcp-poc-384805 \
  --format="value(config.workloadMetadataConfig.mode)"

>> 
# MODE 回傳 GKE_METADATA 為正確開啟，否則 null 或 UNSPECIFIED 為『未啟用 WI』

# 方法二
kubectl get nodes -o custom-columns=NAME:.metadata.name,WI_ENABLED:.metadata.labels."iam\.gke\.io/gke-metadata-server-enabled"
>> 
# WI_ENABLED 應該回傳 true

# node pool 啟用 WI 方式
gcloud container node-pools update NODE_POOL_NAME \
    --cluster=CLUSTER_NAME \
    --region=COMPUTE_REGION \
    --workload-metadata=GKE_METADATA

gcloud container clusters describe gke-lab-cluster \
    --region=asia-east1 --project gcp-poc-384805 \
    --format="value(workloadIdentityConfig.workloadPool)"

## 啟用 node pool meta data，啟動後才正常使用 workload identity，否則會預設使用 default sa
gcloud container node-pools update e2m-spot-pool \
    --cluster=gke-lab-cluster \
    --region=asia-east1 --project gcp-poc-384805 \
    --workload-metadata=GKE_METADATA
```

## 除錯
```bash
# 查找 keda-operator pod service account
kubectl get pod keda-operator-55855f6586-hgzjb  -n keda -o yaml | grep serviceAccountName
>>
serviceAccountName: keda-operator

gcloud iam service-accounts get-iam-policy \
  sa-keda-monitoring@ecshopping.iam.gserviceaccount.com \
  --project ecshopping

## 查詢是否正常綁定 KSA 和 GSA
gcloud iam service-accounts get-iam-policy \
  keda-monitoring-gsa@gcp-poc-384805.iam.gserviceaccount.com \
  --project gcp-poc-384805
>>
bindings:
- members:
  - serviceAccount:gcp-poc-384805.svc.id.goog[keda/keda-operator]
  role: roles/iam.workloadIdentityUser
etag: BwZHXk3gFEg=
version: 1

# 檢查 Node Pool 設定
gcloud container node-pools describe np-e2m --cluster ecshopping-ae1 --project ecshopping --zone asia-east1 \
  --format="value(config.workloadMetadataConfig.mode)"

kubectl get serviceaccount keda-operator -n keda -o jsonpath='{.metadata.annotations}'

```