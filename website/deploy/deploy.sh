#!/usr/bin/env bash
# Zap 官网部署脚本(在服务器上执行)
#
# 由 GitHub Actions 上传到 $DEPLOY_PATH/deploy/deploy.sh 后,经 chmod +x 远程执行。
# 职责:把上传好的静态产物(dist/)切换为对外服务目录,做原子发布 + 保留回滚。
#
# 约定的目录布局($DEPLOY_PATH 下):
#   incoming/   ← Actions 用 rsync 推上来的最新 dist 内容
#   releases/<ts>/ ← 每次发布的快照
#   current     ← symlink,指向当前生效的 releases/<ts>(nginx root 指这里)
#
# nginx 的 root 应配置为 $DEPLOY_PATH/current
set -euo pipefail

# 部署根目录:脚本位于 <root>/deploy/deploy.sh,故根目录是脚本上两级
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INCOMING="$ROOT/incoming"
RELEASES="$ROOT/releases"
CURRENT="$ROOT/current"
KEEP=5  # 保留最近多少份 release 用于回滚

log() { printf '[deploy] %s\n' "$*"; }

if [ ! -d "$INCOMING" ] || [ -z "$(ls -A "$INCOMING" 2>/dev/null)" ]; then
  log "错误:$INCOMING 不存在或为空,没有可发布的产物。先由 CI rsync 产物到 incoming/。"
  exit 1
fi

TS="$(date +%Y%m%d%H%M%S)"
TARGET="$RELEASES/$TS"

mkdir -p "$RELEASES"
log "创建发布快照:$TARGET"
# 用 cp -a 从 incoming 物化一份不可变快照,保证 current 切换是原子的
cp -a "$INCOMING" "$TARGET"

# 原子切换 current symlink:先建临时 link 再 rename,避免出现短暂无 current 的窗口
log "切换 current -> releases/$TS"
ln -sfn "$TARGET" "$CURRENT.tmp"
mv -Tf "$CURRENT.tmp" "$CURRENT"

# 清理旧 release,保留最近 $KEEP 份
log "清理旧 release,保留最近 $KEEP 份"
cd "$RELEASES"
ls -1dt */ 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  log "  删除 $old"
  rm -rf "${RELEASES:?}/${old%/}"
done

log "完成。current 现指向:$(readlink -f "$CURRENT")"
