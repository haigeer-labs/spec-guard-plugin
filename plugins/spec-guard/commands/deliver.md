---
description: 当前模块开 PR 并关联 issue
---
交付粒度是**模块**，不是单个 task。开 PR 前先确认模块真的做完了：

1. `gh api "repos/{owner}/{repo}/issues/<module-issue>/sub_issues"` 取未关闭的 task
2. `git log <默认分支>..HEAD --format=%B` 里的 `Closes #<n>` 是否覆盖了它们

有未覆盖的 task 就**不要开 PR**，报告还差哪几个，回 `/next` 继续。
用户明确要求提前交付（例如 task 被取消、要拆成两批）时照办，但要说明少了哪些。

覆盖齐了再 invoke code-review-and-quality 做五轴自查。
有 Critical 级别发现时不要开 PR，先修。

通过后 invoke spec-github-bridge 执行「操作四：交付」。
