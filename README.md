# travel-poster-mvp

AI 旅行海报生成器。输入结构化旅行需求 → AI 产出行程 JSON → 规则化选模板/素材/图标 → EJS 渲染 HTML → Playwright 截图输出 PNG。

产出为 **1536×2048 PNG**（CSS 768×1024，`deviceScaleFactor: 2`）与一份**自包含 HTML 目录**，可整目录打包分享。

## 快速开始

```bash
npm install
npm run install-browser      # 首次需要，下载 chromium
npm run generate             # 用 fixtures/request.json 生成一张海报
```

产物在 `output/<jobId>/`：

```
poster.png       海报本体
poster.html      自包含 HTML，资源用 ./assets/ ./fonts/ 相对路径引用
manifest.json    渲染契约（模板版本 + 内容 + 素材 + 图标 + 路线坐标）
style.css        模板样式
render.js        模板渲染脚本
assets/          本次用到的素材与图标副本
fonts/           按本次文案子集化的中文字体
```

## 作为服务运行

```bash
npm run dev      # http://localhost:3000（启动到端口就绪约 2-3 秒）
```

```bash
# 建任务（202 + jobId）
curl -X POST http://localhost:3000/api/v1/posters \
  -H "Content-Type: application/json" \
  -d @fixtures/request.json

# 查状态
curl http://localhost:3000/api/v1/posters/<jobId>

# 取产物
curl http://localhost:3000/results/<jobId>/poster.png -o poster.png
```

请求体不合规返回 **400** 并附字段路径，例如
`poster-request 数据校验失败：/output must have required property 'ratio'`。

渲染并发上限为 2，chromium 实例全局复用。

## 测试

```bash
npm test         # node:test，28 项，约 10 秒（含 3 次真实出图）
```

## 架构

```
fixtures/request.json               用户需求
  ↓ src/ai/travel-planner.js        AI_MODE=fixture 读固定行程；出口强制 ajv 校验
plan（行程 JSON，纯内容，不含任何 HTML／图片地址）
  ↓ src/pipeline.js                 天数与预算一致性校验
  ↓ src/selectors.js                标签打分选模板／素材／图标，素材跨槽位去重
      registry/templates.json · assets.json · icons.json
manifest.json                       渲染契约
  ↓ src/render.js
      src/assets.js                 素材复制进产物，URL 改为 ./assets/ 相对路径
      src/fonts.js                  按 manifest 文本 + 模板文案子集化字体
      EJS 渲染 → src/browser.js 取页面 → 质检 → #poster 截图
output/<jobId>/
```

**设计原则：内容与呈现严格解耦。** AI 只产出语义化 JSON，图片与图标一律由注册表按标签打分选出 —— 模型无权指定视觉资源。

**产物自包含。** 素材与字体都复制进 `output/<jobId>/`，HTML 只用相对路径，因此同一份 HTML 在 Playwright 的 `file://` 截图与 Express 的 `/results/<jobId>/` HTTP 分享下都成立。

**渲染前置质检。** `src/render.js` 检查图片加载、内容溢出、画布尺寸，不合格直接失败而非产出坏图。

## 目录

| 路径 | 说明 |
|---|---|
| `src/` | 管线、选择器、渲染、字体子集化、产物自包含、浏览器池、schema 校验 |
| `templates/hangzhou-classic-001/` | 模板（`manifest.json` 声明槽位与字数限制，`index.ejs` + `style.css` + `render.js`） |
| `registry/` | 模板／素材／图标注册表 |
| `schemas/` | `travel-plan`（AI 出口）与 `poster-request`（API 入口）契约 |
| `scripts/` | 一次性素材处理脚本，见下 |
| `fixtures/` | 示例请求与行程数据 |
| `public/design-sheet.png` | 设计素材雪碧图，`extract-icons.js` 的裁切来源 |

## 素材处理脚本

这些脚本是**一次性**的，素材已处理完并提交，通常不需要再跑。

| 命令 | 作用 |
|---|---|
| `node scripts/extract-icons.js` | 从 `public/design-sheet.png` 裁切图标与插画。给粗框，脚本在框内自动收紧 bbox，近白转 alpha |
| `node scripts/make-transparent.js` | 给 registry 中 `transparent: true` 的素材去白底。**从图像四边 flood fill**，只抠与边缘连通的背景白，主体内部封闭的白色（寺庙／民居的白墙）保留 |
| `npm run optimize-assets` | 图片转码压缩。原素材是伪装成 `.webp` 的未压缩 BMP，sharp 读不了，故用 chromium 解码后重编码 |

原图备份在 `public/images/original/`（已 gitignore），脚本检测到备份存在即跳过，避免二次有损编码。

## 字体

`public/fonts/` 下两个思源 OTF 是**构建依赖** —— `src/fonts.js` 在每次渲染时从它们现场子集化出 woff2（通常 100–150 KB）写入产物。删掉它们会导致渲染报 `ENOENT`。

字符集来自 manifest 实际文本 + 模板源码里的固定文案，因此 AI 产出任何文字都不会缺字。

思源黑体／宋体为 SIL Open Font License 1.1 授权。

## 已知素材缺口

以下为观感与设计稿的主要差距，代码侧已无可做：

1. **Hero 需要无缝全景图**。现有 `hangzhou-hero.webp` 是拱桥／游船／雷峰塔／民居的拼贴，元素间有空隙，且塔身落在副标题带上（现靠文字光晕缓解）。
2. **路线图需要手绘地图素材**。现为 CSS 近似（浅绿陆地 + 不规则西湖水域 + 文字标注）。
3. **DAY4 缺夜间演出小图**。
4. **图标是 PNG 套 SVG 壳**。`public/icons/*.svg` 内部是 127×127 base64 PNG，非矢量，放大会糊。

另有若干工程遗留（质检未覆盖容器整体溢出、`contentLimits` 与 schema 两处硬编码未联动、任务状态纯内存无持久化等）记录在
`docs/superpowers/plans/2026-08-13-poster-render-repair.md` 的「待确认事项」。

## 注意

- 所有路径基于 `process.cwd()`，**必须在项目根目录启动**。
- `AI_MODE` 默认 `fixture`；设为其他值会走 remote 分支，目前抛「尚未配置远程 AI Provider」。接真实模型时必须要求其按 `schemas/travel-plan.schema.json` 输出，并在出口调 `assertValid`。
