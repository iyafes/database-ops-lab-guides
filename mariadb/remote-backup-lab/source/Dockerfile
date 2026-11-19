# "Source host": sshd + sudo + its own Docker daemon (MariaDB will run inside it).
FROM docker:dind
RUN apk add --no-cache bash sudo openssh-server openssh-client coreutils findutils util-linux shadow openssl \
 && ln -sf /usr/local/bin/docker /usr/bin/docker \
 && adduser -D -s /bin/bash backupadm \
 && echo "backupadm:$(head -c 24 /dev/urandom | base64)" | chpasswd \
 && printf 'PasswordAuthentication no\nPermitRootLogin no\nPubkeyAuthentication yes\n' > /etc/ssh/sshd_config.d/lab.conf
COPY entrypoint.sh /usr/local/bin/lab-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/lab-entrypoint.sh"]
