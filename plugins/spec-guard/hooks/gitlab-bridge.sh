#!/usr/bin/env bash
# GitLab bridge 的最小执行入口：只在已认证的 GitLab 仓库中调用 glab。
set -euo pipefail

ACTION=${1:-}; shift || true
case "$ACTION" in issue|relate|mr) ;; *) echo 'usage: gitlab-bridge.sh <issue|relate|mr> ...' >&2; exit 2;; esac
command -v glab >/dev/null || { echo 'glab 未安装' >&2; exit 1; }
glab repo view >/dev/null
case "$ACTION" in
  issue)  [ "$#" -gt 0 ] && glab issue create "$@" || { echo 'issue 需要显式参数' >&2; exit 2; } ;;
  relate) [ "$#" -gt 0 ] && glab api -X POST "$@" || { echo 'relate 需要 API 参数' >&2; exit 2; } ;;
  mr)     [ "$#" -gt 0 ] && glab mr create "$@" || { echo 'mr 需要显式参数' >&2; exit 2; } ;;
esac
