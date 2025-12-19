# HPA 自動擴展 - 快速開始

## AI生成

本文檔提供 Nginx + PHP-FPM 基於自定義指標的 HPA 自動擴展快速入門。

## 📋 前置需求檢查清單

- ✅ Nginx + PHP-FPM Deployment 已部署並運行
- ✅ PHP-FPM Exporter 正常暴露指標（端口 9253）
- ✅ Prometheus 或 Google Managed Prometheus 正在收集指標
- ✅ kubectl 已配置並可訪問集群

## 🚀 三步快速部署

### 方法 1: 使用自動化腳本（推薦）

```bash
# 執行互動式部署腳本
./yaml/deploy-hpa.sh
```

腳本會自動：
1. 檢查基礎部署狀態
2. 配置 Prometheus Adapter
3. 驗證自定義指標可用性
4. 讓您選擇合適的 HPA 方案
5. 顯示監控和測試命令

### 方法 2: 手動部署

```bash
# 步驟 1: 部署 Prometheus Adapter
kubectl create namespace custom-metrics
kubectl apply -f yaml/prometheus-adapter.yaml

# 步驟 2: 等待 Adapter 就緒
kubectl wait --for=condition=available --timeout=120s \
  deployment/custom-metrics-apiserver -n custom-metrics

# 步驟 3: 驗證自定義指標
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq -r '.resources[].name' | grep phpfpm

# 步驟 4: 部署 HPA（選擇一個方案）
kubectl apply -f yaml/hpa-custom-metrics.yaml
```

## 🎯 5 種 HPA 方案快速選擇

| 方案 | 適用場景 | 指標 | 閾值 | 特點 |
|------|---------|------|------|------|
| **1. 進程利用率** | 一般 Web 應用 | `phpfpm_active_processes_utilization` | 70% | 平衡資源和性能 |
| **2. 活躍進程數** | 已知並發需求 | `phpfpm_active_processes` | 12 個 | 精確控制 |
| **3. 混合指標** | 生產環境 | 進程+CPU+記憶體 | 多維度 | 最全面保護 |
| **4. 請求隊列** | 高流量電商 | `phpfpm_listen_queue` | 1 個 | 極速響應 |
| **5. 請求率** | API 微服務 | `phpfpm_request_rate` | 50 req/s | 吞吐量驅動 |

### 推薦配置

**新手推薦**: 方案 1（進程利用率）  
**生產環境**: 方案 3（混合指標）  
**高流量場景**: 方案 4（請求隊列）

## 📊 驗證部署

### 1. 檢查 HPA 狀態

```bash
kubectl get hpa

# 預期輸出:
# NAME                          REFERENCE                    TARGETS   MINPODS   MAXPODS   REPLICAS
# nginx-php-hpa-utilization   Deployment/nginx-deployment   350m/700m   2         10        2
```

如果 `TARGETS` 顯示 `<unknown>`，請檢查：
- Prometheus Adapter 是否運行正常
- 指標是否在 Prometheus 中可用
- APIService 狀態

### 2. 查看當前指標值

```bash
# 進程利用率
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/phpfpm_active_processes_utilization" | jq .

# 活躍進程數
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/phpfpm_active_processes" | jq .

# 請求率
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/phpfpm_request_rate" | jq .
```

### 3. 持續監控

```bash
# 在一個終端監控 HPA
kubectl get hpa -w

# 在另一個終端監控 Pod
watch kubectl get pods -l app=nginx
```

## 🧪 負載測試

### 準備工作

```bash
# 獲取服務地址
# GKE (LoadBalancer)
SERVICE_IP=$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# K3s (NodePort)
SERVICE_IP="localhost:30080"
```

### 執行壓測

```bash
# 方法 1: 使用 wrk（推薦）
wrk -t10 -c100 -d2m http://$SERVICE_IP/test.php

# 方法 2: 使用 Apache Bench
ab -n 10000 -c 100 http://$SERVICE_IP/test.php

# 方法 3: 使用 hey
hey -n 10000 -c 100 http://$SERVICE_IP/test.php
```

### 觀察擴展行為

預期行為（以方案 1 為例）：
1. **初始狀態**: 2 個 Pod，利用率約 30%
2. **壓測開始**: 利用率上升至 70% 以上
3. **觸發擴展**: 30-60 秒內增加到 4 個 Pod
4. **持續擴展**: 如果負載持續，繼續擴展至最多 10 個
5. **負載降低**: 5 分鐘穩定期後開始縮容
6. **恢復初始**: 逐步縮減回 2 個 Pod

## 🔧 常見調整

### 調整擴展速度

如果擴展太慢：
```yaml
scaleUp:
  stabilizationWindowSeconds: 30  # 從 60 減少到 30
  policies:
  - type: Pods
    value: 3  # 從 2 增加到 3
    periodSeconds: 15  # 從 30 減少到 15
```

如果擴展太激進：
```yaml
scaleUp:
  stabilizationWindowSeconds: 120  # 從 60 增加到 120
  policies:
  - type: Pods
    value: 1  # 從 2 減少到 1
    periodSeconds: 60  # 從 30 增加到 60
```

### 調整目標利用率

```yaml
target:
  type: AverageValue
  averageValue: "500m"  # 從 700m (70%) 降低到 500m (50%)
```

更低的閾值 = 更早擴展 = 更多資源消耗  
更高的閾值 = 更晚擴展 = 更節省成本但可能影響性能

### 調整副本數範圍

```yaml
spec:
  minReplicas: 3  # 增加最小副本數以提高可用性
  maxReplicas: 20  # 增加最大副本數以應對更高流量
```

## 📈 監控面板

### GKE Workload Metrics

1. 前往 GCP Console
2. 導航到 Kubernetes Engine → Workloads
3. 選擇 `nginx-deployment`
4. 查看 "Metrics" 標籤

### Cloud Monitoring

1. 前往 Cloud Monitoring
2. 創建自定義 Dashboard
3. 添加以下圖表：
   - `phpfpm_active_processes_utilization`
   - `phpfpm_request_rate`
   - `kube_hpa_status_current_replicas`
   - `kube_hpa_status_desired_replicas`

### Grafana（如有）

導入 PHP-FPM Dashboard 模板：
- Dashboard ID: 11831
- 或使用專案提供的 `grafana-dashboard.json`

## ⚠️ 故障排查

### 問題 1: HPA 顯示 `<unknown>`

**解決步驟**:
```bash
# 1. 檢查 Prometheus Adapter
kubectl get pods -n custom-metrics
kubectl logs -n custom-metrics deployment/custom-metrics-apiserver --tail=50

# 2. 檢查 APIService
kubectl get apiservice v1beta1.custom.metrics.k8s.io

# 3. 檢查 Prometheus 中是否有數據
# 如果使用 GMP，檢查 Cloud Monitoring
# 如果使用自建 Prometheus:
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# 訪問 http://localhost:9090，查詢 phpfpm_active_processes
```

### 問題 2: HPA 不進行擴展

**可能原因**:
1. 指標值未超過閾值
2. 穩定期（stabilizationWindowSeconds）限制
3. 已達到 maxReplicas

**診斷**:
```bash
# 查看詳細狀態
kubectl describe hpa nginx-php-hpa-utilization

# 查看事件
kubectl get events --field-selector involvedObject.name=nginx-php-hpa-utilization --sort-by='.lastTimestamp'

# 手動查詢當前指標值
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/deployments/nginx-deployment/phpfpm_active_processes_utilization" | jq .
```

### 問題 3: 指標延遲

Prometheus Adapter 預設每 30 秒更新一次指標。如果需要更快的響應：

1. 編輯 `prometheus-adapter.yaml`
2. 修改 Deployment 中的 `--metrics-relist-interval` 參數
3. 從 `30s` 改為 `10s` 或 `15s`

## 📚 延伸閱讀

- **完整指南**: [HPA-GUIDE.md](./HPA-GUIDE.md) - 詳細的 HPA 配置說明
- **GMP 整合**: [GMP-DEPLOYMENT-GUIDE.md](./GMP-DEPLOYMENT-GUIDE.md) - Google Managed Prometheus 設置
- **快速參考**: [QUICK-REFERENCE.md](./QUICK-REFERENCE.md) - 常用命令集合
- **專案總覽**: [README-GMP.md](./README-GMP.md) - 完整專案說明

## 🎯 生產環境檢查清單

在生產環境使用 HPA 前，請確認：

- [ ] 已進行充分的負載測試
- [ ] 已設置 PodDisruptionBudget (PDB)
- [ ] 已配置節點自動擴展（Cluster Autoscaler）
- [ ] 已設置合理的資源 requests 和 limits
- [ ] 已配置監控告警（HPA 達到 maxReplicas）
- [ ] 已設置成本監控和預算
- [ ] 已記錄最佳配置參數
- [ ] 已建立故障恢復流程

## 🎉 下一步

HPA 配置完成後，您可以：

1. **優化性能**: 根據實際數據調整 HPA 參數
2. **成本優化**: 分析擴展模式，調整 min/max replicas
3. **多維度擴展**: 嘗試混合指標方案
4. **自動化運維**: 整合 CI/CD 流程
5. **進階功能**: 探索 VPA (Vertical Pod Autoscaler) 和 KEDA

---

**提示**: 如果您是第一次使用 HPA，建議從方案 1（進程利用率）開始，並在低流量時段進行測試。

如有問題，請查看 [HPA-GUIDE.md](./HPA-GUIDE.md) 的故障排查章節。
