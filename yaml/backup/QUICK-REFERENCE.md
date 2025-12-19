# 快速參考指南

## AI生成

## 🚀 快速部署命令

### 本地 K3s
```bash
kubectl apply -f yaml/nginx-php-configmap.yaml \
              -f yaml/php-test-files.yaml \
              -f yaml/nginx-deployment.yaml
```

### GKE (一鍵部署)
```bash
export GCP_PROJECT_ID="your-project-id"
./yaml/deploy-gke-gmp.sh
```

### HPA 自動擴展
```bash
# 部署 HPA（互動式）
./yaml/deploy-hpa.sh

# 或手動部署
kubectl create namespace custom-metrics
kubectl apply -f yaml/prometheus-adapter.yaml
kubectl apply -f yaml/hpa-custom-metrics.yaml
```

## 📊 常用查詢命令

### 檢查狀態
```bash
# Pod 狀態
kubectl get pods -l app=nginx

# Service 狀態
kubectl get svc -l app=nginx

# PodMonitor 狀態
kubectl get podmonitor

# 告警規則
kubectl get prometheusrule
```

### 查看日誌
```bash
# PHP-FPM
kubectl logs -l app=nginx -c php-fpm --tail=50

# Nginx
kubectl logs -l app=nginx -c nginx --tail=50

# Exporter
kubectl logs -l app=nginx -c php-fpm-exporter --tail=50
```

### 測試功能
```bash
# 測試 PHP
POD=$(kubectl get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -c nginx -- curl -s localhost/test.php

# 測試指標
kubectl exec $POD -c php-fpm-exporter -- wget -qO- localhost:9253/metrics | grep phpfpm

# 檢查 Socket
kubectl exec $POD -c php-fpm -- ls -la /run/php/
```

## 🔍 GMP 監控命令

### Cloud Console 查詢
```bash
# 列出時間序列
gcloud monitoring time-series list \
  --filter='metric.type="prometheus.googleapis.com/phpfpm_active_processes/gauge"' \
  --format=json

# 查看 Dashboard
open "https://console.cloud.google.com/monitoring/metrics-explorer"
```

### PromQL 查詢範例
```promql
# 平均活躍進程
avg(phpfpm_active_processes)

# 總請求率
rate(phpfpm_accepted_connections[5m])

# 進程利用率
(phpfpm_active_processes / phpfpm_total_processes) * 100

# 請求隊列
phpfpm_listen_queue > 0
```

## 🎯 關鍵指標閾值

| 指標 | 警告 | 嚴重 |
|-----|------|------|
| 活躍進程 | > 15 | > 18 |
| 空閒進程 | < 2 | < 1 |
| 進程利用率 | > 80% | > 90% |
| 請求隊列 | > 0 | > 5 |
| 慢請求率 | > 0.1/s | > 1/s |

## 🔧 配置文件位置

```
yaml/
├── nginx-deployment.yaml          # 本地部署
├── nginx-deployment-gke.yaml      # GKE 部署
├── nginx-php-configmap.yaml       # 配置文件
├── podmonitor.yaml                # 監控配置
├── prometheus-rules.yaml          # 告警規則
├── prometheus-adapter.yaml        # Prometheus Adapter
├── hpa-custom-metrics.yaml        # HPA 配置（5種方案）
├── deploy-gke-gmp.sh             # GKE 部署腳本
└── deploy-hpa.sh                 # HPA 部署腳本
```

## 🔄 HPA 快速命令

### 查看 HPA 狀態
```bash
# 查看所有 HPA
kubectl get hpa

# 持續監控 HPA
kubectl get hpa -w

# 查看詳細資訊
kubectl describe hpa nginx-php-hpa-utilization
```

### 查詢自定義指標
```bash
# 查看所有可用的自定義指標
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq -r '.resources[].name'

# 查看進程利用率
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/phpfpm_active_processes_utilization" | jq .

# 查看請求率
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/phpfpm_request_rate" | jq .
```

### 壓力測試
```bash
# 獲取服務地址
SERVICE_IP=$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 使用 wrk 壓測（推薦）
wrk -t10 -c100 -d2m http://$SERVICE_IP/test.php

# 使用 ab
ab -n 10000 -c 100 http://$SERVICE_IP/test.php

# 監控 Pod 擴展
watch kubectl get pods -l app=nginx
```

## 📱 快速連結

- **Metrics Explorer**: `https://console.cloud.google.com/monitoring/metrics-explorer`
- **Dashboards**: `https://console.cloud.google.com/monitoring/dashboards`
- **Alerts**: `https://console.cloud.google.com/monitoring/alerting`
- **GKE Workloads**: `https://console.cloud.google.com/kubernetes/workload`

## 🆘 快速修復

### Pod 無法啟動
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name> -c php-fpm --previous
```

### 指標未出現
```bash
# 檢查 GMP
kubectl get pods -n gmp-system
kubectl logs -n gmp-system -l app.kubernetes.io/name=collector

# 檢查 PodMonitor
kubectl describe podmonitor nginx-php-fpm-monitor
```

### Unix Socket 錯誤
```bash
# 檢查 socket 文件
kubectl exec <pod-name> -c php-fpm -- test -S /run/php/php-fpm.sock && echo "OK" || echo "FAIL"

# 重啟 Pod
kubectl delete pod <pod-name>
```

## 🎨 環境切換

### 切換到 K3s
```bash
kubectl apply -f yaml/nginx-deployment.yaml
# Service type: NodePort (30080)
```

### 切換到 GKE
```bash
kubectl apply -f yaml/nginx-deployment-gke.yaml
# Service type: LoadBalancer
```

## 💡 實用技巧

### Port Forward
```bash
# Nginx
kubectl port-forward svc/nginx-service 8080:80

# Metrics
kubectl port-forward svc/php-fpm-metrics 9253:9253
```

### 擴縮容
```bash
# 手動擴展
kubectl scale deployment nginx-deployment --replicas=5

# 查看 HPA 狀態
kubectl get hpa

# 刪除 HPA（恢復手動控制）
kubectl delete hpa nginx-php-hpa-utilization

# 使用自定義指標自動擴展（詳見 HPA-GUIDE.md）
./yaml/deploy-hpa.sh
```

### 配置更新
```bash
# 更新 ConfigMap
kubectl apply -f yaml/nginx-php-configmap.yaml

# 重啟 Pod 以應用新配置
kubectl rollout restart deployment nginx-deployment
```

## 📞 緊急聯絡

遇到問題？檢查以下項目：
1. ✅ Pod 是否 Running？
2. ✅ Service 是否有 Endpoint？
3. ✅ ConfigMap 是否正確掛載？
4. ✅ Socket 文件是否存在？
5. ✅ GMP 是否已啟用？
