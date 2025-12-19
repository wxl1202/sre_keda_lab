# Nginx + PHP-FPM + PHP-FPM Exporter with Unix Socket

这个项目部署一个包含以下组件的 Kubernetes 应用：

- **Nginx**: Web 服务器
- **PHP-FPM**: PHP FastCGI 进程管理器
- **PHP-FPM Exporter**: 用于 Prometheus 监控的 metrics 导出器

## 架构特点

### Unix Socket 通信
- Nginx 和 PHP-FPM 通过 Unix socket (`/var/run/php-fpm/php-fpm.sock`) 通信
- 相比 TCP 连接，Unix socket 具有更好的性能和安全性
- 共享的 `emptyDir` 卷用于存放 socket 文件

### 双 Pool 配置
- **主 Pool (www)**: 处理实际的 PHP 请求，使用 Unix socket
- **状态 Pool (status)**: 专门用于状态监控，使用 TCP (127.0.0.1:9000)

## 文件结构

```
yaml/
├── deployment.yaml    # 主要的应用部署
├── service.yaml       # 服务定义
└── configmaps.yaml    # 配置文件
```

## 快速部署

```bash
# 部署应用
./deploy.sh

# 测试连接
./test-unix-socket.sh
```

## 配置详情

### Nginx 配置
- 监听端口 80
- 通过 Unix socket 连接到 PHP-FPM: `unix:/var/run/php-fpm/php-fpm.sock`
- 包含健康检查端点: `/nginx-health`

### PHP-FPM 配置

#### 主 Pool (www)
```ini
listen = /var/run/php-fpm/php-fpm.sock
listen.mode = 0666
pm = dynamic
pm.max_children = 50
```

#### 状态 Pool (status)
```ini
listen = 127.0.0.1:9000
pm.status_path = /status
ping.path = /ping
pm = static
pm.max_children = 1
```

### PHP-FPM Exporter
- 监听端口: 9253
- Metrics 端点: `/metrics`
- 连接到状态 pool: `tcp://127.0.0.1:9000/status`

## 端点测试

### 应用端点
```bash
# 端口转发
kubectl port-forward service/nginx-php-app-service 8080:80

# 测试主页
curl http://localhost:8080/

# 健康检查
curl http://localhost:8080/health.php

# Nginx 健康检查
curl http://localhost:8080/nginx-health

# PHP 信息页
curl http://localhost:8080/info.php
```

### 监控端点
```bash
# 端口转发 metrics
kubectl port-forward service/nginx-php-app-metrics 9253:9253

# PHP-FPM metrics
curl http://localhost:9253/metrics

# PHP-FPM 状态
kubectl exec -it deployment/nginx-php-app -c php-fpm -- curl -s http://127.0.0.1:9000/status
```

## 故障排除

### 检查 Unix Socket
```bash
# 检查 socket 文件
kubectl exec -it deployment/nginx-php-app -c php-fpm -- ls -la /var/run/php-fpm/

# 检查权限
kubectl exec -it deployment/nginx-php-app -c nginx -- ls -la /var/run/php-fpm/
```

### 检查进程状态
```bash
# PHP-FPM 进程
kubectl exec -it deployment/nginx-php-app -c php-fpm -- ps aux | grep php-fpm

# Nginx 配置测试
kubectl exec -it deployment/nginx-php-app -c nginx -- nginx -t
```

### 查看日志
```bash
# Nginx 日志
kubectl logs deployment/nginx-php-app -c nginx

# PHP-FPM 日志
kubectl logs deployment/nginx-php-app -c php-fpm

# Exporter 日志
kubectl logs deployment/nginx-php-app -c php-fpm-exporter
```

## 性能优势

1. **Unix Socket vs TCP**:
   - 减少网络开销
   - 更低的延迟
   - 更好的安全性（本地文件系统权限控制）

2. **资源使用**:
   - Nginx: 100m CPU, 128Mi 内存（请求）
   - PHP-FPM: 150m CPU, 256Mi 内存（请求）
   - Exporter: 25m CPU, 32Mi 内存（请求）

## 扩展说明

### 水平扩展
```bash
kubectl scale deployment nginx-php-app --replicas=3
```

### 监控集成
应用已配置 Prometheus 注解，可以直接被 Prometheus 发现和抓取：
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9253"
  prometheus.io/path: "/metrics"
```
