# Nginx + PHP-FPM + Google Managed Prometheus 完整方案

## AI生成

本方案提供完整的 Nginx + PHP-FPM 部署配置，支持本地 K3s 開發和 GKE 生產環境，並整合 Google Managed Prometheus (GMP) 監控。

## 📁 文件結構

```
yaml/
├── nginx-deployment.yaml           # 本地 K3s 部署配置（NodePort）
├── nginx-deployment-gke.yaml       # GKE 部署配置（LoadBalancer）
├── nginx-php-configmap.yaml        # Nginx 和 PHP-FPM 配置
├── php-test-files.yaml             # 測試 PHP 文件
├── podmonitor.yaml                 # PodMonitor 配置（GMP）
├── prometheus-rules.yaml           # 告警規則配置
├── prometheus-adapter.yaml         # Prometheus Adapter 配置（自動擴展）
├── hpa-custom-metrics.yaml         # HPA 配置（5種方案）
├── deploy-gke-gmp.sh              # GKE 一鍵部署腳本
├── deploy.sh                       # 本地快速部署腳本
├── DEPLOYMENT-GUIDE.md             # 基本部署指南
├── GMP-DEPLOYMENT-GUIDE.md         # GMP 詳細指南
├── HPA-GUIDE.md                    # HPA 自動擴展指南
└── UNIX-SOCKET-SUCCESS.md          # Unix Socket 配置說明
```

## 🚀 快速開始

### 本地 K3s 環境

```bash
# 1. 部署應用
kubectl apply -f yaml/nginx-php-configmap.yaml
kubectl apply -f yaml/php-test-files.yaml
kubectl apply -f yaml/nginx-deployment.yaml

# 2. 訪問服務
curl http://localhost:30080/test.php
```

### GKE 生產環境

```bash
# 1. 設置環境變數
export GCP_PROJECT_ID="your-project-id"
export CLUSTER_NAME="nginx-php-cluster"
export GKE_ZONE="us-central1-a"

# 2. 執行一鍵部署腳本
./yaml/deploy-gke-gmp.sh

# 3. 等待 LoadBalancer IP 分配
kubectl get service nginx-service -w
```

## 🎯 主要特性

### 應用層面
- ✅ **Nginx + PHP-FPM**：高性能 Web 伺服器
- ✅ **Unix Socket**：Nginx 和 PHP-FPM 之間使用 Unix Socket 通訊
- ✅ **多容器 Pod**：nginx、php-fpm、php-fpm-exporter 在同一個 Pod
- ✅ **健康檢查**：完整的 liveness 和 readiness probes
- ✅ **資源限制**：合理的 CPU 和記憶體限制

### 監控層面
- ✅ **PHP-FPM Exporter**：匯出 PHP-FPM 指標給 Prometheus
- ✅ **PodMonitor**：自動發現和抓取指標
- ✅ **告警規則**：11 種預定義告警規則
- ✅ **GMP 整合**：完整的 Google Managed Prometheus 支持

### 部署層面
- ✅ **多環境支持**：K3s 本地開發、GKE 生產環境
- ✅ **自動化腳本**：一鍵部署所有組件
- ✅ **配置管理**：使用 ConfigMap 管理配置

## 📊 監控指標

### PHP-FPM 核心指標

| 指標名稱 | 類型 | 說明 |
|---------|------|------|
| `phpfpm_active_processes` | Gauge | 當前活躍進程數 |
| `phpfpm_idle_processes` | Gauge | 當前空閒進程數 |
| `phpfpm_total_processes` | Gauge | 總進程數 |
| `phpfpm_accepted_connections` | Counter | 接受的連接總數 |
| `phpfpm_listen_queue` | Gauge | 等待隊列長度 |
| `phpfpm_max_children_reached` | Counter | 達到最大子進程次數 |
| `phpfpm_slow_requests` | Counter | 慢請求數 |
| `phpfpm_start_since` | Gauge | 啟動時間（秒） |

### 告警規則

1. **PhpFpmHighActiveProcesses** - 活躍進程數過高
2. **PhpFpmLowIdleProcesses** - 空閒進程數過低
3. **PhpFpmMaxChildrenReached** - 達到最大子進程限制
4. **PhpFpmSlowRequests** - 慢請求告警
5. **PhpFpmHighListenQueue** - 請求隊列積壓
6. **PhpFpmHighProcessUtilization** - 進程利用率過高
7. **PhpFpmLowRequestRate** - 請求率異常下降
8. **PhpFpmHighRequestRate** - 請求率異常升高
9. **PhpFpmFrequentRestarts** - 頻繁重啟
10. **PhpFpmNeedScaleOut** - 需要橫向擴展
11. **PhpFpmCanScaleIn** - 可以縮容

## 🔄 自動擴展 (HPA)

本專案支持基於 PHP-FPM 自定義指標的自動擴展。

### 可用的自定義指標

透過 Prometheus Adapter 提供以下指標：

- `phpfpm_active_processes_utilization` - **推薦** 進程利用率 (0-1)
- `phpfpm_request_rate` - **推薦** 請求處理速率 (req/s)
- `phpfpm_listen_queue` - **推薦** 監聽隊列長度
- `phpfpm_active_processes` - 活躍進程數
- `phpfpm_idle_processes` - 閒置進程數
- `phpfpm_total_processes` - 總進程數

### 5 種 HPA 配置方案

1. **基於進程利用率** - 適合一般場景
2. **基於活躍進程數** - 精確控制並發
3. **混合指標（CPU+記憶體+進程）** - 推薦用於生產環境
4. **基於請求隊列** - 適合高流量電商場景
5. **基於請求率** - 適合 API 微服務

### 快速部署 HPA

```bash
# 1. 部署 Prometheus Adapter
kubectl create namespace custom-metrics
kubectl apply -f yaml/prometheus-adapter.yaml

# 2. 驗證自定義指標可用
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .

# 3. 部署 HPA（選擇一個方案）
kubectl apply -f yaml/hpa-custom-metrics.yaml

# 4. 監控 HPA 狀態
kubectl get hpa -w
```

📚 **詳細說明**：請參閱 [HPA-GUIDE.md](./HPA-GUIDE.md)

## 🔧 配置說明

### Nginx 配置
- **Unix Socket 連接**：`fastcgi_pass unix:/run/php/php-fpm.sock`
- **工作進程**：自動根據 CPU 核心數調整
- **Gzip 壓縮**：已啟用
- **日誌格式**：標準 combined 格式

### PHP-FPM 配置
- **進程管理模式**：dynamic
- **最大子進程數**：20
- **啟動進程數**：5
- **最小空閒進程**：5
- **最大空閒進程**：10
- **狀態頁面**：`/fpm_status`
- **Ping 路徑**：`/fpm_ping`

### 資源配置

#### Nginx 容器
```yaml
requests:
  memory: "64Mi"
  cpu: "100m"
limits:
  memory: "128Mi"
  cpu: "200m"
```

#### PHP-FPM 容器
```yaml
requests:
  memory: "128Mi"
  cpu: "200m"
limits:
  memory: "256Mi"
  cpu: "400m"
```

#### PHP-FPM-Exporter 容器
```yaml
requests:
  memory: "64Mi"
  cpu: "100m"
limits:
  memory: "128Mi"
  cpu: "150m"
```

## 📖 詳細文檔

### 基本部署
參考 [DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md)

### GMP 監控
參考 [GMP-DEPLOYMENT-GUIDE.md](./GMP-DEPLOYMENT-GUIDE.md)

### Unix Socket 配置
參考 [UNIX-SOCKET-SUCCESS.md](./UNIX-SOCKET-SUCCESS.md)

## 🔍 故障排查

### 查看 Pod 狀態
```bash
kubectl get pods -l app=nginx
kubectl describe pod <pod-name>
```

### 查看日誌
```bash
# Nginx 日誌
kubectl logs <pod-name> -c nginx

# PHP-FPM 日誌
kubectl logs <pod-name> -c php-fpm

# Exporter 日誌
kubectl logs <pod-name> -c php-fpm-exporter
```

### 測試指標端點
```bash
# 進入 Pod 測試
kubectl exec <pod-name> -c php-fpm-exporter -- wget -qO- http://localhost:9253/metrics

# 或使用 port-forward
kubectl port-forward <pod-name> 9253:9253
curl http://localhost:9253/metrics
```

### 檢查 Unix Socket
```bash
# 檢查 socket 文件
kubectl exec <pod-name> -c php-fpm -- ls -la /run/php/

# 檢查 PHP-FPM 配置
kubectl exec <pod-name> -c php-fpm -- php-fpm -tt
```

### GMP 故障排查
```bash
# 查看 GMP 系統 Pods
kubectl get pods -n gmp-system

# 查看 collector 日誌
kubectl logs -n gmp-system -l app.kubernetes.io/name=collector

# 查看 operator 日誌
kubectl logs -n gmp-system -l app.kubernetes.io/name=operator

# 檢查 PodMonitor
kubectl describe podmonitor nginx-php-fpm-monitor
```

## 🌐 訪問服務

### 本地 K3s
```bash
# 通過 NodePort 訪問
curl http://localhost:30080/test.php
curl http://localhost:30080/health.php
curl http://localhost:30080/index.php
```

### GKE
```bash
# 獲取 LoadBalancer IP
EXTERNAL_IP=$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 訪問服務
curl http://$EXTERNAL_IP/test.php
curl http://$EXTERNAL_IP/health.php
```

## 📈 性能調優

### 增加 PHP-FPM 進程數
修改 `nginx-php-configmap.yaml` 中的 `www.conf`：
```ini
pm.max_children = 30          # 增加最大子進程
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 15
```

### 橫向擴展
```bash
# 增加副本數
kubectl scale deployment nginx-deployment --replicas=5

# 或使用 HPA（需要 metrics-server）
kubectl autoscale deployment nginx-deployment --min=3 --max=10 --cpu-percent=70
```

### 調整資源限制
根據實際負載修改 Deployment 中的 resources 配置。

## 💰 成本優化

### GKE 成本優化建議
1. **使用搶佔式 VM**：可節省 80% 成本
2. **啟用 Cluster Autoscaler**：根據負載自動調整節點數
3. **調整監控抓取頻率**：從 30s 改為 60s
4. **使用區域性集群**：而不是 Zonal 集群以提高可用性
5. **設置 Pod 驅逐策略**：合理利用節點資源

### GMP 成本優化
1. **過濾不需要的指標**：在 PodMonitor 中使用 `metricRelabelings`
2. **減少抓取頻率**：評估是否需要 30s 的抓取間隔
3. **設置數據保留策略**：不需要長期保留所有指標

## 🔐 安全建議

### 生產環境必做
1. ✅ 使用 HTTPS/TLS（Ingress + cert-manager）
2. ✅ 啟用 Network Policy 限制 Pod 間通訊
3. ✅ 使用 Secret 管理敏感配置
4. ✅ 定期更新容器映像
5. ✅ 啟用 Pod Security Standards
6. ✅ 配置 RBAC 權限控制
7. ✅ 啟用 Cloud Armor（GKE）
8. ✅ 設置 WAF 規則

## 📞 支援

### 相關資源
- [Google Managed Prometheus 文檔](https://cloud.google.com/stackdriver/docs/managed-prometheus)
- [PHP-FPM 官方文檔](https://www.php.net/manual/en/install.fpm.php)
- [Nginx 官方文檔](https://nginx.org/en/docs/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)

## 📝 更新日誌

### 2025-12-12
- ✅ 初始版本發布
- ✅ 支持 Unix Socket 連接
- ✅ 整合 Google Managed Prometheus
- ✅ 提供完整的告警規則
- ✅ 一鍵部署腳本

## 📄 授權

本配置由 AI 生成，可自由使用和修改。

