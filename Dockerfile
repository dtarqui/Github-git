FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
	KEYS_DIR=/git-server/keys \
	HTTP_DATA_DIR=/git-server/http \
	HTTP_HTPASSWD_FILE=/git-server/http/.htpasswd \
	HTTP_AUTH_REQUIRED=false \
	HTTP_PUSH_AUTH_REQUIRED=false \
	HTTP_USER=gitadmin \
	HTTP_PASSWORD= \
	REPOS_DIR=/git-server/repos \
	AUTO_CREATE_BARE_REPO=true \
	DEFAULT_BARE_REPO=proyecto.git

LABEL org.opencontainers.image.title="git-ssh-server" \
	org.opencontainers.image.description="Pure Git + OpenSSH server without external managers" \
	org.opencontainers.image.vendor="local-repo" \
	org.opencontainers.image.source="local-workspace"

# Install Git + OpenSSH server + Apache for Git Smart HTTP.
# Retries/timeouts help when Ubuntu mirrors or DNS are temporarily flaky.
RUN apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout="30" update \
	&& apt-get install -y --no-install-recommends --fix-missing \
		git \
		openssh-server \
		apache2 \
		apache2-utils \
		ca-certificates \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

# Create git user with git-shell to prevent interactive shell access.
RUN useradd -m -d /home/git -s /usr/bin/git-shell git \
	&& passwd -d git \
	&& mkdir -p /home/git/.ssh /git-server/keys /git-server/repos /git-server/http /var/run/sshd \
	&& rm -rf /home/git/repos \
	&& ln -s /git-server/repos /home/git/repos \
	&& usermod -a -G git www-data \
	&& git config --system --add safe.directory '*' \
	&& chown -R git:git /home/git /git-server \
	&& chmod 700 /home/git/.ssh \
	&& a2dissite 000-default.conf \
	&& a2enmod cgi alias env setenvif auth_basic authn_file \
	&& printf '%s\n' \
	   'Port 22' \
	   'Protocol 2' \
	   'PermitRootLogin no' \
	   'PasswordAuthentication no' \
	   'KbdInteractiveAuthentication no' \
	   'ChallengeResponseAuthentication no' \
	   'PubkeyAuthentication yes' \
	   'AuthenticationMethods publickey' \
	   'PermitEmptyPasswords no' \
	   'UsePAM no' \
	   'X11Forwarding no' \
	   'AllowTcpForwarding no' \
	   'AllowAgentForwarding no' \
	   'AllowStreamLocalForwarding no' \
	   'PermitTunnel no' \
	   'LoginGraceTime 20' \
	   'MaxAuthTries 3' \
	   'MaxSessions 2' \
	   'ClientAliveInterval 300' \
	   'ClientAliveCountMax 2' \
	   'AllowUsers git' \
	   'AuthorizedKeysFile .ssh/authorized_keys' \
	   'Subsystem sftp internal-sftp' \
	   'Match User git' \
	   '    PermitTTY no' \
	> /etc/ssh/sshd_config

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

VOLUME ["/git-server/keys", "/git-server/repos", "/git-server/http"]

EXPOSE 22
EXPOSE 80

CMD ["/usr/local/bin/start.sh"]
