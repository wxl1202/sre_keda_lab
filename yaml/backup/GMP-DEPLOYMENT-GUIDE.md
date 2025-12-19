# Google Managed Prometheus (GMP) 部署指南

## AI生成

本指南說明如何在 GKE 上部署 Nginx + PHP-FPM，並使用 Google Managed Prometheus 進行監控。

## 📋 前置需求

### 1. 啟用 GKE 上的 Managed Prometheus

在創建或更新 GKE 集群時啟用 GMP：

```bash
# 創建新集群並啟用 GMP
gcloud container clusters create CLUSTER_NAME \
    --enable-managed-prometheus \
    --zone=ZONE \
    --machine-type=e2-medium \
    --num-nodes=3

# 或更新現有集群
gcloud container clusters update CLUSTER_NAME \
    --enable-managed-prometheus \
    --zone=ZONE
```

### 2. 驗證 GMP 已啟用

```bash
# 檢查 GMP 相關的 Pod
kubectl get pods -n gmp-system

# 應該看到類似以下的 Pod：
# gmp-operator-xxx
# collector-xxx
```

## 🚀 部署步驟

### 步驟 1: 部署應用

```bash
# 部署 ConfigMaps
kubectl apply -f yaml/nginx-php-configmap.yaml
kubectl apply -f yaml/php-test-files.yaml

# 部署 Deployment 和 Services
kubectl apply -f yaml/nginx-deployment.yaml

# 驗證部署
kubectl get pods -l app=nginx
kubectl get services -l app=nginx
```

### 步驟 2: 部署 PodMonitor

```bash
# 部署 PodMonitor 配置
kubectl apply -f yaml/podmonitor.yaml

# 驗證 PodMonitor 已創建
kubectl get podmonitor
kubectl describe podmonitor nginx-php-fpm-monitor
```

### 步驟 3: 驗證指標抓取

等待幾分鐘後，檢查指標是否被 GMP 抓取：

```bash
# 在 Cloud Console 中查詢指標
# 或使用 gcloud 命令
gcloud monitoring time-series list \
    --filter='metric.type="prometheus.googleapis.com/phpfpm_active_processes/gauge"' \
    --format=json
```

## 📊 在 Cloud Console 中查看指標

### 1. 訪問 Metrics Explorer

1. 打開 [Google Cloud Console](https://console.cloud.google.com)
2. 導航到 **Monitoring > Metrics Explorer**
3. 搜索 `phpfpm` 相關指標

### 2. 可用的指標

GMP 會自動收集以下 PHP-FPM 指標：

```
prometheus.googleapis.com/phpfpm_accepted_connections/counter
prometheus.googleapis.com/phpfpm_active_processes/gauge
prometheus.googleapis.com/phpfpm_idle_processes/gauge
prometheus.googleapis.com/phpfpm_listen_queue/gauge
prometheus.googleapis.com/phpfpm_max_active_processes/gauge
prometheus.googleapis.com/phpfpm_max_children_reached/counter
prometheus.googleapis.com/phpfpm_max_listen_queue/gauge
prometheus.googleapis.com/phpfpm_slow_requests/counter
prometheus.googleapis.com/phpfpm_start_since/gauge
prometheus.googleapis.com/phpfpm_total_processes/gauge
```

## 📈 創建 Dashboard

### 使用 Cloud Monitoring Dashboard

創建 `dashboard.json` 或在 Console 中手動創建：

```json
{
  "displayName": "PHP-FPM Monitoring Dashboard",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Active PHP-FPM Processes",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"prometheus.googleapis.com/phpfpm_active_processes/gauge\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      }
    ]
  }
}
```

部署 Dashboard：

```bash
gcloud monitoring dashboards create --config-from-file=dashboard.json
```

## 🔔 設置告警

### 創建告警策略

```bash
# 創建告警：當活躍進程數超過閾值
gcloud alpha monitoring policies create \
    --notification-channels=CHANNEL_ID \
    --display-name="PHP-FPM High Active Processes" \
    --condition-display-name="Active processes > 15" \
    --condition-threshold-value=15 \
    --condition-threshold-duration=300s \
    --condition-filter='metric.type="prometheus.googleapis.com/phpfpm_active_processes/gauge"'
```

### 告警示例

創建 `alert-policy.yaml`:

```yaml
# AI生成
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: php-fpm-alerts
  labels:
    app: nginx
spec:
  groups:
  - name: php-fpm
    interval: 30s
    rules:
    # 活躍進程數過高
    - alert: PhpFpmHighActiveProcesses
      expr: phpfpm_active_processes > 15
      for: 5m
      labels:
        severity: warning
        component: php-fpm
      annotations:
        summary: "PHP-FPM active processes is high"
        description: "Pod {{ $labels.pod }} has {{ $value }} active processes"
    
    # 空閒進程數過低
    - alert: PhpFpmLowIdleProcesses
      expr: phpfpm_idle_processes < 2
      for: 5m
      labels:
        severity: warning
        component: php-fpm
      annotations:
        summary: "PHP-FPM idle processes is low"
        description: "Pod {{ $labels.pod }} has only {{ $value }} idle processes"
    
    # 達到最大子進程數
    - alert: PhpFpmMaxChildrenReached
      expr: rate(phpfpm_max_children_reached[5m]) > 0
      for: 5m
      labels:
        severity: critical
        component: php-fpm
      annotations:
        summary: "PHP-FPM reached max children"
        description: "Pod {{ $labels.pod }} is reaching max children limit"
    
    # 慢請求
    - alert: PhpFpmSlowRequests
      expr: rate(phpfpm_slow_requests[5m]) > 0.1
      for: 5m
      labels:
        severity: warning
        component: php-fpm
      annotations:
        summary: "PHP-FPM slow requests detected"
        description: "Pod {{ $labels.pod }} has slow requests"
```

部署告警規則：

```bash
kubectl apply -f alert-policy.yaml
```

## 🔍 常用 PromQL 查詢

### 1. 平均活躍進程數

```promql
avg(phpfpm_active_processes{job="php-fpm"})
```

### 2. 總請求率

```promql
rate(phpfpm_accepted_connections{job="php-fpm"}[5m])
```

### 3. 進程利用率

```promql
(phpfpm_active_processes / phpfpm_total_processes) * 100
```

### 4. 請求隊列長度

```promql
phpfpm_listen_queue{job="php-fpm"}
```

### 5. 慢請求率

```promql
rate(phpfpm_slow_requests{job="php-fpm"}[5m])
```

## 📝 GMP 特定配置說明

### PodMonitor vs ServiceMonitor

**PodMonitor**（推薦用於此場景）：
- 直接從 Pod 抓取指標
- 適合監控每個 Pod 實例
- 自動發現新的 Pod

**ServiceMonitor**：
- 通過 Service 抓取指標
- 適合聚合指標
- 需要 Service 存在

### 重要標籤

GMP 使用以下標籤來識別和組織指標：

```yaml
labels:
  app: nginx                           # 應用名稱
  app.kubernetes.io/name: nginx-php-fpm  # K8s 標準標籤
  job: php-fpm                         # Prometheus job 名稱
  cluster: gke-cluster                 # 集群名稱
```

### Relabeling 配置

```yaml
relabelings:
# 保留 Pod 名稱
- sourceLabels: [__meta_kubernetes_pod_name]
  targetLabel: pod
  
# 保留命名空間
- sourceLabels: [__meta_kubernetes_namespace]
  targetLabel: namespace
  
# 添加集群標籤
- targetLabel: cluster
  replacement: your-cluster-name
```

## 🎯 優化建議

### 1. 調整抓取間隔

根據需求調整 `interval`：

```yaml
podMetricsEndpoints:
- interval: 30s      # 標準監控
- interval: 10s      # 高頻監控（增加成本）
- interval: 60s      # 低頻監控（降低成本）
```

### 2. 設置資源限制

確保 GMP collector 有足夠資源：

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"
```

### 3. 使用標籤過濾

減少不必要的指標：

```yaml
metricRelabelings:
- sourceLabels: [__name__]
  regex: 'phpfpm_(active|idle|total)_processes'
  action: keep
```

## 💰 成本優化

### 估算成本

GMP 按以下方式計費：
- 指標樣本數量
- 查詢次數
- 數據保留時間

### 降低成本的方法

1. **減少抓取頻率**：從 30s 改為 60s
2. **過濾不需要的指標**：使用 `metricRelabelings`
3. **減少副本數**：如果不需要高可用
4. **使用聚合規則**：減少原始數據存儲

## 🔧 故障排查

### 檢查 PodMonitor 狀態

```bash
# 查看 PodMonitor
kubectl get podmonitor -o yaml

# 查看 GMP operator 日誌
kubectl logs -n gmp-system -l app.kubernetes.io/name=operator

# 查看 collector 日誌
kubectl logs -n gmp-system -l app.kubernetes.io/name=collector
```

### 驗證指標端點

```bash
# 測試指標端點可訪問
kubectl exec -it POD_NAME -c php-fpm-exporter -- wget -qO- http://localhost:9253/metrics

# 檢查 Service
kubectl get svc php-fpm-metrics -o yaml
```

### 常見問題

**問題 1：指標未顯示在 Cloud Console**
- 檢查 PodMonitor 是否正確創建
- 確認 Pod 標籤匹配
- 等待 3-5 分鐘讓 GMP 抓取數據

**問題 2：指標數據不完整**
- 檢查 scrapeTimeout 是否足夠
- 確認網路策略允許訪問
- 查看 collector 日誌

**問題 3：成本過高**
- 減少抓取頻率
- 過濾不需要的指標
- 檢查是否有重複的監控配置

## 📚 相關資源

- [Google Managed Prometheus 文檔](https://cloud.google.com/stackdriver/docs/managed-prometheus)
- [PodMonitor API 參考](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#podmonitor)
- [PromQL 查詢語言](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [GKE Monitoring 最佳實踐](https://cloud.google.com/kubernetes-engine/docs/how-to/monitoring)

## 🚀 快速開始腳本

創建一鍵部署腳本 `deploy-gke-with-monitoring.sh`:

```bash
#!/bin/bash
# AI生成 - GKE 完整部署腳本

set -e

echo "=========================================="
echo "GKE + GMP 部署腳本"
echo "=========================================="

# 配置變數
PROJECT_ID="your-project-id"
CLUSTER_NAME="nginx-php-cluster"
ZONE="us-central1-a"

# 1. 創建 GKE 集群（如果不存在）
echo "創建 GKE 集群..."
gcloud container clusters create $CLUSTER_NAME \
    --enable-managed-prometheus \
    --zone=$ZONE \
    --machine-type=e2-medium \
    --num-nodes=3 \
    --project=$PROJECT_ID \
    || echo "集群可能已存在"

# 2. 獲取集群憑證
echo "獲取集群憑證..."
gcloud container clusters get-credentials $CLUSTER_NAME \
    --zone=$ZONE \
    --project=$PROJECT_ID

# 3. 部署應用
echo "部署應用..."
kubectl apply -f yaml/nginx-php-configmap.yaml
kubectl apply -f yaml/php-test-files.yaml
kubectl apply -f yaml/nginx-deployment.yaml

# 4. 部署監控
echo "部署 PodMonitor..."
kubectl apply -f yaml/podmonitor.yaml

# 5. 等待 Pod 就緒
echo "等待 Pod 就緒..."
kubectl wait --for=condition=ready pod -l app=nginx --timeout=300s

# 6. 顯示狀態
echo "=========================================="
echo "部署完成！"
echo "=========================================="
kubectl get pods -l app=nginx
kubectl get services -l app=nginx
kubectl get podmonitor

echo ""
echo "訪問應用："
EXTERNAL_IP=$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "  http://$EXTERNAL_IP/test.php"
echo ""
echo "查看指標："
echo "  Cloud Console: https://console.cloud.google.com/monitoring/metrics-explorer"
```

使用方法：

```bash
chmod +x deploy-gke-with-monitoring.sh
./deploy-gke-with-monitoring.sh
```
