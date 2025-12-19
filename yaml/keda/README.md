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

# !!!! 注意此範例使用 workloadIdentity 進行授權給 keda-operator
```bash
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

## Pub/Sub 授權給 keda-operator
```bash
export PROJECT_ID="gcp-poc-384805"
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format 'get(projectNumber)')

gcloud pubsub topics create keda-echo --project $PROJECT_ID
gcloud pubsub subscriptions create keda-echo-read --topic=keda-echo --project $PROJECT_ID
gcloud projects add-iam-policy-binding projects/${PROJECT_ID}  \
    --role=roles/pubsub.subscriber \
  --member=principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/keda/sa/keda-operator
```