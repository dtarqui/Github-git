#!/usr/bin/env bash
# Admin utility — run from outside the container:
#   docker exec git-server manage-repo <command> [args]
#
# In normal operation repos are created by the microservice via JGit
# on the shared volume. Use this script for debugging or manual recovery.
set -euo pipefail

REPOS_DIR="${REPOS_DIR:-/git-server/repos}"
GIT_HTTP_RECEIVEPACK_DEFAULT="${GIT_HTTP_RECEIVEPACK_DEFAULT:-true}"
cmd="${1:-}"

_sanitize() {
  local name="$1"
  [[ "${name}" != *.git ]] && name="${name}.git"
  if [[ ! "${name}" =~ ^[a-zA-Z0-9_/-][a-zA-Z0-9_./-]*\.git$ ]] || [[ "${name}" == *..* ]]; then
    echo "Invalid repo name." >&2; exit 1
  fi
  echo "${name}"
}

case "${cmd}" in
  create)
    name="$(_sanitize "${2:-}")"
    target="${REPOS_DIR}/${name}"
    [[ -d "${target}" ]] && { echo "Already exists: ${name}" >&2; exit 1; }
    parent="$(dirname "${target}")"
    mkdir -p "${parent}"
    chown git:git "${parent}"
    su -s /bin/bash git -c \
      "git init --bare --shared=group --initial-branch=main \"${target}\" 2>/dev/null || \
       { git init --bare --shared=group \"${target}\"; \
         git --git-dir=\"${target}\" symbolic-ref HEAD refs/heads/main; }"
    if [[ "${GIT_HTTP_RECEIVEPACK_DEFAULT}" == "true" ]]; then
      git -C "${target}" config http.receivepack true
    fi
    echo "Created: ${name}"
    ;;

  list)
    find "${REPOS_DIR}" -name "*.git" -type d \
      | sed "s|${REPOS_DIR}/||" \
      | sort
    ;;

  delete)
    name="$(_sanitize "${2:-}")"
    target="${REPOS_DIR}/${name}"
    [[ ! -d "${target}" ]] && { echo "Not found: ${name}" >&2; exit 1; }
    rm -rf "${target}"
    echo "Deleted: ${name}"
    ;;

  *)
    echo "Usage: manage-repo <create|list|delete> <name>" >&2
    exit 1
    ;;
esac
