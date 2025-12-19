# Nginx + PHP-FPM + PHP-FPM-Exporter 部署指南

## AI生成

本指南說明如何在 GKE 上部署完整的 Nginx + PHP-FPM 環境，包含 Prometheus 監控支援。

## 架構說明

此部署包含三個容器在同一個 Pod 中：

1. **Nginx**: Web 伺服器，處理 HTTP 請求
2. **PHP-FPM**: PHP FastCGI 進程管理器，執行 PHP 程式碼
3. **PHP-FPM-Exporter**: 匯出 PHP-FPM 指標給 Prometheus

容器間透過共享的 Unix Socket (`/run/php/php-fpm.sock`) 進行通訊。

## 部署步驟

### 1. 部署 ConfigMaps（配置文件）

首先部署所有的配置文件：

```bash
# 部署 Nginx 和 PHP-FPM 配置
kubectl apply -f yaml/nginx-php-configmap.yaml

# 部署測試 PHP 文件
kubectl apply -f yaml/php-test-files.yaml
```

### 2. 部署 Deployment 和 Services

```bash
# 部署主要應用
kubectl apply -f yaml/nginx-deployment.yaml
```

### 3. 驗證部署狀態

```bash
# 查看 Pod 狀態（應該看到 3 個容器都在運行）
kubectl get pods -l app=nginx

# 查看詳細資訊
kubectl describe pod -l app=nginx

# 查看 Services
kubectl get services

# 等待 LoadBalancer 獲得外部 IP
kubectl get service nginx-service -w
```

### 4. 測試應用

取得外部 IP 後，可以透過瀏覽器或 curl 測試：

```bash
# 取得外部 IP
EXTERNAL_IP=$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 測試 PHP 資訊頁面
curl http://$EXTERNAL_IP/index.php

# 測試基本功能
curl http://$EXTERNAL_IP/test.php

# 測試健康檢查
curl http://$EXTERNAL_IP/health.php

# 查看 PHP-FPM Exporter 指標（從 Pod 內部）
POD_NAME=$(kubectl get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -c php-fpm-exporter -- wget -qO- http://localhost:9253/metrics
```

## 文件說明

### nginx-deployment.yaml
主要的 Deployment 和 Service 配置，包含：
- Nginx 容器配置
- PHP-FPM 容器配置
- PHP-FPM-Exporter 容器配置
- 共享 volume 配置
- LoadBalancer Service（對外服務）
- ClusterIP Service（Prometheus metrics）

### nginx-php-configmap.yaml
包含 Nginx 和 PHP-FPM 的配置文件：
- `nginx.conf`: Nginx 主配置
- `default.conf`: Nginx 站點配置（包含 PHP-FPM fastcgi 設定）
- `www.conf`: PHP-FPM pool 配置（包含 Unix socket 和狀態頁面）
- `php.ini`: PHP 運行時配置

### php-test-files.yaml
測試用的 PHP 文件：
- `index.php`: PHP 資訊頁面（phpinfo）
- `test.php`: 基本測試頁面
- `health.php`: 健康檢查端點（JSON 格式）

## 監控整合

### Prometheus 設定

PHP-FPM-Exporter 會在 `9253` 端口暴露指標，可以透過 `php-fpm-metrics` Service 訪問。

在 Prometheus 配置中添加：

```yaml
scrape_configs:
  - job_name: 'php-fpm'
    kubernetes_sd_configs:
      - role: service
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        regex: php-fpm-metrics
        action: keep
```

## 常見問題排查

### Pod 啟動失敗

```bash
# 查看 Pod 事件
kubectl describe pod -l app=nginx

# 查看特定容器日誌
kubectl logs <pod-name> -c nginx
kubectl logs <pod-name> -c php-fpm
kubectl logs <pod-name> -c php-fpm-exporter
```

### PHP-FPM Socket 連接問題

```bash
# 進入 nginx 容器檢查 socket
kubectl exec -it <pod-name> -c nginx -- ls -la /run/php/

# 進入 php-fpm 容器檢查配置
kubectl exec -it <pod-name> -c php-fpm -- php-fpm -tt
```

### Exporter 無法抓取指標

```bash
# 進入 exporter 容器測試
kubectl exec -it <pod-name> -c php-fpm-exporter -- wget -qO- http://localhost:9253/metrics
```

## 自定義配置

### 修改 PHP-FPM 進程數

編輯 `nginx-php-configmap.yaml` 中的 `www.conf`：

```conf
pm.max_children = 20        # 最大子進程數
pm.start_servers = 5        # 啟動時的進程數
pm.min_spare_servers = 5    # 最小空閒進程數
pm.max_spare_servers = 10   # 最大空閒進程數
```

### 添加自己的 PHP 應用

替換 `php-test-files.yaml` 中的文件，或使用 Persistent Volume 掛載應用程式碼。

## 清理資源

```bash
# 刪除所有資源
kubectl delete -f yaml/nginx-deployment.yaml
kubectl delete -f yaml/nginx-php-configmap.yaml
kubectl delete -f yaml/php-test-files.yaml
```

## 安全建議

1. 在生產環境中，建議使用 Ingress 而非 LoadBalancer
2. 啟用 HTTPS/TLS 加密
3. 限制 PHP-FPM status 頁面的訪問
4. 定期更新容器映像以修補安全漏洞
5. 使用 NetworkPolicy 限制 Pod 間通訊
6. 考慮使用 Secret 管理敏感配置

## 效能調優

1. 根據實際負載調整 `replicas` 數量
2. 調整 PHP-FPM 進程管理參數
3. 設定適當的資源 requests 和 limits
4. 啟用 Nginx 快取機制
5. 考慮使用 HPA (Horizontal Pod Autoscaler) 自動擴展
