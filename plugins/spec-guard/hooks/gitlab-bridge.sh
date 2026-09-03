#!/usr/bin/env bash
# GitLab bridge 的最小执行入口：只在已认证的 GitLab 仓库中调用 glab。
set -euo pipefail

ACTION=${1:-}; shift || true
case "$ACTION" in issue|relate|mr) ;; *) echo 'usage: gitlab-bridge.sh <issue|relate|mr> ...' >&2; exit 2;; esac
command -v glab >/dev/null || { echo 'glab 未安装' >&2; exit 1; }
if [ "${1:-}" = --help ]; then
  case "$ACTION" in
    issue) glab issue create --help ;;
    relate) echo 'relate: <project-id> <source-iid> <target-iid>' ;;
    mr) glab mr create --help ;;
  esac
  exit 0
fi
case "$ACTION" in
  issue)
    [ "$#" -eq 6 ] && [ "$1" = --repo ] && [ "$3" = --title ] && [ "$5" = --description-file ] \
      || { echo 'issue 仅接受 --repo --title --description-file' >&2; exit 2; }
    glab repo view >/dev/null; glab issue create "$@"
    ;;
  relate)
    [ "$#" -eq 3 ] || { echo 'relate 需要 project-id source-iid target-iid' >&2; exit 2; }
    case "$1:$2:$3" in *[!0-9:]*|*::*|:*) echo 'relate 参数必须是数字' >&2; exit 2;; esac
    glab repo view >/dev/null; glab api -X POST "projects/$1/issues/$2/links" -f "target_project_id=$1" -f "target_issue_iid=$3"
    ;;
  mr)
    [ "$#" -eq 8 ] && [ "$1" = --repo ] && [ "$3" = --source-branch ] \
      && [ "$5" = --target-branch ] && [ "$7" = --title ] \
      || { echo 'mr 仅接受 --repo --source-branch --target-branch --title' >&2; exit 2; }
    glab repo view >/dev/null; glab mr create "$@"
    ;;
esac
