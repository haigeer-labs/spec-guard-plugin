## 变更

<!-- 一句话 -->

## 关联

Closes #

## 自检

- [ ] `bash scripts/validate.sh` 通过
- [ ] `bash plugins/spec-guard/hooks/test-phase-guard.sh` 通过
- [ ] 改了状态机逻辑的话，已补测试用例
- [ ] 改了命令的话，README 命令表已更新
- [ ] 如果是发版，plugin.json 的 version 和 CHANGELOG 已更新

## 三条硬约束是否仍成立

- [ ] 未声明约定的仓库仍然静默退出
- [ ] 探测失败时降级而不是误报
- [ ] hook 仍然只读，不做写操作
