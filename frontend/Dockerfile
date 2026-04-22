# ---------------------------------------------------------------------------
# Frontend Dockerfile (React + nginx)
# Security hardening:
#   - Multi-stage build to strip node_modules from final image
#   - Uses nginxinc/nginx-unprivileged so it runs as UID 101
#   - Listens on 8080 (unprivileged port)
# ---------------------------------------------------------------------------
FROM node:22-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .
RUN npm run build

# -----------------------------------------------------------------------------
# Production stage — unprivileged nginx (runs as UID 101, no root needed)
# -----------------------------------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.27-alpine

USER root
RUN rm -rf /etc/nginx/conf.d/default.conf

COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html

USER 101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
