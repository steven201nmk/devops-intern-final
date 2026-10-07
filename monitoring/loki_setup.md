# Loki Log Aggregation Setup

Loki stores the logs, Promtail ships them, and Grafana queries them.
Promtail discovers containers through the Docker API, so it picks up the NGINX
container whether it was started by Nomad (Task 5) or by `docker run` (Task 3).

```text
nginx container stdout ──> Docker engine ──> Promtail (docker_sd) ──> Loki :3100 <── Grafana :3000
```

| File | Purpose |
|---|---|
| `docker-compose.yaml` | Starts Loki 3.0.0, Promtail 3.0.0 and Grafana 10.4.0 (pinned versions) |
| `loki-config.yaml` | Single-binary Loki, filesystem storage, TSDB schema v13, no auth |
| `promtail-config.yaml` | Docker service discovery and the relabel rules that create the labels below |

## 1. How I started the stack

```bash
cd monitoring
docker compose up -d
docker compose ps
curl -s http://localhost:3100/ready        # prints "ready" once Loki is up (about 15s)
```

```text
$ cd monitoring && docker compose up -d
 Network monitoring_monitoring Created
 Container monitoring-loki-1 Created
 Container monitoring-promtail-1 Created
 Container monitoring-grafana-1 Created
 Container monitoring-loki-1 Started
 Container monitoring-promtail-1 Started
 Container monitoring-grafana-1 Started
(image pull progress omitted)

$ docker compose ps
SERVICE    IMAGE                    STATUS          PORTS
grafana    grafana/grafana:10.4.0   Up 10 minutes   0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp
loki       grafana/loki:3.0.0       Up 10 minutes   0.0.0.0:3100->3100/tcp, [::]:3100->3100/tcp
promtail   grafana/promtail:3.0.0   Up 10 minutes   

$ curl -s http://localhost:3100/ready
ready
```

Grafana data source: open <http://localhost:3000>, go to **Connections → Data sources → Add data source → Loki**, set the URL to `http://loki:3100`, then click **Save & test**.

## 2. Label set

| Label | Where the value comes from | Example |
|---|---|---|
| `job` | Docker label `job`, set in the Nomad job's `labels` block. Containers without it get `docker` | `nginx-app` |
| `container` | Docker container name, with the leading `/` removed | `nginx-07e9b12d-d3ef-1ff1-2791-6d0fd2c372bc` |
| `nomad_alloc_id` | Docker label `com.hashicorp.nomad.alloc_id`, which Nomad's docker driver always adds | `07e9b12d-d3ef-1ff1-2791-6d0fd2c372bc` |
| `service` | Docker label `service` (Nomad job), or the compose service name for the monitoring containers | `nginx-app` |
| `stream` | `stdout` or `stderr`. NGINX writes access logs to stdout and errors to stderr | `stdout` |

Check which labels reached Loki:

```bash
curl -s http://localhost:3100/loki/api/v1/labels
curl -s http://localhost:3100/loki/api/v1/label/job/values
```

```text
$ curl -s http://localhost:3100/loki/api/v1/labels
{"status":"success","data":["container","job","nomad_alloc_id","service","service_name","stream"]}

$ curl -s http://localhost:3100/loki/api/v1/label/job/values
{"status":"success","data":["docker","nginx-app"]}

$ curl -s http://localhost:3100/loki/api/v1/label/container/values
{"status":"success","data":["monitoring-grafana-1","monitoring-loki-1","monitoring-promtail-1","nginx-07e9b12d-d3ef-1ff1-2791-6d0fd2c372bc","nginx-app"]}

$ curl -s http://localhost:3100/loki/api/v1/label/nomad_alloc_id/values
{"status":"success","data":["07e9b12d-d3ef-1ff1-2791-6d0fd2c372bc"]}

$ curl -s http://localhost:3100/loki/api/v1/label/service/values
{"status":"success","data":["grafana","loki","nginx-app","promtail"]}

$ curl -s http://localhost:3100/loki/api/v1/label/stream/values
{"status":"success","data":["stderr","stdout"]}
```

`service_name` is added by Loki 3 itself, derived from the `service` label.

## 3. Generating test traffic

With the Nomad allocation running (replace `<port>` with the dynamic port from `nomad alloc status`):

```bash
for i in 1 2 3 4 5; do
  curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:<port>/"
  curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:<port>/does-not-exist"
done
```

`/healthz` has `access_log off` in `app/nginx.conf`, so the Consul health checks every 10 s don't flood the logs.

## 4. LogQL queries

```logql
# Q1 - everything NGINX wrote to stdout (start-up messages + access log)
{job="nginx-app", stream="stdout"}

# Q2 - only non-2xx responses (line filter on the status field of the "combined" log format)
{job="nginx-app", stream="stdout"} |~ "\" [45][0-9]{2} "

# Q3 - the same, but parsing the line into fields first
{job="nginx-app", stream="stdout"}
  |= "HTTP/"
  | pattern `<ip> - <_> [<_>] "<method> <path> <_>" <status> <_>`
  | status != "200"

# Q4 - number of requests per status code over the last 10 minutes
sum by (status) (
  count_over_time({job="nginx-app", stream="stdout"} |= "HTTP/"
    | pattern `<ip> - <_> [<_>] "<method> <path> <_>" <status> <_>` [10m])
)
```

`stream="stdout"` keeps NGINX's error log (stderr) out. `|= "HTTP/"` keeps only access-log lines. The official image also prints its `/docker-entrypoint.sh: ...` start-up messages to stdout. Those lines don't match the pattern, so their `status` label comes out empty, and `status != "200"` would count them as matches.

## 5. Results

I sent two rounds of traffic (5 × `/` and 5 × `/does-not-exist` each, at 13:50 and 14:00 local time) and ran the queries over the last 15 minutes:

- **Q1** returned 20 lines: the 10 `200` and 10 `404` access-log lines. The container's start-up messages had already aged out of the 15-minute window.
- **Q2** and **Q3** each returned only the 10 `GET /does-not-exist ... 404` lines. Q3 also exposes `method`, `path` and `status` as labels.
- **Q4** counted `status="200"` → 10 and `status="404"` → 10.

```text
Q2  {job="nginx-app", stream="stdout"} |~ "\" [45][0-9]{2} "
  172.17.0.1 - - [07/Oct/2026:05:50:43 +0000] "GET /does-not-exist HTTP/1.1" 404 153 "-" "curl/8.5.0"
  ... (10 lines, every one a 404 for /does-not-exist)

Q3  {job="nginx-app", stream="stdout"} |= "HTTP/" | pattern `...` | status != "200"
  172.17.0.1 - - [07/Oct/2026:06:00:39 +0000] "GET /does-not-exist HTTP/1.1" 404 153 "-" "curl/8.5.0"
  ... (10 lines, parsed labels: method="GET", path="/does-not-exist", status="404")

Q4  sum by (status) (count_over_time(... [15m]))
  {status="200"} -> 10
  {status="404"} -> 10
```

![Grafana Explore showing only the 404 lines](../docs/screenshots/grafana-explore.png)

## 6. Problems I hit and how I fixed them

1. **The first query matched nothing.** My original query searched for `status":4xx`, as if NGINX wrote JSON logs. NGINX's default `combined` format is plain text, like `"GET /x HTTP/1.1" 404 153`. I fixed it by matching `" 4xx "` (Q2) or parsing the line with `pattern` (Q3).
2. **The `job` label was missing.** Promtail read `job` from the Docker label `com.hashicorp.nomad.job_name`, but Nomad's docker driver only adds `com.hashicorp.nomad.alloc_id` unless the client sets `extra_labels`. I fixed it by setting `job` and `service` Docker labels in the Nomad job's `labels` block, so it works on any Nomad agent without extra client config.
3. **Q3 also returned NGINX's start-up lines.** The first run of Q3 returned 14 lines instead of 5, and Q4 had an extra `{} -> 9` group. The official nginx image prints `/docker-entrypoint.sh: ...` messages to stdout. They don't match the access-log pattern, so `status` is empty, and empty `!= "200"`. I fixed it by adding `|= "HTTP/"` before `pattern` (commit `84cc347`).
4. **Grafana Explore showed "No data" at first,** even though the label browser listed `job=nginx-app`. Building the query in Builder mode does not run it. Clicking **Run query**, with a time range that covered the test traffic, showed the logs. Later, the data source picker had switched to Grafana's built-in "-- Grafana --" test source, which draws a random-walk graph. Switching back to **loki** fixed that.
