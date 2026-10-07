# Pinned base image: never "latest", so every build starts from the same layers.
FROM nginx:1.27-alpine

# Build identifier, injected by CI with --build-arg BUILD_SHA=<git sha>.
ARG BUILD_SHA=unknown
ENV BUILD_SHA=$BUILD_SHA

LABEL org.opencontainers.image.title="nginx-app" \
      org.opencontainers.image.source="https://github.com/steven201nmk/devops-intern-final" \
      org.opencontainers.image.revision=$BUILD_SHA

# NGINX runs as the unprivileged "nginx" user, so give it the directories it writes to.
RUN mkdir -p /var/run /var/cache/nginx /var/log/nginx && \
    chown -R nginx:nginx /var/run /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

# Custom config: listens on 8080, serves /healthz, keeps the PID and temp files in /tmp.
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html

# Stamp the build SHA into the page.
RUN sed -i "s/BUILD_SHA_PLACEHOLDER/${BUILD_SHA}/g" /usr/share/nginx/html/index.html && \
    chown -R nginx:nginx /usr/share/nginx/html

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=2s --start-period=5s --retries=3 \
  CMD curl -fsS http://localhost:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
