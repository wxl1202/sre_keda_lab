# Unix Socket 配置成功總結

## AI生成

## ✅ 問題已完全解決

成功將 Nginx + PHP-FPM 配置為使用 Unix Socket 連接，所有組件正常運作。

## 🔧 關鍵修復

### 1. **刪除衝突的配置文件**
PHP-FPM 官方映像包含 `zz-docker.conf`，它會覆蓋我們的配置並強制監聽 TCP 9000。

```bash
rm -f /usr/local/etc/php-fpm.d/zz-docker.conf
```

### 2. **使用前台模式啟動**
```bash
php-fpm -F  # 前台運行，適合容器環境
```

### 3. **修改健康檢查**
從 TCP 端口檢查改為檢查 Socket 文件是否存在：

```yaml
livenessProbe:
  exec:
    command:
    - test
    - -S
    - /run/php/php-fpm.sock
```

### 4. **配置 Unix Socket**

**Nginx 配置：**
```nginx
fastcgi_pass unix:/run/php/php-fpm.sock;
```

**PHP-FPM 配置：**
```ini
listen = /run/php/php-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0666
```

**PHP-FPM Exporter 配置：**
```yaml
PHP_FPM_SCRAPE_URI: "unix:///run/php/php-fpm.sock;/fpm_status"
```

## 📊 驗證結果

### Pod 狀態
```
NAME                               READY   STATUS    RESTARTS   AGE
nginx-deployment-9f8b85c48-bjjq5   3/3     Running   0          20s
```

### Socket 文件
```
srw-rw-rw-  1 www-data www-data  0 php-fpm.sock
```

### PHP 測試
```bash
$ curl http://localhost:30080/test.php
<h1>PHP-FPM 運行正常</h1>
<p>PHP 版本: 8.2.29</p>
```

### Prometheus 指標
```bash
$ kubectl exec pod -c php-fpm-exporter -- wget -qO- localhost:9253/metrics
phpfpm_active_processes{pool="www",scrape_uri="unix:///run/php/php-fpm.sock;/fpm_status"} 1
```

## 🎯 Unix Socket vs TCP 比較

### Unix Socket 優勢
- ✅ **性能更好**：本地通訊，無需 TCP/IP 協議棧
- ✅ **延遲更低**：直接文件系統通訊
- ✅ **安全性更高**：只能本地訪問，可設置文件權限
- ✅ **資源消耗更少**：不佔用網路端口

### TCP 優勢
- ✅ **配置更簡單**：不需要處理文件權限
- ✅ **健康檢查更容易**：可直接使用 tcpSocket probe
- ✅ **跨容器通訊**：可以跨 Pod 通訊（如需要）

## 📝 配置文件說明

### PHP-FPM 啟動腳本
```yaml
command: ['sh', '-c']
args:
- |
  echo "準備啟動 PHP-FPM..."
  # 清理舊文件
  rm -f /run/php/php-fpm.sock || true
  rm -f /run/php/*.pid || true
  # 刪除默認配置（重要！）
  rm -f /usr/local/etc/php-fpm.d/zz-docker.conf || true
  # 測試配置
  php-fpm -t
  # 前台啟動
  php-fpm -F
```

## 🚀 部署方式

### K3s 本機環境
```bash
# 應用配置
kubectl apply -f yaml/

# 訪問服務
curl http://localhost:30080/test.php
```

### GKE 雲端環境
將 `nginx-deployment.yaml` 中的 Service type 改為 LoadBalancer：
```yaml
spec:
  type: LoadBalancer  # 改為 LoadBalancer
```

## 🔍 故障排查

### 檢查 Socket 文件
```bash
kubectl exec pod-name -c php-fpm -- ls -la /run/php/
```

### 檢查 PHP-FPM 配置
```bash
kubectl exec pod-name -c php-fpm -- php-fpm -tt
```

### 檢查 Nginx 連接
```bash
kubectl exec pod-name -c nginx -- curl -v http://localhost/test.php
```

### 查看日誌
```bash
kubectl logs pod-name -c php-fpm
kubectl logs pod-name -c nginx
```

## 💡 最佳實踐

1. **使用 emptyDir volume** 在同一 Pod 內的容器間共享 socket
2. **設置正確的文件權限** (0666) 確保 Nginx 可以訪問
3. **刪除衝突配置** (zz-docker.conf) 避免被覆蓋
4. **使用前台模式** (php-fpm -F) 適合容器環境
5. **調整健康檢查** 檢查 socket 文件而不是 TCP 端口
6. **配置狀態頁面** 供 Prometheus Exporter 使用

## 📚 相關文件

- `nginx-deployment.yaml` - 主要部署配置
- `nginx-php-configmap.yaml` - Nginx 和 PHP-FPM 配置
- `php-test-files.yaml` - 測試 PHP 文件
- `DEPLOYMENT-GUIDE.md` - 完整部署指南
