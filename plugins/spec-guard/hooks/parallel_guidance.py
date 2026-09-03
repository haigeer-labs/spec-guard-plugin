"""将安全门结果转换为人工并行开发指引，不执行任何生命周期操作。"""
from __future__ import print_function


def guidance(report):
    groups = []
    for group in report.get("groups", []):
        eligible = group.get("classification") == "manual-parallel-eligible"
        workers = []
        if eligible:
            for module_id in group.get("modules", []):
                workers.append({
                    "module": module_id,
                    "branch": "codex/parallel/%s" % module_id,
                    "title": "[SG 手动并行｜待汇合] %s" % module_id,
                    "responsibility": "用户自行创建、管理与回收此隔离 worker。",
                })
        groups.append({"layer": group.get("layer"), "classification": group.get("classification"),
                       "workers": workers, "evidence": group.get("evidence", [])})
    return {"base": report.get("base"), "warnings": report.get("warnings", []), "groups": groups,
            "mergeChecklist": [
                "各 worker 工作树干净且变更仍符合声明边界。",
                "各 worker 的针对性测试通过。",
                "按能力图依赖拓扑依次合并。",
                "整合后运行完整仓库校验。",
            ]}
