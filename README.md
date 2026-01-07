# sre_keda_lab

本專案根目錄的 README 主要提供快速導覽，避免重複維護多份說明文件。

## 文件導覽

- KEDA（事件驅動自動擴縮）說明：[`yaml/keda/README.md`](yaml/keda/README.md)
- Custom Metrics Stackdriver Adapter 說明：[`yaml/custom-metrics-stackdriver-adapter/README.md`](yaml/custom-metrics-stackdriver-adapter/README.md)

## yaml/keda 資料夾摘要

`yaml/keda/` 用於在 GKE 上示範以 KEDA 進行事件/指標驅動的自動擴縮；範例工作負載是 Nginx + PHP-FPM（含 exporter），並可搭配 Google Managed Prometheus（GMP）與 Pub/Sub。

- 部署腳本
	- `gen_pub_msg.sh`：對 Pub/Sub topic 發送測試訊息（用於製造 backlog/流量情境）。
- Kubernetes / KEDA manifests
	- `nginx-php-configmap.yaml`：Nginx 設定與 PHP-FPM（www.conf/php.ini）設定。
	- `php-test-files.yaml`：測試用 PHP 頁面（phpinfo、health、慢回應等）。
	- `nginx-deployment.yaml`：Nginx + PHP-FPM + php-fpm_exporter 的 Deployment，並包含 Service（GKE LoadBalancer）與 `PodMonitoring`（抓取 exporter metrics）。
	- `rule.yaml`：GMP recording rules，將 PHP-FPM 指標整理成可供查詢/擴縮使用的 recording metric。
	- `keda-scaledobject.yaml`：KEDA `TriggerAuthentication`（GCP Workload Identity）與 `ScaledObject`；示範 Prometheus（GMP PromQL）、CPU、Pub/Sub backlog 等觸發條件。
	- `pod-use-keda-ksa.yaml`：除錯用 Pod 範例，使用 `keda` namespace 的 `keda-operator` KSA（用來驗證 Workload Identity/權限綁定）。
