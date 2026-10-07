# Deploys the image that CI published to GHCR.
#
#   nomad job run -var "app_tag=$(git rev-parse HEAD)" nomad/nginx-app.nomad.hcl
#
# app_tag must be a full commit SHA that the CI publish job pushed.

variable "app_tag" {
  type        = string
  description = "Image tag to deploy: the full git commit SHA pushed to GHCR by CI."

  validation {
    condition     = var.app_tag != "latest" && var.app_tag != ""
    error_message = "Deploy an immutable commit-SHA tag, not \"latest\"."
  }
}

job "nginx-app" {
  datacenters = ["dc1"]
  type        = "service"

  # Rolling deployment: replace one allocation at a time, require it to stay
  # healthy for 10s, give up after 2m and roll back to the last good version.
  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "2m"
    auto_revert      = true
  }

  group "web" {
    count = 1

    # Restart the task in place up to 2 times per minute, then fail the
    # allocation so the reschedule policy can move it.
    restart {
      attempts = 2
      interval = "1m"
      delay    = "10s"
      mode     = "fail"
    }

    # Place a failed allocation again (on another client if one exists),
    # up to 3 times in 5 minutes, with exponential back-off.
    reschedule {
      attempts       = 3
      interval       = "5m"
      delay          = "15s"
      delay_function = "exponential"
      max_delay      = "2m"
      unlimited      = false
    }

    network {
      # Dynamic host port, mapped to the container's port 8080.
      port "http" {
        to = 8080
      }
    }

    service {
      name     = "nginx-app"
      port     = "http"
      provider = "consul"
      tags     = ["web", "nginx"]

      check {
        name     = "nginx-healthz"
        type     = "http"
        path     = "/healthz"
        interval = "10s"
        timeout  = "2s"

        # Restart the task if the check fails 3 times in a row.
        check_restart {
          limit = 3
          grace = "10s"
        }
      }
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "ghcr.io/steven201nmk/devops-intern-final/nginx-app:${var.app_tag}"
        ports = ["http"]

        # Docker labels read by Promtail (monitoring/promtail-config.yaml).
        # Nomad itself adds com.hashicorp.nomad.alloc_id.
        labels {
          job     = "nginx-app"
          service = "nginx-app"
        }
      }

      resources {
        cpu    = 100 # MHz
        memory = 64  # MB
      }
    }
  }
}
