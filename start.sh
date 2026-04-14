#!/usr/bin/env bash
set -euo pipefail

GIT_HOME="/home/git"
SSH_DIR="${GIT_HOME}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
KEYS_DIR="${KEYS_DIR:-/git-server/keys}"
REPOS_DIR="${REPOS_DIR:-/git-server/repos}"
HTTP_DATA_DIR="${HTTP_DATA_DIR:-/git-server/http}"
HTTP_HTPASSWD_FILE="${HTTP_HTPASSWD_FILE:-/git-server/http/.htpasswd}"
HTTP_AUTH_REQUIRED="${HTTP_AUTH_REQUIRED:-false}"
HTTP_PUSH_AUTH_REQUIRED="${HTTP_PUSH_AUTH_REQUIRED:-false}"
HTTP_USER="${HTTP_USER:-gitadmin}"
HTTP_PASSWORD="${HTTP_PASSWORD:-}"
AUTO_CREATE_BARE_REPO="${AUTO_CREATE_BARE_REPO:-true}"
DEFAULT_BARE_REPO="${DEFAULT_BARE_REPO:-proyecto.git}"
GIT_SSH_PUBLIC_KEY="${GIT_SSH_PUBLIC_KEY:-}"

mkdir -p "${SSH_DIR}" "${KEYS_DIR}" "${REPOS_DIR}" "${HTTP_DATA_DIR}" /var/run/sshd /var/run/apache2 /var/lock/apache2 /var/log/apache2

# If authorized_keys is mounted as a file from host, this touch is harmless.
if [[ ! -f "${AUTHORIZED_KEYS}" ]]; then
  touch "${AUTHORIZED_KEYS}"
fi

# Rebuild authorized_keys from existing file + all files in keys dir + env key.
tmp_keys="$(mktemp)"
if [[ -f "${AUTHORIZED_KEYS}" ]]; then
  cat "${AUTHORIZED_KEYS}" >> "${tmp_keys}"
fi

for key_file in "${KEYS_DIR}"/*; do
  if [[ -f "${key_file}" ]]; then
    cat "${key_file}" >> "${tmp_keys}"
  fi
done

if [[ -n "${GIT_SSH_PUBLIC_KEY}" ]]; then
  echo "${GIT_SSH_PUBLIC_KEY}" >> "${tmp_keys}"
fi

# Keep only non-empty unique lines.
awk 'NF && !seen[$0]++' "${tmp_keys}" > "${AUTHORIZED_KEYS}"
rm -f "${tmp_keys}"

chown -R git:git "${GIT_HOME}" "${KEYS_DIR}" "${REPOS_DIR}" "${HTTP_DATA_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${AUTHORIZED_KEYS}"
chmod 2775 "${REPOS_DIR}"

# Build Apache Git Smart HTTP config from env flags.
auth_block=""
if [[ "${HTTP_AUTH_REQUIRED}" == "true" ]]; then
  if [[ -n "${HTTP_PASSWORD}" ]]; then
    htpasswd -bc "${HTTP_HTPASSWD_FILE}" "${HTTP_USER}" "${HTTP_PASSWORD}" >/dev/null
  fi
  if [[ ! -f "${HTTP_HTPASSWD_FILE}" ]]; then
    echo "HTTP auth enabled but no htpasswd found. Set HTTP_PASSWORD or mount ${HTTP_HTPASSWD_FILE}." >&2
    exit 1
  fi
  chgrp www-data "${HTTP_HTPASSWD_FILE}"
  chmod 640 "${HTTP_HTPASSWD_FILE}"
  auth_block=$(cat <<EOF
<LocationMatch "^/git/.*/(git-upload-pack|git-receive-pack)$">
    AuthType Basic
    AuthName "Git HTTP"
    AuthUserFile ${HTTP_HTPASSWD_FILE}
    Require valid-user
</LocationMatch>
EOF
)
elif [[ "${HTTP_PUSH_AUTH_REQUIRED}" == "true" ]]; then
  if [[ -n "${HTTP_PASSWORD}" ]]; then
    htpasswd -bc "${HTTP_HTPASSWD_FILE}" "${HTTP_USER}" "${HTTP_PASSWORD}" >/dev/null
  fi
  if [[ ! -f "${HTTP_HTPASSWD_FILE}" ]]; then
    echo "HTTP push auth enabled but no htpasswd found. Set HTTP_PASSWORD or mount ${HTTP_HTPASSWD_FILE}." >&2
    exit 1
  fi
  chgrp www-data "${HTTP_HTPASSWD_FILE}"
  chmod 640 "${HTTP_HTPASSWD_FILE}"
  auth_block=$(cat <<EOF
<LocationMatch "^/git/.*/git-receive-pack$">
    AuthType Basic
    AuthName "Git HTTP Push"
    AuthUserFile ${HTTP_HTPASSWD_FILE}
    Require valid-user
</LocationMatch>
EOF
)
fi

cat > /etc/apache2/sites-available/git-http.conf <<EOF
ServerName localhost

SetEnv GIT_PROJECT_ROOT ${REPOS_DIR}
SetEnv GIT_HTTP_EXPORT_ALL

ScriptAlias /git/ /usr/lib/git-core/git-http-backend/

<Directory "/usr/lib/git-core">
    Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
    Require all granted
</Directory>

${auth_block}
EOF

a2ensite git-http.conf >/dev/null

# Auto-create a default bare repository so the server is usable immediately.
if [[ "${AUTO_CREATE_BARE_REPO}" == "true" ]]; then
  if [[ "${DEFAULT_BARE_REPO}" != *.git ]]; then
    DEFAULT_BARE_REPO="${DEFAULT_BARE_REPO}.git"
  fi

  TARGET_REPO="${REPOS_DIR}/${DEFAULT_BARE_REPO}"
  if [[ ! -d "${TARGET_REPO}" ]]; then
    if ! su -s /bin/bash git -c "git init --bare --shared=group --initial-branch=main \"${TARGET_REPO}\""; then
      su -s /bin/bash git -c "git init --bare --shared=group \"${TARGET_REPO}\""
      su -s /bin/bash git -c "git --git-dir=\"${TARGET_REPO}\" symbolic-ref HEAD refs/heads/main"
    fi
  fi
fi

# Ensure host keys exist for the SSH daemon.
ssh-keygen -A

/usr/sbin/sshd -D -e &
exec /usr/sbin/apache2ctl -D FOREGROUND
