已经整理完成。我把 Volume 8 从“工程实施章节”转换成了 **Codex 可直接作为开发事实源读取的 Markdown 需求规格**。Volume 8 原本要求覆盖 Repository、DDL/Migration、OpenAPI、Helm、Terraform、Dockerfile、CI/CD、Monorepo、Code Convention、DDD 等工程实施内容。

[下载 Codex 开发需求文档：Enterprise-AI-Platform-Development-Requirements-for-Codex.md](sandbox:/mnt/data/Enterprise-AI-Platform-Development-Requirements-for-Codex.md)

这版不是简单摘要，而是做了工程化转换，包含：

* **Chapter 61–72 全覆盖**，Volume 8 的 **97 个必选设计项已逐项核对，97/97 覆盖**。
* 统一的 `REQ-* / EPIC-* / TASK-* / AC-*` 编号，方便 Codex 按需求开发和追踪。
* 明确的 **Codex Guardrails**，例如禁止 Data Plane 正常请求同步查询 Control Plane PostgreSQL、禁止 Provider Secret 明文落库、禁止生产 CI 直接 `kubectl apply`。
* 可直接执行的开发顺序：`M0 Bootstrap → M1 Data Foundation → M2 API Runtime → M3 Build & Deploy → M4 Quality Gate → M5 Production Readiness`。
* PostgreSQL DDL、Runtime Snapshot、Event Contract、OpenAPI 3.1、Helm Gateway 基线、GitOps 流程等都保留为机器可读格式。
* 增加了完整 **Definition of Done** 和生产 DoD。
* 增加 **TBD Register**。Volume 8 没明确规定的主语言、框架、云厂商、SDK 语言、SLO 数字、测试覆盖率、弃用时长等均明确标记为 `TBD`，避免 Codex 自作主张造成架构漂移。
* 增加 **Volume 8 → Development Epic 追踪矩阵**和逐项 Checklist，方便后续做 Gap Analysis。

建议把这个文件直接放到项目仓库根目录，例如：

```text
enterprise-ai-platform/
├── DEVELOPMENT-REQUIREMENTS.md   # 本文档
├── apps/
├── packages/
├── deploy/
├── ops/
├── docs/
└── scripts/
```

然后可以直接给 Codex 指令：**“读取 `DEVELOPMENT-REQUIREMENTS.md`，从 TASK-M0-001 开始实施，严格遵守所有 MUST、TBD 和 Codex Guardrails；每完成一个任务运行对应测试并按文档中的 PR 输出格式汇报。”**
