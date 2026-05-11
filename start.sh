#!/usr/bin/env bash
set -euo pipefail

GIT_HOME="/home/git"
SSH_DIR="${GIT_HOME}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
KEYS_DIR="${KEYS_DIR:-/git-server/keys}"
SSH_KEYS_DIR="${SSH_KEYS_DIR:-/git-server/ssh-host-keys}"
REPOS_DIR="${REPOS_DIR:-/git-server/repos}"
GIT_HTTP_RECEIVEPACK_DEFAULT="${GIT_HTTP_RECEIVEPACK_DEFAULT:-true}"
AUTO_CREATE_BARE_REPO="${AUTO_CREATE_BARE_REPO:-false}"
DEFAULT_BARE_REPO="${DEFAULT_BARE_REPO:-}"
MICROSERVICE_URL="${MICROSERVICE_URL:-}"
MICROSERVICE_AUTH_TOKEN="${MICROSERVICE_AUTH_TOKEN:-}"

mkdir -p \
  "${SSH_DIR}" \
  "${KEYS_DIR}" \
  "${REPOS_DIR}" \
  "${SSH_KEYS_DIR}" \
  /var/run/sshd \
  /var/run/apache2 \
  /var/lock/apache2 \
  /var/log/apache2

# ── authorized_keys ─────────────────────────────────────────────────────────
# Concatenates all files in KEYS_DIR into authorized_keys.
# In microservice mode the microservice writes files with command= prefixes:
#   command="/usr/local/bin/git-auth alice",no-pty,no-port-forwarding ssh-ed25519 AAAA...
# Called once at startup and by the key watcher on every change.
[[ -f "${AUTHORIZED_KEYS}" ]] || touch "${AUTHORIZED_KEYS}"

_rebuild_authorized_keys() {
  local tmp
  tmp="$(mktemp)"
  for f in "${KEYS_DIR}"/*; do
    [[ -f "${f}" ]] && cat "${f}" >> "${tmp}"
  done
  awk 'NF && !seen[$0]++' "${tmp}" > "${AUTHORIZED_KEYS}"
  rm -f "${tmp}"
  chmod 600 "${AUTHORIZED_KEYS}"
  chown git:git "${AUTHORIZED_KEYS}"
}

_rebuild_authorized_keys

# ── SSH host key persistence ─────────────────────────────────────────────────
for key_type in rsa ecdsa ed25519; do
  stored="${SSH_KEYS_DIR}/ssh_host_${key_type}_key"
  live="/etc/ssh/ssh_host_${key_type}_key"
  if [[ -f "${stored}" ]]; then
    cp "${stored}" "${live}"
    cp "${stored}.pub" "${live}.pub"
    chmod 600 "${live}"
    chmod 644 "${live}.pub"
  fi
done

ssh-keygen -A

for key_type in rsa ecdsa ed25519; do
  stored="${SSH_KEYS_DIR}/ssh_host_${key_type}_key"
  live="/etc/ssh/ssh_host_${key_type}_key"
  if [[ ! -f "${stored}" && -f "${live}" ]]; then
    cp "${live}" "${stored}"
    cp "${live}.pub" "${stored}.pub"
    chmod 600 "${stored}"
    chmod 644 "${stored}.pub"
  fi
done

# ── Permissions ──────────────────────────────────────────────────────────────
chown -R git:git "${GIT_HOME}" "${KEYS_DIR}" "${REPOS_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${AUTHORIZED_KEYS}"
chmod 2775 "${REPOS_DIR}"

# ── Apache — no auth, internal use only ──────────────────────────────────────
cat > /etc/apache2/sites-available/git-http.conf <<EOF
<VirtualHost *:80>
  ServerName _

  SetEnv GIT_PROJECT_ROOT ${REPOS_DIR}
  SetEnv GIT_HTTP_EXPORT_ALL

  SetEnv REPOS_DIR ${REPOS_DIR}
  SetEnv KEYS_DIR ${KEYS_DIR}
  SetEnv MICROSERVICE_AUTH_TOKEN ${MICROSERVICE_AUTH_TOKEN}

  ScriptAlias /git/ /usr/lib/git-core/git-http-backend/

  <Directory "/usr/lib/git-core">
    Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
    AllowOverride None
    Require all granted
  </Directory>

  ScriptAlias /admin /usr/local/bin/git-admin.cgi

  <Directory "/usr/local/bin">
    Options +ExecCGI
    AllowOverride None
    Require all granted
  </Directory>

  ErrorLog  /var/log/apache2/git-error.log
  CustomLog /var/log/apache2/git-access.log combined
</VirtualHost>
EOF

a2ensite git-http.conf >/dev/null

# ── Default bare repo ────────────────────────────────────────────────────────
if [[ "${AUTO_CREATE_BARE_REPO}" == "true" && -n "${DEFAULT_BARE_REPO}" ]]; then
  repo="${DEFAULT_BARE_REPO}"
  [[ "${repo}" != *.git ]] && repo="${repo}.git"
  target="${REPOS_DIR}/${repo}"
  if [[ ! -d "${target}" ]]; then
    parent="$(dirname "${target}")"
    mkdir -p "${parent}"
    chown git:git "${parent}"
    su -s /bin/bash git -c \
      "git init --bare --shared=group --initial-branch=main \"${target}\" 2>/dev/null || \
       { git init --bare --shared=group \"${target}\"; \
         git --git-dir=\"${target}\" symbolic-ref HEAD refs/heads/main; }"
    echo "Created default repo: ${repo}"
  fi
fi

# ── HTTP push default policy ────────────────────────────────────────────────
if [[ "${GIT_HTTP_RECEIVEPACK_DEFAULT}" == "true" ]]; then
  while IFS= read -r -d '' repo; do
    git -C "${repo}" config http.receivepack true || true
  done < <(find "${REPOS_DIR}" -type d -name "*.git" -print0)
fi

# ── Startup info ─────────────────────────────────────────────────────────────
echo "---"
if [[ -n "${MICROSERVICE_URL}" ]]; then
  echo "SSH access checks → ${MICROSERVICE_URL}/internal/ssh-access"
else
  echo "WARNING: MICROSERVICE_URL is not set — SSH access control is disabled."
  echo "         All SSH key holders can access all repos."
fi
echo "HTTP git (internal): http://localhost:80/git/<owner>/<repo>.git"
echo "HTTP push default:   ${GIT_HTTP_RECEIVEPACK_DEFAULT}"
echo "SSH git:             ssh://git@<host>:22${REPOS_DIR}/<owner>/<repo>.git"
echo "---"

# ── Process management ───────────────────────────────────────────────────────
_cleanup() {
  echo "Shutting down..."
  [[ -n "${SSHD_PID:-}" ]]    && kill "${SSHD_PID}"    2>/dev/null || true
  [[ -n "${WATCHER_PID:-}" ]] && kill "${WATCHER_PID}" 2>/dev/null || true
  apache2ctl stop 2>/dev/null || true
  exit 0
}
trap _cleanup SIGTERM SIGINT

/usr/sbin/sshd -D -e &
SSHD_PID=$!

apache2ctl -D FOREGROUND &
APACHE_PID=$!

_watch_keys() {
  local last=""
  while true; do
    local cur
    cur="$(find "${KEYS_DIR}" -maxdepth 1 -type f | sort | xargs md5sum 2>/dev/null | md5sum)"
    if [[ "${cur}" != "${last}" ]]; then
      last="${cur}"
      _rebuild_authorized_keys
      echo "[keys] authorized_keys rebuilt"
    fi
    sleep 5
  done
}
_watch_keys &
WATCHER_PID=$!

wait -n "${SSHD_PID}" "${APACHE_PID}"
EXIT_CODE=$?
echo "A service exited (${EXIT_CODE}). Stopping."
kill "${SSHD_PID}" "${APACHE_PID}" "${WATCHER_PID}" 2>/dev/null || true
exit "${EXIT_CODE}"
