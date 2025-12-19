# Nginx + PHP-FPM with HPA 部署指南

本目錄包含在 Google Kubernetes Engine (GKE) 上部署 Nginx + PHP-FPM 應用程式的完整配置，支援基於自訂指標的自動擴展（HPA）。

## 📋 目錄

- [前置需求](#前置需求)
- [GKE Cluster 設置](#gke-cluster-設置)
- [部署步驟](#部署步驟)
- [驗證與測試](#驗證與測試)
- [監控與擴展](#監控與擴展)
- [故障排除](#故障排除)
- [檔案說明](#檔案說明)

## 🔧 前置需求

### 本地工具
確保已安裝以下工具：
```bash
# Google Cloud SDK
gcloud --version

# Kubernetes CLI
kubectl version --client

# 驗證 GCP 認證
gcloud auth list
gcloud config list project
```

### GCP 專案設置
```bash
# 設定專案 ID
export PROJECT_ID="your-project-id"
export REGION="asia-east1"
export ZONE="asia-east1-a"

gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
```

## 🚀 GKE Cluster 設置

### 1. 啟用必要的 GCP API

```bash
# 啟用必要的 API
gcloud services enable container.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable cloudapis.googleapis.com
```

### 2. 創建 GKE Cluster（新 Cluster）

如果是新的 GKE cluster，需要啟用以下功能：

```bash
# 創建啟用 Google Managed Prometheus (GMP) 的 GKE cluster
gcloud container clusters create php-fpm-cluster \
  --zone=$ZONE \
  --enable-managed-prometheus \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=10 \
  --machine-type=e2-medium \
  --disk-size=20 \
  --enable-autorepair \
  --enable-autoupgrade \
  --release-channel=regular
```

**重要功能說明：**
- `--enable-managed-prometheus`：啟用 Google Managed Prometheus，用於收集和儲存自訂指標
- `--enable-autoscaling`：啟用 cluster 節點自動擴展
- `--release-channel=regular`：使用穩定的發布頻道

### 3. 為現有 Cluster 啟用 GMP

如果已有 cluster，需要啟用 Google Managed Prometheus：

```bash
# 啟用 Managed Prometheus
gcloud container clusters update php-fpm-cluster \
  --zone=$ZONE \
  --enable-managed-prometheus
```

### 4. 連接到 Cluster

```bash
# 取得 cluster 憑證
gcloud container clusters get-credentials php-fpm-cluster --zone=$ZONE

# 驗證連接
kubectl cluster-info
kubectl get nodes
```

### 5. 驗證 GMP 安裝

```bash
# 檢查 GMP 相關元件
kubectl get pods -n gmp-system
kubectl get pods -n gmp-public

# 應該看到以下 pods 正在運行：
# - gmp-system namespace: collector, rule-evaluator
# - gmp-public namespace: operator
```

### 6. 驗證 PodMonitoring CRD

```bash
# 確認 PodMonitoring CRD 已安裝
kubectl get crd podmonitorings.monitoring.googleapis.com

# 輸出應顯示 CRD 存在
```

## 📦 部署步驟

按照以下順序部署應用程式：

### 步驟 1：部署 ConfigMaps

首先部署配置檔案，因為 Deployment 需要引用這些 ConfigMaps。

```bash
# 部署 Nginx 和 PHP-FPM 配置
kubectl apply -f nginx-php-configmap.yaml

# 部署 PHP 測試檔案
kubectl apply -f php-test-files.yaml

# 驗證 ConfigMaps
kubectl get configmap
```

**預期輸出：**
- `nginx-config`
- `php-fpm-config`
- `php-test-files`

### 步驟 2：部署應用程式

```bash
# 部署 Nginx + PHP-FPM Deployment 和 Service
kubectl apply -f nginx-deployment.yaml

# 等待 pods 就緒（可能需要 1-2 分鐘）
kubectl rollout status deployment/nginx-deployment

# 檢查 pods 狀態
kubectl get pods -l app=nginx
```

**預期輸出：**
```
NAME                               READY   STATUS    RESTARTS   AGE
nginx-deployment-xxxxxxxxx-xxxxx   3/3     Running   0          2m
nginx-deployment-xxxxxxxxx-xxxxx   3/3     Running   0          2m
```

每個 Pod 包含 3 個容器：nginx、php-fpm、php-fpm-exporter

### 步驟 3：驗證 PodMonitoring

```bash
# PodMonitoring 已包含在 nginx-deployment.yaml 中
# 驗證 PodMonitoring 資源
kubectl get podmonitoring custom-metrics-exporter

# 檢查 PodMonitoring 狀態
kubectl describe podmonitoring custom-metrics-exporter
```

### 步驟 4：部署 Prometheus Recording Rules

```bash
# 部署計算 PHP-FPM 利用率的記錄規則
kubectl apply -f rule.yaml

# 驗證 Rules 資源
kubectl get rules php-fpm-recording-rules

# 檢查詳細資訊
kubectl describe rules php-fpm-recording-rules
```

**等待指標生成：** 記錄規則每 15 秒計算一次，需要等待 2-3 分鐘讓指標開始產生。

### 步驟 5：驗證指標收集

```bash
# 取得 Service 外部 IP
kubectl get svc nginx-service

# 產生一些流量以產生指標
EXTERNAL_IP=$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for i in {1..100}; do curl http://$EXTERNAL_IP/test.php; done

# 檢查 PHP-FPM exporter 指標（port-forward 到本地）
kubectl port-forward deployment/nginx-deployment 9253:9253

# 在另一個終端機視窗執行
curl http://localhost:9253/metrics | grep phpfpm
```

**重要指標：**
- `phpfpm_active_processes`：當前活躍的 PHP-FPM 進程數
- `phpfpm_total_processes`：總進程數
- `job:phpfpm_process_utilization:ratio`：計算出的利用率百分比

### 步驟 6：部署 HPA

**⚠️ 重要：在部署 HPA 之前，確保：**
1. 指標已經在 Cloud Monitoring 中可見（等待 5-10 分鐘）
2. Recording rule 正在產生 `job:phpfpm_process_utilization:ratio` 指標

```bash
# 驗證指標在 GCP Console 是否可見
# 前往：Cloud Console > Monitoring > Metrics Explorer
# 搜尋：prometheus.googleapis.com/job:phpfpm_process_utilization:ratio/gauge

# 部署 HPA
kubectl apply -f hpa-external.yaml

# 驗證 HPA
kubectl get hpa php-fpm-hpa

# 檢查 HPA 詳細狀態
kubectl describe hpa php-fpm-hpa
```

**預期輸出：**
```
NAME           REFERENCE                     TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
php-fpm-hpa    Deployment/nginx-deployment   15/70, 5%/40%   2         10        2          1m
```

## ✅ 驗證與測試

### 1. 驗證應用程式運作

```bash
# 取得 Service 外部 IP
EXTERNAL_IP=$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP: $EXTERNAL_IP"

# 測試 PHP 資訊頁面
curl http://$EXTERNAL_IP/index.php

# 測試 PHP-FPM 狀態
curl http://$EXTERNAL_IP/test.php

# 測試健康檢查
curl http://$EXTERNAL_IP/health.php
```

### 2. 驗證 Prometheus 指標

```bash
# Port-forward 到 exporter
kubectl port-forward deployment/nginx-deployment 9253:9253 &

# 檢查原始指標
curl http://localhost:9253/metrics | grep -E "phpfpm_(active|total)_processes"

# 預期輸出範例：
# phpfpm_active_processes{pool="www",scrape_uri="unix:///run/php/php-fpm.sock;/fpm_status"} 2
# phpfpm_total_processes{pool="www",scrape_uri="unix:///run/php/php-fpm.sock;/fpm_status"} 5
```

### 3. 在 Google Cloud Console 驗證指標

1. 前往 [Cloud Console - Metrics Explorer](https://console.cloud.google.com/monitoring/metrics-explorer)
2. 搜尋以下指標：
   - `prometheus.googleapis.com/phpfpm_active_processes/gauge`
   - `prometheus.googleapis.com/phpfpm_total_processes/gauge`
   - `prometheus.googleapis.com/job:phpfpm_process_utilization:ratio/gauge`
3. 確認數據正在收集

## 📊 監控與擴展

### 監控 HPA 行為

```bash
# 即時監控 HPA 狀態
kubectl get hpa php-fpm-hpa --watch

# 查看 HPA 事件
kubectl describe hpa php-fpm-hpa | tail -20

# 監控 Pod 數量變化
kubectl get pods -l app=nginx --watch
```

### 負載測試觸發擴展

使用提供的負載測試檔案：

```bash
# 使用 Apache Bench 進行負載測試
EXTERNAL_IP=$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 安裝 Apache Bench（如果尚未安裝）
# macOS: brew install httpd
# Ubuntu: sudo apt-get install apache2-utils

# 執行負載測試（同時 50 個連線，總共 10000 個請求）
ab -n 10000 -c 50 http://$EXTERNAL_IP/test.php

# 或使用 hey（更現代的負載測試工具）
# brew install hey
hey -n 10000 -c 50 http://$EXTERNAL_IP/test.php
```

**觀察擴展行為：**
```bash
# 在另一個終端機監控
watch -n 2 'kubectl get hpa php-fpm-hpa && echo "---" && kubectl get pods -l app=nginx'
```

## 🔍 故障排除

### HPA 顯示 "unknown" 指標

**問題：** HPA 無法取得外部指標

```bash
kubectl describe hpa php-fpm-hpa
# 看到：unable to get external metric
```

**解決方案：**

1. **驗證 GMP 已啟用：**
   ```bash
   gcloud container clusters describe php-fpm-cluster --zone=$ZONE | grep managedPrometheusConfig
   ```

2. **檢查 PodMonitoring 狀態：**
   ```bash
   kubectl describe podmonitoring custom-metrics-exporter
   ```

3. **確認指標在 Cloud Monitoring 中存在：**
   ```bash
   # 使用 gcloud 查詢指標
   gcloud monitoring time-series list \
     --filter='metric.type="prometheus.googleapis.com/job:phpfpm_process_utilization:ratio/gauge"' \
     --limit=10
   ```

4. **等待更長時間：** 指標從收集到在 HPA 中可用可能需要 10-15 分鐘

### Pods 無法啟動

**問題：** Pods 停留在 Pending 或 CrashLoopBackOff

```bash
# 檢查 Pod 事件
kubectl describe pod <pod-name>

# 檢查容器日誌
kubectl logs <pod-name> -c nginx
kubectl logs <pod-name> -c php-fpm
kubectl logs <pod-name> -c php-fpm-exporter
```

**常見原因：**
- ConfigMap 未正確創建
- 資源配額不足
- 映像檔拉取失敗

### PHP-FPM Socket 連接失敗

**問題：** Nginx 無法連接到 PHP-FPM

```bash
# 進入 nginx 容器
kubectl exec -it <pod-name> -c nginx -- sh

# 檢查 socket 檔案
ls -la /run/php/php-fpm.sock

# 測試 socket 連接
echo -e "SCRIPT_FILENAME=/var/www/html/test.php\n\n" | cgi-fcgi -bind -connect /run/php/php-fpm.sock
```

### 負載均衡器無法取得外部 IP

**問題：** Service 停留在 `<pending>`

```bash
kubectl get svc nginx-service
# EXTERNAL-IP 顯示 <pending>
```

**解決方案：**
```bash
# 檢查 Service 事件
kubectl describe svc nginx-service

# 如果是本地測試，改用 NodePort
kubectl patch svc nginx-service -p '{"spec":{"type":"NodePort"}}'
```

## 📁 檔案說明

| 檔案 | 用途 | 部署順序 |
|------|------|----------|
| `nginx-php-configmap.yaml` | Nginx 和 PHP-FPM 配置檔案 | 1 |
| `php-test-files.yaml` | 測試用 PHP 檔案（phpinfo、test、health） | 1 |
| `nginx-deployment.yaml` | 完整的應用程式部署（Nginx + PHP-FPM + Exporter）<br/>包含 PodMonitoring 配置 | 2 |
| `rule.yaml` | Prometheus Recording Rules<br/>計算 PHP-FPM 進程利用率 | 3 |
| `hpa-external.yaml` | Horizontal Pod Autoscaler<br/>基於 PHP-FPM 利用率和 CPU 的自動擴展 | 4 |

## 🏗️ 架構說明

```
┌─────────────────────────────────────────────────────────────┐
│                         GKE Cluster                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │                    Pod (每個)                       │    │
│  │                                                     │    │
│  │  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │    │
│  │  │  Nginx   │◄─┤ PHP-FPM  │◄─┤ PHP-FPM        │  │    │
│  │  │          │  │          │  │ Exporter       │  │    │
│  │  │  :80     │  │  socket  │  │ :9253/metrics  │  │    │
│  │  └────┬─────┘  └──────────┘  └───────┬────────┘  │    │
│  │       │                               │           │    │
│  │       └───────────────┬───────────────┘           │    │
│  │                       │                           │    │
│  └───────────────────────┼───────────────────────────┘    │
│                          │                                │
│                          ▼                                │
│              ┌────────────────────────┐                   │
│              │  PodMonitoring (GMP)   │                   │
│              │  收集 :9253/metrics    │                   │
│              └───────────┬────────────┘                   │
│                          │                                │
│                          ▼                                │
│              ┌────────────────────────┐                   │
│              │  Recording Rules       │                   │
│              │  計算利用率百分比       │                   │
│              └───────────┬────────────┘                   │
│                          │                                │
│                          ▼                                │
│              ┌────────────────────────┐                   │
│              │         HPA            │                   │
│              │  監控指標並調整副本數   │                   │
│              └────────────────────────┘                   │
│                                                            │
└────────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │  Google Cloud          │
              │  Monitoring            │
              │  (儲存指標)            │
              └────────────────────────┘
```

## 📚 相關資源

- [Google Managed Prometheus 文檔](https://cloud.google.com/stackdriver/docs/managed-prometheus)
- [GKE HPA with Custom Metrics](https://cloud.google.com/kubernetes-engine/docs/how-to/horizontal-pod-autoscaling)
- [PHP-FPM Exporter](https://github.com/hipages/php-fpm_exporter)
- [Kubernetes HPA v2 API](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/horizontal-pod-autoscaler-v2/)

## 🤝 支援

如有問題，請檢查：
1. GKE cluster 日誌
2. Cloud Monitoring Metrics Explorer
3. Pod 和容器日誌
4. HPA 事件和狀態

---

**AI生成**
