#!/usr/bin/env bash
# GitLab bridge 的最小执行入口：只在已认证的 GitLab 仓库中调用 glab。
set -euo pipefail

ACTION=${1:-}; shift || true
case "$ACTION" in issue|relate|mr) ;; *) echo 'usage: gitlab-bridge.sh <issue|relate|mr> ...' >&2; exit 2;; esac
command -v glab >/dev/null || { echo 'glab 未安装' >&2; exit 1; }
glab repo view >/dev/null
case "$ACTION" in
  issue)  glab issue create "$@" ;;
  relate) glab api -X POST "$@" ;;
  mr)     glab mr create "$@" ;;
esac
