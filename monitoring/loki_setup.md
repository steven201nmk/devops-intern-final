# Loki Log Aggregation Setup

## Starting the Stack
The stack was initiated using docker-compose:
cd monitoring
docker-compose up -d

## Applied Labels
Promtail is configured to scrape Docker containers and dynamically append labels:
- container: Derived from the docker container name.
- nomad_alloc_id: Pulled from the Nomad allocation Docker label.
- job: Pulled from the Nomad job Docker label.

## Querying and Results
To isolate NGINX access logs and filter for non-200 status codes:
{job="nginx-app"} |= "HTTP" |~ "status\":[4-5][0-9][0-9]"
