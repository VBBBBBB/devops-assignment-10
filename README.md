# Assignment 10: Monitoring and Observability Using Prometheus and Grafana

A ready-to-run monitoring stack that collects host metrics with **Node Exporter**,
stores them in **Prometheus**, and visualizes them in a provisioned **Grafana**
dashboard with three panels (CPU, memory, system load) plus Prometheus alert rules.

## Project Structure
```
Ass10/
├── docker-compose.yml                     # Prometheus + Node Exporter + Grafana
├── prometheus/
│   ├── prometheus.yml                     # Scrape configuration
│   └── alert-rules.yml                    # CPU / memory / load alerts
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/prometheus.yml     # Auto-provision Prometheus datasource
│   │   └── dashboards/dashboards.yml      # Dashboard provider
│   └── dashboards/
│       └── devops-dashboard.json          # Provisioned dashboard (3 panels)
├── REPORT.md
└── README.md
```

## Start the Stack
```bash
docker compose up -d
```
| Service | URL | Credentials |
| :--- | :--- | :--- |
| Prometheus | http://localhost:9090 | - |
| Grafana | http://localhost:3000 | admin / admin |
| Node Exporter | http://localhost:9100/metrics | - |

## Verify Targets
Open http://localhost:9090/targets - the `prometheus` and `node-exporter` targets
should both be **UP**.

## Grafana Dashboard
The `DevOps System Monitoring` dashboard is auto-provisioned under the **DevOps**
folder with three panels:
- **CPU Utilization** - `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
- **Memory Usage** - `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100`
- **System Load (1m)** - `node_load1`

## Generate Load
```bash
# Linux/macOS
yes > /dev/null &        # spawn CPU load
sleep 60 && kill %1
```
Then watch the dashboard update in near real time.

## Stop and Clean Up
```bash
docker compose down -v
```
