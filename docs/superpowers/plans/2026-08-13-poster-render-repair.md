# 旅行海报渲染链路修复实施计划

> **执行方式：** 逐任务实施，每个任务独立提交。步骤用 `- [ ]` 追踪。

**Goal:** 从「质检失败、零 PNG 产出」修复到「稳定产出 768×1024 自包含海报、数据契约有校验、服务端可承载并发」。

**Architecture:** 保留现有四段式管线（AI 产出 plan JSON → 注册表打分选模板/素材/图标 → 生成 manifest 渲染契约 → EJS + Playwright 截图）。核心修复是把误粘进 `index.ejs` 的 CSS 归位到 `style.css` 并补齐动态类样式；再把产物改造为**自包含目录**（素材与按需子集化字体复制进 `output/<jobId>/`，HTML 用 `./assets/` `./fonts/` 相对路径），使同一份 HTML 在 `file://` 截图与 `http://` 分享下都成立；最后补 ajv 数据契约、浏览器实例复用与并发队列。

**Tech Stack:** Node.js 24 ESM · Express 5 · EJS 3 · Playwright(chromium) · ajv 8 · subset-font 2（harfbuzz wasm）· sharp 0.35 · node:test

**修复前基线（已实测）：** `npm run generate` 抛 `海报质检失败：画布尺寸错误：752 × 4884.734375`，根因是 CSS 从未被加载。

---

## 关键设计决策

**D1 — 产物自包含取代「URL 双模式」。** 双模式（`file://` 截图 / `/public` 分享）无法让同一份 HTML 两用。改为把本次用到的素材与字体复制进 `output/<jobId>/assets/`、`fonts/`，HTML 只用 `./assets/x.webp` 相对路径 —— `file://` 与 `http://` 同时成立，产物可整目录打包分享。这是对原需求更彻底的达成。

**D2 — 字体按需子集化，不预生成固定字表。** 文案由 AI 动态产出，预生成 3500 字表既大又可能缺字。改为渲染时从 manifest 文本 + 模板源码字面量收集实际字符，用 subset-font 现场生成 woff2。源 OTF Buffer 进程内缓存。现有 3.2KB/3.9KB 的 woff2 是失败的子集化残留，删除。

**D3 — 不改动既有布局数值。** `hero 215px`、`grid-template-rows: 438px 274px`、`gap 10px` 全部保留（`215+10+438+10+274+12 = 959`，底部留 65px 呼吸区）。新增样式只填空缺，不重排既有版式。

**D4 — 视觉严格对齐 `public/287c37369ac7166021452f488b73b138.png` 素材图。** 该图是组件雪碧图（非版式稿），明确了：`.route-number` 为 day 色实心圆 + 白字；`.day-index` 为 day 色圆角方块、上 `DAY` 小字下大号数字；`.day-price` 为浅底 + day 色描边胶囊；`#budgetTotal` 为浅底圆角卡 + 橙色 `#ed7617` 大号金额；`.tip-row` 图标为绿色描边圆形。

---

## 文件结构

**新建**

| 路径 | 职责 |
|---|---|
| `.gitignore` | 忽略 `node_modules/`、`output/`、`public/images/original/` |
| `src/fonts.js` | 字符收集 + 按需字体子集化 → 产物 `fonts/` |
| `src/assets.js` | 素材/图标复制进产物 `assets/`，重写为相对路径 |
| `src/validate.js` | ajv 单例、schema 编译与校验封装 |
| `src/browser.js` | chromium 单例 + 并发闸门 |
| `schemas/poster-request.schema.json` | API 请求体契约 |
| `scripts/optimize-assets.js` | 一次性 webp 压缩 |
| `tests/*.test.js` | 6 个测试文件 |

**修改**

| 路径 | 变更点 |
|---|---|
| `schemas/travel-plan.schema.json` | 0 字节 → 完整 draft-07 schema |
| `templates/.../index.ejs` | 加 HTML 骨架与 stylesheet link；删除第 47 行起误粘的 CSS |
| `templates/.../style.css` | 0 字节 → 完整样式（含 16 个动态类） |
| `templates/.../render.js` | tips 改用语义图标 + `✓` 回退 |
| `registry/icons.json` | 4 项 → 7 项，覆盖 tips 全部 6 种 type |
| `src/selectors.js` | 素材去重、移除恒真打分项、图标语义 fallback |
| `src/render.js` | 接入字体/素材自包含、复用浏览器实例 |
| `src/pipeline.js` | 移除硬编码 5 天断言、接入 plan 校验 |
| `src/ai/travel-planner.js` | 出口接 ajv 校验 |
| `src/server.js` | 入口校验请求体、接入并发队列 |
| `package.json` | 新增依赖与 `test`、`optimize-assets` 脚本 |

---

# 阶段 0：基础设施

### Task 1: 初始化 git 仓库与基线提交
- [ ] `git init`
- [ ] 创建 `.gitignore`（`node_modules/`、`output/`、`public/images/original/`、`*.log`）
- [ ] 提交损坏基线：`chore: 提交修复前基线（CSS 未加载，质检失败）`
- [ ] 验证：`git status --short` 无输出；`git ls-files | grep -c output` 为 0

### Task 2: 接入依赖与测试运行器
- [ ] `npm install subset-font@^2.5.0 sharp@^0.35.3`
- [ ] `package.json` 加 `"test": "node --test tests/"`、`"optimize-assets": "node scripts/optimize-assets.js"`
- [ ] 验证：`npm test` 退出码 0（`# pass 0`）
- [ ] 提交：`chore: 接入 subset-font/sharp 与 node:test 运行器`

---

# 阶段 1：让流程跑通出图

### Task 3: CSS 归位 + HTML 骨架
**Files:** `tests/style-coverage.test.js`(新) · `templates/hangzhou-classic-001/index.ejs` · `.../style.css`

- [ ] 写失败测试 `tests/style-coverage.test.js`，4 条断言：`style.css` 非空 / `index.ejs` 含 DOCTYPE+head+stylesheet link / `index.ejs` 不含 `@font-face` / render.js 用到的每个类名在 CSS 中有定义
- [ ] 运行确认 4 条全失败（缺失类应列出 15 个）
- [ ] 重写 `index.ejs`：加 `<!DOCTYPE html>`/`<head>`/`<link rel="stylesheet" href="./style.css">`，移除第 47 行起误粘的 CSS，hero 背景改用 `manifest.assets.hero.resolvedUrl`
- [ ] 把归位后的 CSS 写入 `style.css`（`@font-face` 指向 `./fonts/*.woff2`，Task 7 生成）
- [ ] 验证：`npm test` → pass 3 / fail 1（剩类名覆盖）
- [ ] 提交：`fix: CSS 归位到 style.css 并为模板补全 HTML 骨架`

### Task 4: 补全 16 个动态类样式
**Files:** `templates/hangzhou-classic-001/style.css`（追加）

尺寸推算：`#schedule` 内容区 400px / 5 行 = 80px 每行；`#tips`、`#budgetItems`+`#budgetTotal` 内容区各 236px。

- [ ] 追加路线图节点：`.route-lines .route-node .route-landmark .route-number .route-day .route-name`
- [ ] 追加五天速览：`#schedule .day-row .day-index .day-content .day-price`
- [ ] 追加备注事项：`#tips .tip-row .tip-check`
- [ ] 追加花销明细：`#budgetItems .budget-item .budget-name #budgetTotal .total-label`
- [ ] 验证：`npm test` → pass 4 / fail 0
- [ ] 提交：`feat: 按素材图补全路线图/速览/备注/花销的完整样式`

### Task 5: 端到端出图冒烟测试
**Files:** `tests/render.smoke.test.js`(新)

- [ ] 写测试：调 `generatePoster`，断言 `status==="completed"`、`quality.passed===true`、`failures` 为空、`poster.png` > 10KB
- [ ] 运行 `npm run generate` 定位真实失败原因；若报 `内容溢出：xxx`，下调该容器 font-size 1px 后重跑，**不改 D3 锁定的版式数值**
- [ ] 验证：`npm test` → pass 5 / fail 0；`ls -l output/test-smoke/` 有 poster.png
- [ ] 目视确认：标题、路线图 5 节点、五天速览、备注 6 条、花销 4 项+合计均无裁切
- [ ] 提交：`test: 补充端到端出图冒烟测试`

---

# 阶段 2：中文字体按需子集化

### Task 6: 实现字体子集化模块
**Files:** `src/fonts.js`(新) · `tests/fonts.test.js`(新)

- [ ] 写失败测试：`collectCharacters` 覆盖 manifest 文本 + 模板固定文案（`核心路线示意图`、`预算合计` 等）+ ASCII + `¥`；`writeSubsetFonts` 产出 `wOF2` 魔数且 > 8KB
- [ ] 实现 `src/fonts.js`：`FONT_SOURCES`（`思源黑體.otf` / `思源宋体Adobe版SourceHanSerifSC-Bold.otf`）、进程内 Buffer 缓存、`flattenStrings` 递归收集、把模板源码整体纳入字符表以免漏固定文案、`subsetFont(buffer, text, {targetFormat:"woff2"})`
- [ ] 验证：`npm test` → pass 7 / fail 0
- [ ] 提交：`feat: 按需字体子集化模块`

### Task 7: 字体接入渲染流程
**Files:** `src/render.js` · 删除 `public/fonts/*.woff2`

- [ ] `render.js` 引入 `writeSubsetFonts`，并入写 HTML 的 `Promise.all`
- [ ] 删除失败残留 `SourceHanSansSC-Regular.woff2`、`SourceHanSerifSC-Bold.woff2`
- [ ] 验证：`ls -l output/*/fonts/` 有两个 woff2，体积 10KB–120KB 量级
- [ ] 目视确认标题为宋体粗体、正文为黑体
- [ ] 提交：`feat: 渲染时生成子集字体并移除失效的 woff2 残留`

### Task 8: 渲染产物自包含（D1）
**Files:** `src/assets.js`(新) · `tests/assets.test.js`(新) · `src/render.js`

- [ ] 写失败测试：`materializeResources` 把 `/public/images/hangzhou-hero.webp` 复制为 `assets/hero-hangzhou-001.webp` 并把 `resolvedUrl` 改写为 `./assets/hero-hangzhou-001.webp`；同一资源不重复复制
- [ ] 实现 `src/assets.js`
- [ ] `render.js` 删除 `resolvePublicAsset`/`enrichResourceUrls`，改调 `materializeResources`；移除 EJS 的 `resolveAsset` 参数
- [ ] 验证：`npm test` → pass 9 / fail 0
- [ ] 验证 HTTP 分享：起服务 POST 建任务，浏览器打开 `http://localhost:3000/results/<jobId>/poster.html`，图片与字体全部正常（修复前此处图片全挂）
- [ ] 提交：`feat: 渲染产物自包含，资源改为相对路径以支持 HTTP 分享`

---

# 阶段 3：数据契约

### Task 9: 行程 schema 与校验封装
**Files:** `schemas/travel-plan.schema.json` · `src/validate.js`(新) · `tests/validate.test.js`(新)

- [ ] 写失败测试：合法 fixture 通过；缺 `itinerary[].visualPosition` / `budget.items[].type` 越界 / `trip.days` 非整数 均应报错且错误信息含字段路径
- [ ] 填写 `travel-plan.schema.json`（draft-07，覆盖 `trip`/`content`/`itinerary`/`tips`/`budget`，`budget.items[].type` 枚举 `ticket|food|transport|other`，`tips[].type` 枚举 6 种，`itinerary[].visualPosition` 必填且 0–100）
- [ ] 实现 `src/validate.js`：ajv 单例（`allErrors:true`）、`compile(name)` 缓存、`assertValid(name, data)` 抛出带字段路径的错误
- [ ] 验证：`npm test` 全绿
- [ ] 提交：`feat: 补全行程数据 schema 与 ajv 校验封装`

### Task 10: AI 出口接校验
**Files:** `src/ai/travel-planner.js` · `tests/validate.test.js`（追加）

- [ ] 追加测试：`generateTravelPlan` 返回值必须通过 `travel-plan` schema
- [ ] `travel-planner.js` 在 return 前调 `assertValid("travel-plan", plan)`
- [ ] 验证：`npm test` 全绿
- [ ] 提交：`feat: AI 出口强制校验行程数据契约`

### Task 11: 请求体 schema + 去除硬编码 5 天
**Files:** `schemas/poster-request.schema.json`(新) · `src/server.js` · `src/pipeline.js`

- [ ] 写失败测试：缺 `output.ratio` 的请求体应被拒；`fixtures/request.json` 应通过
- [ ] 填写 `poster-request.schema.json`（`destination`/`output.ratio` 必填，`profile` 可选）
- [ ] `server.js` 在建任务前校验 `request.body`，不合法返回 400 + 字段路径
- [ ] `pipeline.js` 删除 `if (plan.itinerary.length !== 5) throw`（天数已由 `selectTemplate` 的 `minDays/maxDays` filter 保证）
- [ ] 验证：`npm test` 全绿；`curl -X POST -d '{}'` 返回 400
- [ ] 提交：`feat: API 入口校验请求体并移除硬编码五天限制`

---

# 阶段 4：选择器与图标

### Task 12: 素材去重 + 移除恒真打分项
**Files:** `src/selectors.js` · `tests/selectors.test.js`(新)

- [ ] 写失败测试：两个 requiredTags 相近的槽位不得选中同一 `assetId`
- [ ] `selectAssets` 加已用 `assetId` 排除集
- [ ] `selectTemplate` 移除 `ratios.includes(...)` 与天数区间那两个 `+0.15`（上游已 filter，对所有候选恒定，不影响排序）
- [ ] 验证：`npm test` 全绿
- [ ] 提交：`fix: 素材槽位去重并移除恒真打分项`

### Task 13: 图标注册表补全 + 语义 fallback
**Files:** `registry/icons.json` · `src/selectors.js` · `tests/selectors.test.js`（追加）

映射：`date→calendar` `transport→bus` `walking→clothing` `reservation→reservation` `crowd→other` `environment→other`；budget：`ticket→ticket` `food→food` `transport→bus` `other→other`。

- [ ] 追加测试：`selectIcons()` 结果必须覆盖 tips 全部 6 种 type 与 budget 全部 4 种 type
- [ ] `icons.json` 从 4 项扩到 7 项（新增 `calendar`→semantic `date`、`clothing`→`walking`、`reservation`→`reservation`）
- [ ] `selectIcons` 对未注册 semantic 回退到 `other`
- [ ] 验证：`npm test` 全绿
- [ ] 提交：`feat: 补全图标注册表并支持语义回退`
- [ ] 备注：`public/icons/location.svg` 当前无消费方，未注册

### Task 14: tips 语义图标落地
**Files:** `templates/.../render.js` · `templates/.../style.css`

- [ ] `renderTips` 改为按 `tip.type` 取图标，无图标时回退 `✓`（保留 `.tip-check`）
- [ ] `style.css` 追加 `.tip-icon`（24px 绿色描边圆形）
- [ ] 验证：`npm test` 全绿（类名覆盖测试会要求 `.tip-icon` 有定义）
- [ ] 目视确认 6 条备注各带对应图标
- [ ] 提交：`feat: 备注事项按语义渲染图标`

---

# 阶段 5：服务端与素材

### Task 15: 浏览器复用 + 并发闸门
**Files:** `src/browser.js`(新) · `src/render.js` · `src/server.js`

- [ ] 写测试：连续两次 `renderPoster` 复用同一 browser 实例
- [ ] `src/browser.js`：`getBrowser()` 惰性单例 + `withPage(fn)` 并发闸门（上限 2）+ `closeBrowser()`
- [ ] `render.js` 改用 `withPage`，移除每次 `chromium.launch()`
- [ ] `server.js` 注册 `SIGINT`/`SIGTERM` 时 `closeBrowser()`
- [ ] 验证：`npm test` 全绿；并发 POST 3 个任务全部 completed
- [ ] 提交：`perf: 复用 chromium 实例并限制渲染并发`

### Task 16: 素材压缩
**Files:** `scripts/optimize-assets.js`(新)

- [ ] 脚本：原图备份到 `public/images/original/`，宽 > 1600 缩到 1600，webp quality 80 写回原路径
- [ ] 执行 `npm run optimize-assets`
- [ ] 验证：`hangzhou-hero.webp` 从 3.7MB、`route-background.webp` 从 3.1MB 显著下降；`npm test` 全绿；目视确认 PNG 画质无可见劣化
- [ ] 提交：`perf: 压缩素材图并保留原图备份`

---

## 待确认事项（不在本次范围）

1. **底部 65px 空白** —— D3 保留既有版式数值导致。是否调整 `grid-template-rows` 填满，需产品确认。
2. **质检覆盖面** —— 当前只检 `.day-content`/`.tip-row`/`.budget-item`，未检 `#schedule`/`#tips`/`#budgetItems` 容器整体溢出。建议后续补上。
3. **`contentLimits` 未被消费** —— 模板 manifest 声明了 `titleMaxChars` 等限制，但无代码校验或截断。建议接入 AI 出口校验。
4. **无失败降级** —— 质检不过直接抛错，无「缩字号重试」回路。
5. **图标为 PNG 套 SVG 壳** —— `public/icons/*.svg` 内部是 127×127 base64 PNG，非矢量，放大会糊。需重制矢量图标。
6. **任务状态纯内存** —— `server.js` 的 `jobs` Map 进程重启即丢，无持久化。