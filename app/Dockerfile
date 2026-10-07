FROM nginx:1.27-alpine

ARG BUILD_SHA=unknown
ENV BUILD_SHA=$BUILD_SHA

RUN mkdir -p /var/run /var/cache/nginx /var/log/nginx && \
    chown -R nginx:nginx /var/run /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

COPY nginx.conf /etc/nginx/nginx.conf

RUN grep -nE "pid|listen" /etc/nginx/nginx.conf

COPY index.html /usr/share/nginx/html/index.html

RUN sed -i "s/BUILD_SHA_PLACEHOLDER/${BUILD_SHA}/g" /usr/share/nginx/html/index.html && \
    chown -R nginx:nginx /usr/share/nginx/html

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=2s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
