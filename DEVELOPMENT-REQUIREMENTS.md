# Enterprise AI Platform Development Requirements

> 面向 Codex / 工程开发的单一需求规格（Source of Truth）  
> 来源：`Volume-08-Implementation.md`（Chapter 61–72）  
> 文档版本：1.0  
> 状态：Development Baseline  
> 适用对象：Codex、后端工程师、平台工程师、SRE、DevSecOps、QA、架构评审人员

---

## 0. 如何让 Codex 使用本文档

### 0.1 执行指令

Codex 在本仓库中开发时，必须把本文档视为 **工程实施的最高优先级需求基线**。除非用户或后续 ADR 明确覆盖，否则不得自行改变本文档中的架构边界、数据流、部署流和安全约束。

每次实现任务时必须遵循：

1. 先定位对应 `REQ-*`、`EPIC-*`、`TASK-*` 和 `AC-*`。
2. 只实现当前任务所需的最小范围，不顺手改变其他领域边界。
3. 对本文档标记为 `TBD` 的内容，不得自行“合理猜测”为生产决策；需要保留配置入口、接口或 TODO，并在 PR 中列出待决策项。
4. 不得把控制平面的治理逻辑下沉到 LiteLLM、Provider SDK 或具体模型供应商。
5. 不得让 Data Plane 为正常请求同步查询控制平面数据库。
6. 不得在代码、镜像、Helm values、Terraform state 输出、日志或错误响应中泄漏 Provider 明文密钥。
7. 每个实现必须同时考虑：正常路径、租户隔离、故障路径、回滚、可观测性和测试。
8. 对所有影响请求行为的配置，必须携带可追踪版本，并保证旧版本可回滚。
9. 非阻塞副作用（Usage、Billing、Audit、Analytics）默认走异步事件链路，不得阻塞模型调用主路径。
10. PR 合并前必须满足本任务的 Acceptance Criteria 和全局 Definition of Done。

### 0.2 需求状态约定

- `MUST`：必须实现；未实现不能视为完成。
- `SHOULD`：Volume 8 明确推荐，除非 ADR 说明理由，否则应实现。
- `TBD`：Volume 8 未给出足够细节，Codex 不得自行确定最终生产值。
- `OUT-OF-SCOPE`：不属于本卷工程实施范围，不能在本需求中凭空扩展。

### 0.3 需求 ID 规则

| 前缀 | 含义 |
|---|---|
| `REQ-GEN-*` | 全局工程约束 |
| `REQ-REP-*` | Monorepo / Repository |
| `REQ-CODE-*` | DDD / 插件 / 代码结构 |
| `REQ-DB-*` | PostgreSQL / DDL / Migration |
| `REQ-API-*` | OpenAPI / 错误码 / SDK |
| `REQ-BLD-*` | Docker / 构建 |
| `REQ-HELM-*` | Helm / Kubernetes |
| `REQ-IAC-*` | Terraform / 环境拓扑 |
| `REQ-CICD-*` | GitHub Actions / Harbor / ArgoCD |
| `REQ-TST-*` | 测试 / 安全验证 |
| `REQ-RM-*` | Roadmap / 阶段退出标准 |
| `REQ-REL-*` | 发布 / 兼容 / 弃用 |
| `REQ-OPS-*` | 上线 / SLO / Runbook / Day-2 |

---

# Part I. 工程总约束

## 1. 系统边界与核心原则

### REQ-GEN-001 Control Plane 与 Data Plane 分离 — MUST

- Control Plane 保存事实状态、配置与治理规则。
- Data Plane 消费已发布的 Runtime Snapshot，并保持无状态。
- 除 Provider 调用适配外，不得把企业治理职责交给 LiteLLM 或 Provider。

**AC-GEN-001**

- Data Plane 的在线请求链路在 Control Plane 短时不可用时仍能继续处理请求。
- 代码扫描可证明 Data Plane 不依赖 Control Plane 的业务数据库 Repository。
- Data Plane 能暴露当前使用的 `config_version` 与配置陈旧度。

### REQ-GEN-002 单一事实源 — MUST

- PostgreSQL / Control Plane 是管理状态事实源。
- Redis 和进程内存只作为配置发布、缓存、原子状态与 Data Plane 加速层。
- 禁止把 Redis 中的临时值当作不可恢复的唯一业务事实。

### REQ-GEN-003 配置版本化 — MUST

所有影响请求行为的配置对象必须具备版本与发布信息。最低字段要求：

```text
id
name
status
version
created_at
updated_at
created_by
updated_by
tenant_id       # 全局资源可为空
revision        # 发布对象
 effective_at
rollback_revision
content_hash
```

请求侧必须记录生效的 `config_version`。

### REQ-GEN-004 租户优先 — MUST

- 所有租户资源访问显式携带 `tenant_id`。
- 禁止“先查询所有租户数据，再由应用代码过滤”的实现。
- 数据访问层、缓存 Key、运行时快照、审计和测试都必须体现租户边界。

### REQ-GEN-005 失败显式化 — MUST

拒绝、降级、回退、缓存命中、策略覆盖等决策必须输出结构化 reason code，不得只依靠自由文本日志。

最低可追踪上下文：

```text
request_id
trace_id
tenant_id
config_version
decision/reason_code
provider/model
retry/fallback/cache status
```

### REQ-GEN-006 异步副作用 — MUST

Usage、Billing、Audit、Analytics 等不参与在线决策的副作用必须通过 Kafka 或等价异步事件机制处理；在线请求不得等待这些下游数据库写入完成。

### REQ-GEN-007 可逆变更 — MUST

高风险配置生命周期必须支持：

```text
Draft -> Validate -> Publish -> Observe -> Rollback
```

禁止把“直接修改生产 Redis / 内存”作为常规发布流程。

### REQ-GEN-008 配置发布一致性 — MUST

发布链路必须满足：

```text
Admin/User
  -> Control Plane validate + authorize
  -> PostgreSQL transaction
  -> Outbox/Event
  -> compile Runtime Snapshot
  -> Redis publish/version notification
  -> Data Plane fetch
  -> atomic in-memory swap
```

发布失败时旧版本必须继续生效，不允许半发布。

建议采用 `revision + compare-and-swap` 或双缓冲 Runtime Snapshot。

### REQ-GEN-009 Runtime Snapshot — MUST

Data Plane 消费的配置必须被编译为紧凑运行时快照。结构至少能表达以下语义：

```json
{
  "config_version": 1842,
  "tenant_id": "t_01",
  "model_alias": "smart-chat",
  "policy_ids": ["p_budget", "p_region"],
  "route_strategy": "latency_cost_weighted",
  "providers": ["openai-us", "claude-jp", "gemini-ap"]
}
```

字段可扩展，但不得丢失版本、租户、模型别名、策略、路由策略和候选 Provider 这些核心语义。

### REQ-GEN-010 Redis 故障退化 — MUST

- Redis 短时故障时，Data Plane 可继续使用最后一个内存快照。
- 超过最大允许陈旧时间后的 fail-open / fail-closed 策略属于 `TBD`，必须做成可配置或待 ADR 决策，不得硬编码为单一行为。

### REQ-GEN-011 事件契约 — MUST

事件最少包含：

```text
event_id
event_type
schema_version
occurred_at
tenant_id
request_id / trace_id
producer
payload
```

消费者必须支持重复投递；不得假设 Kafka “只投递一次”。

### REQ-GEN-012 Secret 处理 — MUST

- 控制平面敏感字段只保存 `secret_ref`。
- 不保存 Provider 明文 Key。
- 日志、错误、追踪、镜像层和构建输出不得泄漏密钥。

### REQ-GEN-013 管理 API 通用模式 — MUST

管理资源 API 采用以下资源化模式：

```text
POST  /admin/<resource>
GET   /admin/<resource>/{id}
PATCH /admin/<resource>/{id}
POST  /admin/<resource>/{id}:publish
POST  /admin/<resource>/{id}:rollback
```

所有写操作必须支持幂等，并生成审计事件。

> `Idempotency-Key` 的具体 Header 名称、有效期和冲突语义：`TBD`。

### REQ-GEN-014 安全默认值 — MUST

- 管理操作必须强身份认证并执行资源级授权。
- 高风险操作（密钥、全局策略、模型下线、预算上限）应由受控角色执行，并为双人审批预留能力。
- 默认不记录完整 Prompt / Response。
- 如租户策略启用正文采集，必须支持 PII 脱敏与保留期限。
- 对外错误不得泄漏内部 endpoint、Provider Key、策略源码或堆栈。

### REQ-GEN-015 可观测性基线 — MUST

平台至少采集：

- 请求数、成功率、拒绝原因；
- 端到端延迟与内部阶段耗时；
- Provider 延迟与错误；
- Cache hit；
- Retry / Fallback；
- Token；
- Cost；
- Budget 消耗；
- Config Version；
- 配置发布成功率；
- 配置传播延迟。

`tenant_id` 可以作为受控维度；不得把 `user_id`、`request_id` 直接作为高基数 Prometheus label。

---

# Part II. Repository 与代码结构

## 2. EPIC-REP：Monorepo 与 Repository

### 2.1 目标目录

Codex 必须以以下目录为工程基线：

```text
enterprise-ai-platform/
  apps/
    gateway/
    iam/
    billing/
    provider/
    policy/
    router/
    audit/
  packages/
    sdk/
    common/
    auth/
    telemetry/
    db/
    cache/
  deploy/
    helm/
    kubernetes/
    terraform/
  ops/
  docs/
  scripts/
```

早期如果 Gateway 仍是较集中实现，内部允许按以下边界演进：

```text
api/
auth/
router/
policy/
provider/
billing/
telemetry/
db/
scheduler/
config/
```

### REQ-REP-001 apps 边界 — MUST

`apps/` 放置可独立构建、部署、拥有运行时生命周期的应用/服务。当前基线至少包含：Gateway、IAM、Billing、Provider、Policy、Router、Audit。

### REQ-REP-002 packages 边界 — MUST

`packages/` 放置可复用组件，至少覆盖 SDK、Common、Auth、Telemetry、DB、Cache。

共享包不得成为跨领域直接读写业务表的捷径。

### REQ-REP-003 deploy / ops / docs / scripts — MUST

- `deploy/helm`：Helm Chart。
- `deploy/kubernetes`：原生 Kubernetes 资源或环境补丁。
- `deploy/terraform`：基础设施即代码。
- `ops/`：SLO、Runbook、告警、运营脚本/资产。
- `docs/`：架构、接口、ADR、运维说明。
- `scripts/`：开发、构建、迁移、校验类工具脚本。

### REQ-REP-004 所有权 — MUST

每个应用/共享组件必须有明确 Owner，并关联：

```text
owner
SLO
runbook
upgrade window
data retention responsibility (if applicable)
```

Owner 的具体组织名称：`TBD`。

### REQ-REP-005 跨域集成 — MUST

跨领域优先使用稳定 API / 事件，不得通过共享数据库表形成隐式耦合。

### REQ-REP-006 版本策略 — MUST

仓库必须支持组件和 API 的可追踪版本；具体 Monorepo package 版本发布策略属于 `TBD`，但不得破坏 Chapter 71 的 SemVer 与兼容性约束。

### TASK-REP-001 Repository Bootstrap

**交付物**

- 创建上述目录。
- 为每个应用增加最小 README / owner 元数据占位。
- 增加根目录开发入口文档与本需求文档链接。
- 增加基础 lint/test/build 命令入口。

**AC-REP-001**

- 新开发者或 Codex 从仓库根目录可定位所有服务、共享库、部署代码、运维资产和文档。
- 不存在不可解释的跨域“common business logic”。

---

## 3. EPIC-CODE：代码规范、DDD 分层与插件接口

### REQ-CODE-001 分层 — MUST

每个需要领域建模的服务必须体现：

```text
Domain
Application
Infrastructure
```

Volume 8 要求明确依赖方向，但未规定具体语言、框架、包命名或依赖注入框架；这些属于 `TBD`，Codex 不得自行把某种框架选择写成平台标准。

### REQ-CODE-002 Router Plugin — MUST

Router 必须提供可扩展插件接口，避免把策略写成长链 `if/else`。

插件协议的具体方法签名：`TBD`。

实现必须至少允许后续新增路由策略而不修改核心请求生命周期。

### REQ-CODE-003 Policy Plugin — MUST

Policy 必须通过稳定接口执行策略判断，并支持结构化结果。

策略结果至少表达：

```text
allow
deny_reason
obligations
matched_policy_ids
policy_version
```

### REQ-CODE-004 Provider Adapter — MUST

Provider 适配层必须屏蔽具体 Provider 差异，不允许上层业务依赖 Provider Key 或内部 endpoint。

LiteLLM 可以作为 Runtime/Provider 适配能力的一部分，但不能承载 Control Plane 治理事实状态。

### REQ-CODE-005 Guardrail — MUST

Guardrail 需要在 Input / Output 两侧存在安全处理链，并输出结构化 verdict。

PII 处理至少应支持按字段类型进行：

```text
mask
tokenize
```

高风险内容的阻断、降级或人工升级动作由租户策略决定。

### REQ-CODE-006 Cache 插件边界 — MUST

Cache 必须能够在不污染领域逻辑的前提下实现进程内/Redis/语义缓存的接入。语义缓存只用于明确允许近似命中的场景。

### REQ-CODE-007 测试约束 — MUST

核心领域与插件接口必须可通过 Provider Mock、策略 Mock、缓存 Mock 等方式测试，测试不得依赖真实外部模型才能执行基础逻辑。

### TASK-CODE-001 插件协议定义

Codex 需要在实现具体 Router/Policy/Provider 之前先提交接口协议与契约测试骨架。

**AC-CODE-001**

- 可增加一个新的 Router Plugin 而不修改主请求控制流程。
- 可增加一个新的 Provider Adapter 而不泄露 Provider 专属凭据给上层。
- Policy 返回结构化 decision，不使用仅日志文本表达拒绝原因。

---

# Part III. 数据库与迁移

## 4. EPIC-DB：PostgreSQL DDL 与 Migration

### 4.1 最小业务表集合

数据库至少覆盖：

```text
tenant
user
role
api_key
provider
provider_capability
model / model_mapping
route_policy
usage
audit_event
```

Volume 8 仅给出了部分 DDL 完整字段，因此未给出字段的表必须以领域设计/ADR 补齐，Codex 不得擅自把推测字段视为正式契约。

### REQ-DB-001 tenant — MUST

基线 DDL：

```sql
CREATE TABLE tenant (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  plan TEXT NOT NULL,
  status TEXT NOT NULL,
  budget_monthly NUMERIC(18,6),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### REQ-DB-002 provider_endpoint — MUST

基线 DDL：

```sql
CREATE TABLE provider_endpoint (
  id UUID PRIMARY KEY,
  provider_name TEXT NOT NULL,
  region TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  secret_ref TEXT NOT NULL,
  priority INT NOT NULL DEFAULT 100,
  weight INT NOT NULL DEFAULT 100,
  enabled BOOLEAN NOT NULL DEFAULT true,
  config_version BIGINT NOT NULL DEFAULT 1
);
```

### REQ-DB-003 model_route — MUST

基线 DDL：

```sql
CREATE TABLE model_route (
  id UUID PRIMARY KEY,
  tenant_id UUID REFERENCES tenant(id),
  model_alias TEXT NOT NULL,
  provider_endpoint_id UUID REFERENCES provider_endpoint(id),
  provider_model TEXT NOT NULL,
  strategy TEXT NOT NULL,
  weight INT NOT NULL DEFAULT 100,
  priority INT NOT NULL DEFAULT 100,
  enabled BOOLEAN NOT NULL DEFAULT true
);
```

### REQ-DB-004 provider_capability — MUST

能力数据模型必须能描述：

```text
capability name
support level
limits
max context / context length
tool calling mode
multimodal size limits
capability version
```

Router 必须先按 capability 过滤候选，再比较成本/延迟等路由指标。

### REQ-DB-005 Usage 写入策略 — MUST

Usage 不得在在线调用路径中“每请求同步插入并立刻做在线聚合”。

推荐流：

```text
request completed
 -> emit Kafka usage event
 -> Billing consumer
 -> aggregate by hour or required time bucket
 -> PostgreSQL / analytics storage
```

### REQ-DB-006 Audit 写入 — MUST

所有生产管理变更与关键调用审计必须可追踪操作者、版本、时间与影响对象。

### REQ-DB-007 Migration — MUST

数据库迁移必须使用：

```text
expand
 -> deploy compatible code
 -> backfill
 -> contract
```

大表迁移必须支持在线索引/低锁影响方式和限速；具体 PostgreSQL 工具与阈值：`TBD`。

### REQ-DB-008 Outbox — MUST

数据库事实状态与异步配置/审计事件之间必须采用 Outbox 或等价事务事件机制，避免数据库提交成功但事件永久丢失。

### TASK-DB-001 Migration Framework

**交付物**

- migration 工具集成；
- 上述基线表 migration；
- rollback/forward 文档；
- expand/contract 示例迁移；
- CI migration validation。

**AC-DB-001**

- 空数据库可一键迁移到当前 schema。
- 当前版本应用和兼容迁移期间的上一版本应用可按发布方案并存。
- Migration 失败不会破坏已运行版本读取旧 schema 的能力。

---

# Part IV. API、错误与 SDK

## 5. EPIC-API：OpenAPI、版本、错误码与 SDK

### REQ-API-001 OpenAI Compatible Surface — MUST

平台必须提供 OpenAI Compatible API Surface，基线至少包含：

```text
POST /v1/chat/completions
```

### REQ-API-002 API Version — MUST

公共 API 使用 `/v1` 基线路径。未来版本演进必须符合 Chapter 71 兼容要求。

### REQ-API-003 Authentication — MUST

`/v1/chat/completions` OpenAPI 必须表达 Bearer / API Key 类鉴权能力。

具体 security scheme 定义和 Header 名称：`TBD`。

### REQ-API-004 基线 HTTP 状态 — MUST

至少支持以下响应语义：

```text
200 Success
400 Invalid request
401 Authentication failed
403 Policy or model denied
429 Rate or quota exceeded
502 Provider failure after fallback exhaustion
```

Volume 8 未规定完整 JSON Error Schema、内部错误码枚举与 402 语义；本开发需求不自行补充，需后续 API ADR 决策。

### REQ-API-005 管理 API — MUST

管理 API 使用 Part I 中定义的资源化 create/read/patch/publish/rollback 模式。

### REQ-API-006 Pagination — MUST

管理列表 API 必须提供分页能力。

分页采用 cursor 还是 offset：`TBD`。

### REQ-API-007 Idempotency — MUST

管理写操作必须提供幂等能力。

幂等键存储介质、TTL、重放响应策略：`TBD`。

### REQ-API-008 OpenAPI as Contract — MUST

OpenAPI 文档必须能够被自动校验并用于 SDK 生成与兼容性测试。

### REQ-API-009 SDK Generation — MUST

SDK 必须从稳定 API 契约生成或与其进行机器可验证同步。

Volume 8 未指定必须支持的 SDK 语言集合，因此语言列表：`TBD`。

### REQ-API-010 Compatibility Test — MUST

API 修改必须运行兼容性检查，不能在未标记 Breaking Change 的情况下静默删除字段、改变含义或破坏现有 `/v1` 客户端。

### 5.1 OpenAPI 基线

```yaml
openapi: 3.1.0
info:
  title: Enterprise AI Platform API
  version: 1.0.0
paths:
  /v1/chat/completions:
    post:
      operationId: createChatCompletion
      security:
        - BearerAuth: []
        - ApiKeyAuth: []
      responses:
        '200': {description: Success}
        '400': {description: Invalid request}
        '401': {description: Authentication failed}
        '403': {description: Policy or model denied}
        '429': {description: Rate or quota exceeded}
        '502': {description: Provider failure after fallback exhaustion}
```

### TASK-API-001 API Contract Bootstrap

**交付物**

- `openapi.yaml`；
- schema lint；
- compatibility/diff 检查；
- server stub 或 handler binding；
- SDK 生成入口。

**AC-API-001**

- OpenAPI 3.1 校验通过。
- `/v1/chat/completions` 可通过契约测试。
- 错误响应不泄漏 Provider Key、内部 endpoint、策略源码或 stack trace。

---

# Part V. 构建与镜像

## 6. EPIC-BLD：Dockerfile 与构建标准

### REQ-BLD-001 Multi-stage Build — MUST

所有生产镜像采用多阶段构建。

### REQ-BLD-002 Minimal Runtime Image — MUST

运行时镜像应保持最小化，仅包含执行所需依赖。

### REQ-BLD-003 Non-root — MUST

生产容器不得以 root 身份运行。

### REQ-BLD-004 Dependency Lock — MUST

依赖必须锁定版本；具体包管理器由实现语言决定，语言和包管理器：`TBD`。

### REQ-BLD-005 Health Endpoints — MUST

可部署应用需要暴露 Kubernetes 可使用的健康检查端点。Gateway 基线：

```text
/healthz
/readyz
```

### REQ-BLD-006 SBOM — MUST

CI 构建必须生成 SBOM，并为镜像签名预留/实现能力。

### REQ-BLD-007 Secret-free Image — MUST

构建过程中不得把密钥写入镜像层。

### REQ-BLD-008 Build Cache — SHOULD

构建流程应支持依赖与镜像层缓存，但缓存不可包含明文 Secret。

### REQ-BLD-009 Image Tag — MUST

镜像标签必须可追溯到源码版本/发布版本。具体 tag 组合：`TBD`。

### AC-BLD-001

- 容器启动身份非 root。
- 镜像扫描可生成 SBOM。
- 镜像历史层不包含 Provider/API 密钥。
- `/healthz`、`/readyz` 可由 Kubernetes probe 使用。

---

# Part VI. Kubernetes 与 Helm

## 7. EPIC-HELM：完整 Helm 部署模型

### REQ-HELM-001 Chart Scope — MUST

Helm 部署模型必须覆盖：

```text
gateway
control-plane
runtime
observability
dependency charts
values examples
production overrides
upgrade strategy
```

### REQ-HELM-002 Gateway Deployment Baseline — MUST

Gateway Kubernetes 基线：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: gateway
  template:
    metadata:
      labels:
        app: gateway
    spec:
      containers:
        - name: gateway
          image: registry.example.com/ai-platform/gateway:${VERSION}
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /readyz
              port: 8080
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "2"
              memory: "2Gi"
```

上述值是 Volume 8 的部署起点；生产调优可通过 values override，不得把环境差异复制为多套不可维护模板。

### REQ-HELM-003 Kubernetes Workload Safety — MUST

工作负载必须考虑：

```text
requests / limits
readiness probe
liveness probe
startup probe
PodDisruptionBudget
topology spread
```

### REQ-HELM-004 Node Isolation — SHOULD

Data Plane 与 GPU Runtime 可使用独立 node pool，以避免资源争抢。

### REQ-HELM-005 Production Values — MUST

必须至少有可区分开发/测试/生产的 values 或环境覆盖机制。

具体 namespace、域名、证书 issuer、storage class：`TBD`。

### REQ-HELM-006 Upgrade Strategy — MUST

Chart 升级必须能与 Chapter 71 的 API/DB/config compatibility 同步，支持失败回滚。

### TASK-HELM-001 Helm Bootstrap

**交付物**

- Chart 目录；
- gateway deployment/service；
- probes/resources；
- env values；
- upgrade/rollback 命令说明；
- helm lint/template CI。

**AC-HELM-001**

- `helm lint` 通过。
- `helm template` 可生成有效资源。
- Gateway 默认 3 replicas、8080 端口、`/readyz`/`/healthz` probes 与资源限制生效。

---

# Part VII. Terraform 与环境拓扑

## 8. EPIC-IAC：Terraform

### REQ-IAC-001 Module Coverage — MUST

Terraform 模块至少覆盖：

```text
network
kubernetes
postgres
redis
kafka
object-storage
kms
dns
```

### REQ-IAC-002 Environment Coverage — MUST

基础设施必须支持：

```text
dev
stage
prod
```

环境差异通过变量/环境配置表达，公共模块应复用。

### REQ-IAC-003 Kubernetes Requirements — MUST

IaC 创建/配置的 Kubernetes 环境必须能够承载 Chapter 66 的资源约束和独立 node pool 需求。

### REQ-IAC-004 Redis — MUST

Redis 用于共享缓存和原子状态。缓存层语义：

```text
L1 process memory: ultra-low latency
L2 Redis: shared cache / atomic state
L3 semantic cache: only when approximate semantic reuse is explicitly allowed
```

所有缓存命中必须按租户与策略版本隔离。

### REQ-IAC-005 Kafka — MUST

- Topic 按事件域划分。
- Key 需要保证所需的局部顺序。
- Consumer 支持幂等、重试和 DLQ。
- Schema 显式 version；禁止静默改变字段语义。

### REQ-IAC-006 Object Storage — MUST

Object Storage 为平台/数据域提供对象存储能力。

RAG 索引/检索不属于 Gateway 业务：Gateway 只传递安全上下文、预算和 trace，并通过稳定接口调用知识域能力。

### REQ-IAC-007 KMS / Secret — MUST

- 应用仅持有 `secret_ref` 或短期凭据。
- KMS 用于 envelope encryption。
- Vault / 云 Secrets Manager 用于访问审计与轮换。
- Break-glass 使用独立受控流程。

具体云厂商与 Secret Manager 产品：`TBD`。

### REQ-IAC-008 Cloud Provider — TBD

Volume 8 没有指定 AWS/Azure/GCP 或其他云为唯一实现。因此 Codex 不能自行把某一云厂商写死为平台架构标准。

### TASK-IAC-001 Terraform Skeleton

**交付物**

```text
deploy/terraform/modules/network
deploy/terraform/modules/kubernetes
deploy/terraform/modules/postgres
deploy/terraform/modules/redis
deploy/terraform/modules/kafka
deploy/terraform/modules/object-storage
deploy/terraform/modules/kms
deploy/terraform/modules/dns
deploy/terraform/environments/dev
deploy/terraform/environments/stage
deploy/terraform/environments/prod
```

**AC-IAC-001**

- `terraform fmt` / validate 通过。
- 环境模块无明文 Secret。
- 生产变量和开发变量可分离。

---

# Part VIII. CI/CD 与 GitOps

## 9. EPIC-CICD：GitHub Actions、Harbor、ArgoCD

### REQ-CICD-001 Pipeline — MUST

生产交付主流程：

```text
Pull Request
 -> Test / Lint / Security
 -> Build Image
 -> Push Harbor
 -> Update Environment Manifest
 -> ArgoCD Sync
 -> Smoke / SLO Check
 -> Promote OR Rollback
```

### REQ-CICD-002 PR Gate — MUST

PR 必须至少经过：

```text
lint
test
security checks
```

具体 lint/test 工具与最低覆盖率：`TBD`。

### REQ-CICD-003 Image Build and Push — MUST

通过 CI 构建符合 Chapter 65 要求的镜像并推送 Harbor。

### REQ-CICD-004 Security Scan — MUST

CI 必须执行依赖/镜像/Secret 等安全扫描。具体扫描器：`TBD`。

### REQ-CICD-005 Environment Promotion — MUST

环境晋级通过 Git 中的期望状态变更进行，而不是 CI 直接操作生产工作负载。

### REQ-CICD-006 ArgoCD Source of Desired State — MUST

Git 是部署期望状态事实源；ArgoCD 负责 drift detection、sync 和 rollback。

### REQ-CICD-007 No Direct Production kubectl — MUST

生产环境禁止 CI 直接执行：

```bash
kubectl apply ...
```

作为常规发布手段。

### REQ-CICD-008 Rollback — MUST

Smoke/SLO 检查失败后必须能够回滚到上一可用部署/manifest 版本。

### TASK-CICD-001 CI Bootstrap

**交付物**

- PR workflow；
- test/lint/security jobs；
- image build/SBOM/sign jobs；
- Harbor push；
- environment manifest update mechanism；
- ArgoCD deployment definition；
- smoke/SLO gate；
- rollback procedure。

**AC-CICD-001**

- CI 无生产集群直接写权限或不把直接 `kubectl apply` 作为部署路径。
- 任一版本可从 Git commit + image tag 追溯。
- ArgoCD 可发现 drift。

---

# Part IX. 测试与安全验证

## 10. EPIC-TST：测试策略

### REQ-TST-001 Unit Test — MUST

核心领域、Application Service、插件逻辑需要单元测试。

具体覆盖率阈值：`TBD`。

### REQ-TST-002 Contract Test — MUST

必须对 API、事件、Provider Adapter、Runtime Snapshot 等稳定契约进行契约测试。

### REQ-TST-003 Provider Mock — MUST

基础 CI 测试不得依赖真实 Provider 才能执行；必须提供 Provider Mock / Fake。

### REQ-TST-004 E2E — MUST

需要覆盖从鉴权/策略到路由/Provider Mock/usage event 的端到端核心路径。

### REQ-TST-005 Failure Injection — MUST

故障注入至少验证：

- Control Plane 不可用时 Data Plane 使用最后快照；
- Redis 短时不可用；
- Provider 错误导致 Retry/Fallback；
- 异步事件重复；
- 配置发布失败保持旧 revision。

### REQ-TST-006 Performance Regression — MUST

建立性能回归测试。具体 RPS、P95/P99、TTFT 数值阈值由 SLO/容量规划决定，当前为 `TBD`。

### REQ-TST-007 Security Scan — MUST

安全验证必须包括代码/依赖/镜像/Secret 扫描和租户隔离测试。

### REQ-TST-008 Threat Model — MUST

至少覆盖以下威胁：

```text
credential leakage
cross-tenant unauthorized access
malicious prompt/tool arguments
SSRF / data exfiltration
provider supply-chain risk
PII in logs
model output secret leakage
replay attack
resource exhaustion
```

高风险控制必须有自动化验证和审计证据。

### REQ-TST-009 Policy Test — MUST

策略引擎需要能够表达并测试类似以下约束：

```cel
request.tenant.status == "active" &&
request.model in tenant.allowed_models &&
request.region in tenant.allowed_regions &&
budget.month_spend + request.estimated_cost <= budget.month_limit
```

策略判定必须返回：

```text
allow
deny_reason
obligations
matched_policy_ids
policy_version
```

Obligation 至少能承载以下类型的后续要求：

```text
mask/redact
force region
disable body logging
limit max_tokens
```

### REQ-TST-010 Release Gate — MUST

发布门禁必须聚合测试、安全、迁移、Smoke/SLO 结果；任何必须项失败时不得自动晋级生产。

### TASK-TST-001 Test Harness

**交付物**

- unit test framework；
- contract test harness；
- Provider Mock；
- E2E environment；
- fault injection suite；
- performance regression entrypoint；
- security scan jobs。

---

# Part X. Roadmap 与实施顺序

## 11. EPIC-RM：Phase 1–5

Codex 应优先按以下阶段实现，不应在 Phase 1 尚未形成可运行闭环时先大规模开发 Phase 5 能力。

### Phase 1 / MVP

**必须完成**

```text
统一 API
API Key
LiteLLM
Redis
PostgreSQL
Retry / Fallback
Prometheus
```

**Exit Criteria — REQ-RM-001**

上述能力形成可运行、可部署、可观察的最小闭环。

### Phase 2 / 企业可用

**必须完成**

```text
多租户
Budget / Usage
Provider Registry
Model Registry
Health
Cache
基本 Audit
```

**Exit Criteria — REQ-RM-002**

多租户治理、预算/用量、Provider/Model 管理、健康和缓存可被测试环境验证。

### Phase 3 / 平台化

**必须完成**

```text
Web Console
RBAC / OIDC
Billing
灰度 / A-B Testing
OpenTelemetry
Langfuse
```

**Exit Criteria — REQ-RM-003**

控制平面具备企业管理入口，身份授权、计费、灰度与完整观测链路可用。

### Phase 4 / 云原生

**必须完成**

```text
Kubernetes
Helm
ArgoCD
HPA
Redis Cluster
PostgreSQL HA
Kafka
Multi-Region
```

**Exit Criteria — REQ-RM-004**

部署、扩缩容、高可用、事件总线和多 Region 能力形成生产级运行模型。

### Phase 5 / AI 平台

按业务优先级接入：

```text
MCP
Agent
RAG
Prompt Registry
Workflow
Evaluation
Safety Guardrail
Marketplace
```

**Exit Criteria — REQ-RM-005**

这些能力必须建立在前四阶段的治理、运行和观测基础上，不得绕开统一 IAM、Policy、Budget、Audit 和 Trace。

### REQ-RM-006 团队拓扑 — MUST

各领域必须有明确 Owner。Volume 8 没有指定组织人数或具体 Team 名称，因此具体团队划分属于 `TBD`。

---

# Part XI. 发布、兼容、弃用与变更管理

## 12. EPIC-REL：Release Management

### REQ-REL-001 SemVer — MUST

平台发布使用 SemVer 语义管理版本。具体 Monorepo 是统一版本还是独立组件版本：`TBD`。

### REQ-REL-002 API Compatibility — MUST

- `/v1` 内不得静默引入破坏性变更。
- Breaking Change 必须通过明确版本/迁移路径处理。
- API compatibility test 必须作为发布 Gate。

### REQ-REL-003 Model Alias Switch — MUST

模型切换应通过 Model Alias / 配置发布完成，而不是要求客户端直接切换真实 Provider 模型名。

切换必须可观察、可回滚。

### REQ-REL-004 Provider Canary — MUST

Provider 切换必须支持灰度/受控发布，而不是一步全量替换。

具体权重阶梯与观察窗口：`TBD`。

### REQ-REL-005 DB Migration Compatibility — MUST

所有涉及数据库 schema 的发布遵循：

```text
expand -> compatible deployment -> backfill -> contract
```

### REQ-REL-006 Config Rollback — MUST

生产配置必须保存 revision 和 rollback target；失败后能够恢复上一可用配置。

### REQ-REL-007 Deprecation Window — MUST

API、模型别名、配置字段或能力弃用必须有明确弃用窗口。

具体窗口时长：`TBD`。

### REQ-REL-008 Change Evidence — MUST

任何生产配置变更至少可以回答：

```text
who
what revision
when
impact scope
rollback revision
```

---

# Part XII. 生产上线与运营移交

## 13. EPIC-OPS：Go-live / Day-2

### REQ-OPS-001 Go-live Gate — MUST

生产上线前必须完成 Gate。Gate 至少聚合：

```text
functional verification
security approval
migration readiness
capacity validation
observability readiness
runbook readiness
rollback readiness
```

具体审批系统：`TBD`。

### REQ-OPS-002 Capacity Model — MUST

容量模型至少考虑：

```text
RPS
concurrency
input token distribution
output token distribution
TTFT
Provider quota
fallback amplification
```

### REQ-OPS-003 N-1 Validation — MUST

必须验证 N-1 Provider / Region 场景，确认单个关键 Provider 或 Region 不可用后的服务行为与容量余量。

### REQ-OPS-004 Security Approval — MUST

生产上线必须有安全审批与证据记录。具体审批角色/系统：`TBD`。

### REQ-OPS-005 SLO — MUST

平台必须定义并监控 SLO。Volume 8 未给出具体可用性、P95/P99 或 TTFT 数值，因此数值阈值必须由后续 SLO 文档/ADR 定义，Codex 不得自行填入生产承诺。

### REQ-OPS-006 Runbook — MUST

每个关键服务/故障模式必须关联 Runbook，至少覆盖：

```text
symptom
alert
impact
diagnosis
mitigation
rollback / failover
verification
escalation
```

上述字段是把 Volume 8 的 Runbook 要求整理成 Codex 可实现的文档骨架；具体故障项由服务实现补齐。

### REQ-OPS-007 On-call — MUST

平台进入生产后必须有明确值班/升级责任。具体排班与工具：`TBD`。

### REQ-OPS-008 Evidence Pack — MUST

上线需要形成可审计证据包，至少关联：测试结果、安全扫描、配置/版本、部署记录、迁移结果、SLO/Smoke 结果、回滚方案。

### REQ-OPS-009 Day-2 Operations — MUST

项目完成不以“部署成功”为终点。必须提供后续运行所需的监控、告警、容量复核、变更、升级、故障处理和回滚资产。

### AC-OPS-001

- 可以在不查源码的情况下，从 Dashboard/Trace/Audit 回答“谁在何时使用哪个模型、为什么路由到该 Provider、花费多少、是否发生 retry/cache/fallback”。
- Control Plane 短时不可用不会让 Data Plane 立即停止服务。
- 配置或版本失败有可执行回滚路径。
- 跨租户、权限绕过和 Secret 泄漏验证通过。

---

# Part XIII. 全局接口与数据契约

## 14. Runtime Config Contract

### 14.1 Minimum Runtime Snapshot

```json
{
  "config_version": 1842,
  "tenant_id": "t_01",
  "model_alias": "smart-chat",
  "policy_ids": ["p_budget", "p_region"],
  "route_strategy": "latency_cost_weighted",
  "providers": ["openai-us", "claude-jp", "gemini-ap"]
}
```

### 14.2 原子切换要求

Data Plane 必须：

1. 收到版本通知；
2. 拉取完整候选快照；
3. 校验快照；
4. 原子替换当前内存引用；
5. 新请求使用新版本；
6. 旧 in-flight 请求允许按原上下文结束；
7. 上报 active version 与 staleness。

其中第 6 点的具体 in-flight 切换语义未在 Volume 8 规定，因此若实现存在差异必须写 ADR，不得隐藏。

## 15. Event Contract

最低事件 envelope：

```json
{
  "event_id": "uuid",
  "event_type": "ConfigPublished",
  "schema_version": 1,
  "occurred_at": "RFC3339 timestamp",
  "tenant_id": "t_01",
  "request_id": "optional",
  "trace_id": "optional",
  "producer": "control-plane",
  "payload": {}
}
```

### REQ-EVT-001 Idempotent Consumer — MUST

Consumer 按 `event_id` 或业务幂等键去重。

### REQ-EVT-002 Backlog Isolation — MUST

Kafka 事件堆积不得阻塞在线模型请求。

### REQ-EVT-003 Schema Version — MUST

任何字段语义变化必须通过显式 schema version 管理。

---

# Part XIV. Codex 可执行开发 Backlog

## 16. Milestone M0 — Bootstrap

### TASK-M0-001 初始化 Monorepo

依赖：无。

完成：

- `apps/ packages/ deploy/ ops/ docs/ scripts/`；
- 根目录开发说明；
- 基础 lint/test/build 入口；
- owner/TBD 占位。

### TASK-M0-002 定义公共契约目录

依赖：M0-001。

需要至少能存放：

```text
OpenAPI
Event Schema
Runtime Snapshot Schema
Policy Decision Schema
ADR
```

### TASK-M0-003 建立 CI Skeleton

依赖：M0-001。

先建立 PR lint/test/security 空门禁，再逐步接入真实测试。

---

## 17. Milestone M1 — Data Foundation

### TASK-M1-001 PostgreSQL Migration

实现 `tenant`、`provider_endpoint`、`model_route` 基线表和其他必选业务表的 migration 骨架。

对于 Volume 8 未定义字段的表，只创建经领域设计确认的字段；未确认的保持 ADR/TBD，禁止臆造业务约束。

### TASK-M1-002 Outbox/Event

实现事务写入 + 事件发布边界。

### TASK-M1-003 Redis Snapshot Store

实现版本化 Snapshot 的写入、读取与当前版本指针。

### TASK-M1-004 Data Plane Snapshot Consumer

实现版本通知、拉取、校验、原子替换和 staleness 指标。

---

## 18. Milestone M2 — API Runtime

### TASK-M2-001 OpenAPI 3.1 Baseline

实现 `/v1/chat/completions` 契约。

### TASK-M2-002 Authentication Boundary

接入 Bearer/API Key 协议接口；具体 Identity Provider 属于 `TBD`。

### TASK-M2-003 Policy Decision Interface

实现结构化 Policy Decision。

### TASK-M2-004 Router Plugin Interface

提供插件注册/组合边界；具体路由算法由对应领域需求实现。

### TASK-M2-005 Provider Adapter Interface

实现 Provider 抽象，并接入 LiteLLM Runtime 边界。

### TASK-M2-006 Retry/Fallback

形成 Phase 1 要求的可验证 Retry / Fallback 流程，并输出结构化 reason/telemetry。

### TASK-M2-007 Usage Event

请求完成后异步发布 Usage 事件，不阻塞在线响应。

---

## 19. Milestone M3 — Build & Deploy

### TASK-M3-001 Production Dockerfile

多阶段、最小镜像、non-root、依赖锁定、健康检查、SBOM、无 Secret。

### TASK-M3-002 Helm Gateway

实现 Gateway Deployment 基线与环境 values。

### TASK-M3-003 Terraform Skeleton

建立 network/kubernetes/postgres/redis/kafka/object-storage/kms/dns 模块与 dev/stage/prod 环境目录。

### TASK-M3-004 GitOps

实现 Harbor + environment manifest + ArgoCD sync + smoke/SLO + rollback 流程。

---

## 20. Milestone M4 — Quality Gate

### TASK-M4-001 Unit/Contract Tests

### TASK-M4-002 Provider Mock + E2E

### TASK-M4-003 Failure Injection

### TASK-M4-004 Performance Regression Harness

### TASK-M4-005 Security & Threat Validation

### TASK-M4-006 Release Gate

Gate 必须阻止测试/安全/兼容性/迁移/Smoke 必须项失败的版本晋级生产。

---

## 21. Milestone M5 — Production Readiness

### TASK-M5-001 SLO & Dashboard

数值目标由 `TBD` SLO 决策输入，Codex 不自行定义对外承诺。

### TASK-M5-002 Runbook Set

覆盖 Control Plane、Redis、Provider、配置发布、数据库迁移和回滚等关键故障。

### TASK-M5-003 Capacity / N-1 Test

验证 RPS、并发、Token 分布、TTFT、Provider quota、fallback amplification 和 N-1 Provider/Region。

### TASK-M5-004 Evidence Pack

归档测试、安全、构建、镜像、SBOM、部署、迁移、SLO/Smoke、回滚证据。

---

# Part XV. Definition of Done

## 22. 单个任务 DoD

每个 TASK 只有同时满足以下条件才可标记完成：

- [ ] 对应代码/配置/文档已提交。
- [ ] 有自动化测试或机器可验证证据。
- [ ] 租户边界已验证（如适用）。
- [ ] Secret 不在代码、配置明文、镜像层或日志中。
- [ ] 失败路径有明确 reason code。
- [ ] 有必要的 metrics/logs/traces。
- [ ] 对配置/数据库变化存在兼容与回滚说明。
- [ ] OpenAPI/Event/Schema 变化已同步契约。
- [ ] CI Gate 通过。
- [ ] 没有把 `TBD` 擅自实现为不可配置的生产标准。

## 23. Phase DoD

每个 Roadmap Phase 必须同时满足：

- [ ] 本 Phase Exit Criteria 全部满足。
- [ ] 所有 MUST 需求有测试或验证证据。
- [ ] 未完成的 SHOULD 有明确 ADR/风险记录。
- [ ] 所有生产相关变更可追踪版本和回滚目标。
- [ ] Dashboard/Alert/Runbook 与新增能力同步。
- [ ] 安全、租户隔离、Secret 扫描通过。

## 24. Production DoD

生产版本额外必须满足：

- [ ] GitOps 是生产部署唯一常规事实源。
- [ ] 生产部署不依赖 CI 直接 `kubectl apply`。
- [ ] 镜像可追踪、存在 SBOM、无明文 Secret。
- [ ] DB migration 采用兼容发布流程。
- [ ] 配置可版本化发布与回滚。
- [ ] Control Plane 故障时 Data Plane 可继续使用最后有效快照。
- [ ] Redis 短故障有内存快照退化路径。
- [ ] N-1 Provider/Region 验证完成。
- [ ] On-call / Runbook / Evidence Pack 就绪。

---

# Part XVI. 禁止事项（Codex Guardrails）

## 25. MUST NOT

Codex 不得：

1. 让 LiteLLM 成为租户、预算、审计、策略等企业治理的事实源。
2. 让 Data Plane 在线请求正常路径直接读取 Control Plane PostgreSQL。
3. 在 Provider 配置表中保存明文 Provider Key；只能保存 `secret_ref`。
4. 把 Usage/Billing/Audit 同步 SQL 写入作为模型调用完成的前置条件。
5. 把跨租户数据先全量查询后在业务层过滤。
6. 把 Provider / Policy / Router 决策只写成无结构日志。
7. 在配置发布失败时覆盖掉最后一个可用 Runtime Snapshot。
8. 假设 Kafka 不会重复投递。
9. 在生产 CI 中把 `kubectl apply` 当作常规发布路径。
10. 在镜像层、构建参数输出、日志或错误中写入 Provider Secret。
11. 在 `/v1` 内无兼容策略地引入 Breaking Change。
12. 用一次性 destructive migration 替代 expand/backfill/contract。
13. 在 Volume 8 未指定的技术决策上自行宣布唯一标准，例如云厂商、SDK 语言、覆盖率数字、SLO 数值、弃用天数。

---

# Part XVII. 待架构决策清单（TBD Register）

## 26. Codex 遇到以下问题时不得自行定案

| ID | 待决策项 | Volume 8 状态 | 开发处理方式 |
|---|---|---|---|
| TBD-001 | 后端主语言 / Web Framework | 未指定 | 保持实现现状或等待用户/ADR |
| TBD-002 | DDD 具体目录命名 / DI 框架 | 未指定 | 不写成平台标准 |
| TBD-003 | Router Plugin 方法签名 | 未指定 | 先定义最小接口并记录 ADR |
| TBD-004 | Policy Runtime 具体使用 CEL/OPA/自研 | 本卷未定唯一方案 | 接口先行 |
| TBD-005 | Idempotency Header / TTL | 未指定 | 契约留扩展点 |
| TBD-006 | Pagination cursor/offset | 未指定 | API 设计评审后确定 |
| TBD-007 | SDK 语言集合 | 未指定 | 只建立生成流水线 |
| TBD-008 | API 完整 Error JSON Schema | 未指定 | 先按 OpenAPI 状态语义实现 |
| TBD-009 | 测试覆盖率阈值 | 未指定 | CI 留门禁参数 |
| TBD-010 | SLO/SLI 数字 | 未指定 | Dashboard 支持，目标另行配置 |
| TBD-011 | Cloud Provider | 未指定 | Terraform 模块避免不必要锁定 |
| TBD-012 | Secret Manager 产品 | 未指定 | `secret_ref` 抽象先行 |
| TBD-013 | Image Tag 规范细节 | 未指定 | 保证源码/版本可追踪 |
| TBD-014 | Provider 灰度权重/观察窗口 | 未指定 | 配置化 |
| TBD-015 | Deprecation Window 时长 | 未指定 | 变更流程预留字段 |
| TBD-016 | Redis 最大配置陈旧时间 | 未指定 | 配置化，不硬编码 |
| TBD-017 | fail-open / fail-closed 资源策略 | 未指定 | 按资源配置/ADR |
| TBD-018 | 团队/Owner 具体名称 | 未指定 | 元数据占位 |
| TBD-019 | 生产域名/Namespace/StorageClass | 未指定 | Helm/Terraform variables |
| TBD-020 | on-call / 审批系统 | 未指定 | 接口/文档占位 |

---

# Part XVIII. 需求追踪矩阵

## 27. Volume 8 Chapter -> Development Epic

| Volume 8 | 原章节 | 本需求文档 Epic | 关键交付 |
|---|---|---|---|
| Chapter 61 | Monorepo 与 Repository 结构 | EPIC-REP | Repo、Ownership、边界 |
| Chapter 62 | 代码规范、DDD 分层与插件接口 | EPIC-CODE | DDD、Router/Policy/Provider/Guardrail/Cache 插件 |
| Chapter 63 | 数据库 DDL 与 Migration | EPIC-DB | PostgreSQL、Migration、Outbox、Usage 聚合 |
| Chapter 64 | OpenAPI、错误码、API 版本与 SDK | EPIC-API | `/v1`、OpenAPI、幂等、分页、SDK、兼容 |
| Chapter 65 | Dockerfile 与构建标准 | EPIC-BLD | 多阶段、non-root、SBOM、Secret-free |
| Chapter 66 | 完整 Helm 部署模型 | EPIC-HELM | Gateway/CP/Runtime/Obs Chart、生产 values |
| Chapter 67 | Terraform 模块与环境拓扑 | EPIC-IAC | Network/K8s/Postgres/Redis/Kafka/Object/KMS/DNS |
| Chapter 68 | GitHub Actions、Harbor、ArgoCD 与 GitOps | EPIC-CICD | CI、Harbor、GitOps、ArgoCD、Rollback |
| Chapter 69 | 测试策略 | EPIC-TST | Unit/Contract/E2E/Load/Security/Threat |
| Chapter 70 | Roadmap 与团队拓扑 | EPIC-RM | Phase 1–5、Exit Criteria、Owners |
| Chapter 71 | 发布、兼容、弃用与变更管理 | EPIC-REL | SemVer、Compatibility、Canary、Rollback |
| Chapter 72 | 生产上线与运营移交 | EPIC-OPS | Gate、Capacity、SLO、Runbook、On-call、Evidence |

---

# Part XIX. Codex 开工入口

## 28. 推荐第一批任务顺序

Codex 在一个空仓库或尚未形成工程骨架的仓库中，应依次执行：

```text
1. TASK-M0-001  Monorepo bootstrap
2. TASK-M0-002  Contract directories
3. TASK-M0-003  CI skeleton
4. TASK-M1-001  PostgreSQL migration
5. TASK-M1-002  Outbox/event
6. TASK-M1-003  Redis snapshot store
7. TASK-M1-004  Data Plane snapshot consumer
8. TASK-M2-001  OpenAPI baseline
9. TASK-M2-002  Auth boundary
10. TASK-M2-003 Policy decision interface
11. TASK-M2-004 Router plugin interface
12. TASK-M2-005 Provider adapter + LiteLLM boundary
13. TASK-M2-006 Retry/Fallback
14. TASK-M2-007 Usage async event
15. TASK-M3-001 Production Dockerfile
16. TASK-M3-002 Helm gateway
17. TASK-M3-003 Terraform skeleton
18. TASK-M3-004 GitOps
19. TASK-M4-*    Test/security/release gates
20. TASK-M5-*    Production readiness
```

若仓库已经存在代码，Codex 应先做 Gap Analysis：把现有实现映射到本文 `REQ-*`，只创建缺失项，不重写已经满足且没有违反本需求的模块。

## 29. 每次 Codex PR 的建议输出

Codex 完成一个任务时，在 PR/最终回复中输出：

```text
Implemented Requirements:
- REQ-...

Changed Files:
- ...

Tests / Evidence:
- ...

Architecture Constraints Checked:
- CP/DP separation
- tenant isolation
- config versioning
- async side effects
- rollback
- secret safety

TBD / ADR Needed:
- ...

Acceptance Criteria:
- [x] AC-...
```

---

# Appendix A. 最小验收场景

## A.1 配置发布

1. Admin 修改配置。
2. Control Plane 鉴权、授权、校验。
3. PostgreSQL 提交 revision。
4. Outbox 发布 `ConfigPublished`。
5. Snapshot Compiler 更新 Redis。
6. Data Plane 收到版本通知。
7. Data Plane 校验并原子替换内存快照。
8. 新请求记录新 `config_version`。
9. 发布异常时旧快照继续服务。

## A.2 Control Plane 故障

1. 停止 Control Plane。
2. 使用已有 Data Plane 调用 `/v1/chat/completions`。
3. 请求仍可按最后已验证配置执行。
4. 指标显示配置 staleness。

## A.3 Redis 短故障

1. Data Plane 已加载快照。
2. 暂时中断 Redis。
3. Data Plane 使用内存快照继续服务。
4. 不发生同步数据库降级查询。

## A.4 Provider Failure

1. Provider Mock 返回错误/超时。
2. Router/Runtime 执行 Retry/Fallback。
3. Telemetry 记录失败 Provider、retry_count、fallback 和最终结果。
4. 所有失败原因结构化输出。

## A.5 Tenant Isolation

1. Tenant A token/API Key 请求 Tenant B 资源。
2. 请求必须被资源级授权拒绝。
3. Data/Cache/Runtime Snapshot 不得返回 Tenant B 内容。
4. 审计可追踪该拒绝。

## A.6 Config Rollback

1. 发布 revision N+1。
2. Smoke/SLO Gate 失败。
3. 执行 rollback 到 N。
4. Data Plane 原子恢复 N。
5. Audit 能定位发布人、发布时间、N+1、N 和失败原因。

## A.7 GitOps Rollback

1. PR 通过 Test/Lint/Security。
2. 构建镜像并推送 Harbor。
3. 更新环境 manifest。
4. ArgoCD Sync。
5. Smoke/SLO 失败。
6. 回滚 Git/ArgoCD 到上一状态。
7. CI 不直接 `kubectl apply` 生产集群。

---

# Appendix B. 来源约束说明

本文档是对 `Volume-08-Implementation.md` Chapter 61–72 的 **开发需求化整理**，不是重新设计平台架构。

为让 Codex 可直接执行，本文增加了：

- 需求 ID；
- Epic / Task / Acceptance Criteria；
- Definition of Done；
- TBD Register；
- 推荐实施顺序；
- Codex Guardrails。

这些增加项用于把原工程实施章节转化为可追踪开发工作流；没有把 Volume 8 未明确给出的云厂商、框架、SLO 数字、测试覆盖率、弃用天数、SDK 语言等内容擅自设为生产事实。所有此类缺口均显式标记为 `TBD`。


# Appendix C. Volume 8 必选设计项逐项追踪

以下索引逐项保留 Volume 8 各章“本章覆盖”的必选设计项名称。Codex 做 Gap Analysis 时必须逐项核对，不能因为某项被合并进 Epic 而忽略。

## C.61 Chapter 61 — Monorepo 与 Repository 结构

对应：`EPIC-REP`。

- [ ] **apps/** — 必须在 `EPIC-REP` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **packages/** — 必须在 `EPIC-REP` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **deploy/** — 必须在 `EPIC-REP` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **ops/** — 必须在 `EPIC-REP` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **docs/** — 必须在 `EPIC-REP` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **scripts/** — 必须在 `EPIC-REP` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **共享库边界** — 必须在 `EPIC-REP` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **版本策略** — 必须在 `EPIC-REP` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.62 Chapter 62 — 代码规范、DDD 分层与插件接口

对应：`EPIC-CODE`。

- [ ] **Domain/Application/Infrastructure** — 必须在 `EPIC-CODE` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **依赖方向** — 必须在 `EPIC-CODE` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Router Plugin** — 必须在 `EPIC-CODE` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Policy Plugin** — 必须在 `EPIC-CODE` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Provider Adapter** — 必须在 `EPIC-CODE` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Guardrail** — 必须在 `EPIC-CODE` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Cache** — 必须在 `EPIC-CODE` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **测试约束** — 必须在 `EPIC-CODE` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.63 Chapter 63 — 数据库 DDL 与 Migration

对应：`EPIC-DB`。

- [ ] **tenant** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **user** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **api_key** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **provider** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **provider_capability** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **model** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **route_policy** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **usage** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **audit** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **迁移流程** — 必须在 `EPIC-DB` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.64 Chapter 64 — OpenAPI、错误码、API 版本与 SDK

对应：`EPIC-API`。

- [ ] **OpenAI Compatible Surface** — 必须在 `EPIC-API` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **/v1** — 必须在 `EPIC-API` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **管理 API** — 必须在 `EPIC-API` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **错误模型** — 必须在 `EPIC-API` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **分页** — 必须在 `EPIC-API` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **幂等** — 必须在 `EPIC-API` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **SDK 生成** — 必须在 `EPIC-API` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **兼容性测试** — 必须在 `EPIC-API` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.65 Chapter 65 — Dockerfile 与构建标准

对应：`EPIC-BLD`。

- [ ] **多阶段构建** — 必须在 `EPIC-BLD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **最小基础镜像** — 必须在 `EPIC-BLD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **非 root** — 必须在 `EPIC-BLD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **依赖锁定** — 必须在 `EPIC-BLD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **健康检查** — 必须在 `EPIC-BLD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **SBOM** — 必须在 `EPIC-BLD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **缓存** — 必须在 `EPIC-BLD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **镜像标签** — 必须在 `EPIC-BLD` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.66 Chapter 66 — 完整 Helm 部署模型

对应：`EPIC-HELM`。

- [ ] **gateway** — 必须在 `EPIC-HELM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **control-plane** — 必须在 `EPIC-HELM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **runtime** — 必须在 `EPIC-HELM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **observability** — 必须在 `EPIC-HELM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **依赖 Chart** — 必须在 `EPIC-HELM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **values 示例** — 必须在 `EPIC-HELM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **生产覆盖** — 必须在 `EPIC-HELM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **升级策略** — 必须在 `EPIC-HELM` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.67 Chapter 67 — Terraform 模块与环境拓扑

对应：`EPIC-IAC`。

- [ ] **network** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **kubernetes** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **postgres** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **redis** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **kafka** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **object-storage** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **kms** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **dns** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **dev/stage/prod** — 必须在 `EPIC-IAC` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.68 Chapter 68 — GitHub Actions、Harbor、ArgoCD 与 GitOps

对应：`EPIC-CICD`。

- [ ] **PR 检查** — 必须在 `EPIC-CICD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **测试** — 必须在 `EPIC-CICD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **镜像构建** — 必须在 `EPIC-CICD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **扫描** — 必须在 `EPIC-CICD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **推送 Harbor** — 必须在 `EPIC-CICD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **环境晋级** — 必须在 `EPIC-CICD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **ArgoCD Sync** — 必须在 `EPIC-CICD` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **回滚** — 必须在 `EPIC-CICD` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.69 Chapter 69 — 测试策略：Unit、Contract、E2E、Load、Security

对应：`EPIC-TST`。

- [ ] **单元测试** — 必须在 `EPIC-TST` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **契约测试** — 必须在 `EPIC-TST` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Provider Mock** — 必须在 `EPIC-TST` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **E2E** — 必须在 `EPIC-TST` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **故障注入** — 必须在 `EPIC-TST` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **性能回归** — 必须在 `EPIC-TST` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **安全扫描** — 必须在 `EPIC-TST` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **发布门禁** — 必须在 `EPIC-TST` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.70 Chapter 70 — Roadmap 与团队拓扑

对应：`EPIC-RM`。

- [ ] **Phase1 MVP** — 必须在 `EPIC-RM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Phase2 企业可用** — 必须在 `EPIC-RM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Phase3 平台化** — 必须在 `EPIC-RM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Phase4 云原生** — 必须在 `EPIC-RM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Phase5 AI 平台** — 必须在 `EPIC-RM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **团队角色** — 必须在 `EPIC-RM` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **里程碑与 Exit Criteria** — 必须在 `EPIC-RM` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.71 Chapter 71 — 发布、兼容、弃用与变更管理

对应：`EPIC-REL`。

- [ ] **SemVer** — 必须在 `EPIC-REL` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **API Compatibility** — 必须在 `EPIC-REL` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Model Alias 切换** — 必须在 `EPIC-REL` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Provider 灰度** — 必须在 `EPIC-REL` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **数据库迁移** — 必须在 `EPIC-REL` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **配置回滚** — 必须在 `EPIC-REL` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **弃用窗口** — 必须在 `EPIC-REL` 的代码、配置、监控、测试或运维资产中形成可验证实现。

## C.72 Chapter 72 — 生产上线与运营移交

对应：`EPIC-OPS`。

- [ ] **上线 Gate** — 必须在 `EPIC-OPS` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **容量与演练** — 必须在 `EPIC-OPS` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **安全审批** — 必须在 `EPIC-OPS` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **SLO** — 必须在 `EPIC-OPS` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Runbook** — 必须在 `EPIC-OPS` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **值班** — 必须在 `EPIC-OPS` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **证据包** — 必须在 `EPIC-OPS` 的代码、配置、监控、测试或运维资产中形成可验证实现。
- [ ] **Day-2 Operations** — 必须在 `EPIC-OPS` 的代码、配置、监控、测试或运维资产中形成可验证实现。

