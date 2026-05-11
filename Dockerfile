FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
	KEYS_DIR=/git-server/keys \
	SSH_KEYS_DIR=/git-server/ssh-host-keys \
	REPOS_DIR=/git-server/repos \
	GIT_HTTP_RECEIVEPACK_DEFAULT=true \
	AUTO_CREATE_BARE_REPO=false \
	DEFAULT_BARE_REPO= \
	MICROSERVICE_URL= \
	MICROSERVICE_AUTH_TOKEN=

LABEL org.opencontainers.image.title="git-server" \
	org.opencontainers.image.description="Git storage backend (SSH + HTTP) for a microservice layer" \
	org.opencontainers.image.vendor="local-repo" \
	org.opencontainers.image.source="local-workspace"

RUN apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout="30" update \
	&& apt-get install -y --no-install-recommends --fix-missing \
		git \
		openssh-server \
		apache2 \
		curl \
		iproute2 \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /home/git -s /usr/bin/git-shell git \
	&& passwd -d git \
	&& mkdir -p \
		/home/git/.ssh \
		/git-server/keys \
		/git-server/repos \
		/git-server/ssh-host-keys \
		/var/run/sshd \
	&& rm -rf /home/git/repos \
	&& ln -s /git-server/repos /home/git/repos \
	&& usermod -a -G git www-data \
	&& git config --system --add safe.directory '*' \
	&& chown -R git:git /home/git /git-server \
	&& chmod 700 /home/git/.ssh \
	&& a2dissite 000-default.conf \
	&& a2enmod cgi alias env \
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
	   'MaxSessions 10' \
	   'ClientAliveInterval 300' \
	   'ClientAliveCountMax 2' \
	   'AllowUsers git' \
	   'AuthorizedKeysFile .ssh/authorized_keys' \
	   'Match User git' \
	   '    PermitTTY no' \
	> /etc/ssh/sshd_config

# git-auth is called by sshd via command= in each authorized_keys entry.
# The microservice writes those entries when a user registers an SSH key.
COPY git-auth /usr/local/bin/git-auth
COPY start.sh /usr/local/bin/start.sh
COPY manage-repo.sh /usr/local/bin/manage-repo
COPY git-admin.cgi /usr/local/bin/git-admin.cgi
RUN chmod +x /usr/local/bin/git-auth /usr/local/bin/start.sh /usr/local/bin/manage-repo /usr/local/bin/git-admin.cgi

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
	CMD ss -tlnH | grep -q ':80' && ss -tlnH | grep -q ':22'

VOLUME ["/git-server/keys", "/git-server/repos", "/git-server/ssh-host-keys"]

EXPOSE 22 80

CMD ["/usr/local/bin/start.sh"]
