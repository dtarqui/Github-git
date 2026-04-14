FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
	KEYS_DIR=/git-server/keys \
	REPOS_DIR=/git-server/repos \
	AUTO_CREATE_BARE_REPO=true \
	DEFAULT_BARE_REPO=proyecto.git

LABEL org.opencontainers.image.title="git-ssh-server" \
	org.opencontainers.image.description="Pure Git + OpenSSH server without external managers" \
	org.opencontainers.image.vendor="local-repo" \
	org.opencontainers.image.source="local-workspace"

# Install Git + OpenSSH server and clean apt cache to keep image small.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		git \
		openssh-server \
		ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

# Create git user with git-shell to prevent interactive shell access.
RUN useradd -m -d /home/git -s /usr/bin/git-shell git \
	&& passwd -d git \
	&& mkdir -p /home/git/.ssh /git-server/keys /git-server/repos /var/run/sshd \
	&& rm -rf /home/git/repos \
	&& ln -s /git-server/repos /home/git/repos \
	&& chown -R git:git /home/git /git-server \
	&& chmod 700 /home/git/.ssh \
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

VOLUME ["/git-server/keys", "/git-server/repos"]

EXPOSE 22

CMD ["/usr/local/bin/start.sh"]
