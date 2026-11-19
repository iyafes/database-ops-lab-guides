# "Backup host": ssh client, cron, flock and its own Docker daemon (used only for restore tests).
FROM docker:dind
RUN apk add --no-cache bash sudo openssh-client coreutils findutils util-linux shadow openssl \
 && ln -sf /usr/local/bin/docker /usr/bin/docker \
 && adduser -D -s /bin/bash backupadm \
 && mkdir -p /backup/mariadb && chown backupadm:backupadm /backup/mariadb && chmod 750 /backup/mariadb \
 && addgroup backupadm docker 2>/dev/null || true
COPY entrypoint.sh /usr/local/bin/lab-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/lab-entrypoint.sh"]
