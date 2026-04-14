#!/usr/bin/env bash
set -euo pipefail

GIT_HOME="/home/git"
SSH_DIR="${GIT_HOME}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
KEYS_DIR="${KEYS_DIR:-/git-server/keys}"
REPOS_DIR="${REPOS_DIR:-/git-server/repos}"
AUTO_CREATE_BARE_REPO="${AUTO_CREATE_BARE_REPO:-true}"
DEFAULT_BARE_REPO="${DEFAULT_BARE_REPO:-proyecto.git}"
GIT_SSH_PUBLIC_KEY="${GIT_SSH_PUBLIC_KEY:-}"

mkdir -p "${SSH_DIR}" "${KEYS_DIR}" "${REPOS_DIR}" /var/run/sshd

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

chown -R git:git "${GIT_HOME}" "${KEYS_DIR}" "${REPOS_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${AUTHORIZED_KEYS}"
chmod 755 "${REPOS_DIR}"

# Auto-create a default bare repository so the server is usable immediately.
if [[ "${AUTO_CREATE_BARE_REPO}" == "true" ]]; then
  if [[ "${DEFAULT_BARE_REPO}" != *.git ]]; then
    DEFAULT_BARE_REPO="${DEFAULT_BARE_REPO}.git"
  fi

  TARGET_REPO="${REPOS_DIR}/${DEFAULT_BARE_REPO}"
  if [[ ! -d "${TARGET_REPO}" ]]; then
    if ! su -s /bin/bash git -c "git init --bare --initial-branch=main \"${TARGET_REPO}\""; then
      su -s /bin/bash git -c "git init --bare \"${TARGET_REPO}\""
      su -s /bin/bash git -c "git --git-dir=\"${TARGET_REPO}\" symbolic-ref HEAD refs/heads/main"
    fi
  fi
fi

# Ensure host keys exist for the SSH daemon.
ssh-keygen -A

exec /usr/sbin/sshd -D -e
