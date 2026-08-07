# SOURCE COVERAGE MATRIX

本表用于证明 `AI-Gateway.md` 中最终方案的主要能力均已映射到正式指南章节。

| 源需求 | 章节 |
| --- | --- |
| LiteLLM 只承担 Provider 调度，不直接暴露给用户 | Ch1, Ch17, Ch26 |
| Enterprise Gateway 前置 AuthN/AuthZ、Policy、Routing、Billing | Ch4, Ch17-Ch20, Ch24 |
| 多租户 Tenant/User/API Key | Ch8-Ch10, Ch63 |
| Provider / Model Mapping / Capability Registry | Ch11-Ch12, Ch20, Ch63 |
| Router Pipeline：Capability/Tenant/Budget/Geo/Health/Latency/Cost/Weight | Ch14, Ch20 |
| Latency/Cost/Region/Sticky/Weighted/Health/Capability 路由 | Ch14, Ch20 |
| Budget：Daily/Weekly/Monthly/Lifetime | Ch13, Ch15 |
| 灰度发布、UserID Hash、A/B Test | Ch14, Ch20, Ch71 |
| Provider Health：P95/P99/Availability/ErrorRate，后台探测 | Ch11, Ch20, Ch53-Ch56 |
| 三级缓存：Memory/Redis/Vector(Semantic) | Ch22, Ch38 |
| Data Plane 无状态，配置来自 Redis/Memory，不直接查询数据库 | Ch2, Ch17, Ch25 |
| Control Plane：IAM/Provider/Model/Policy/Routing/Billing/Audit | Ch8-Ch16 |
| Kafka 异步日志、计费、审计 | Ch15-Ch16, Ch24, Ch40 |
| Kubernetes + Helm + HPA；Redis Cluster；Postgres Patroni | Ch35-Ch39, Ch66 |
| CI/CD：GitHub Actions + Harbor + ArgoCD | Ch68 |
| Observability：Prometheus/Grafana/OTEL/Tempo/Langfuse | Ch52-Ch56 |
| AI Runtime：LiteLLM/vLLM/SGLang/Ollama | Ch26-Ch29 |
| Embedding/Reranker/Vision/Audio/Image | Ch30-Ch32 |
| Prompt Registry/Version/Template | Ch33 |
| MCP/Agent/RAG/Workflow/Evaluation/Safety/Marketplace | Ch34, Ch49, Ch70 |
| Security：OIDC/OAuth2/JWT、RBAC/ABAC、Vault/KMS、TLS/mTLS、GDPR/SOC2/ISO27001 | Ch44-Ch51 |
| Operations：Alert/Runbook/Chaos/Capacity Planning | Ch55-Ch60 |
| Implementation：Repository/DDL/OpenAPI/Helm/Terraform/Dockerfile/GitOps/Code Convention | Ch61-Ch72 |

## 章节统计

- 主体：8 卷，72 章。
- 附录：3 个。
- Sequence Diagram 模板：20 个。

