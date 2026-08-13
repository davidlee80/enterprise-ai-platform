import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";

const templateDirectory = path.join(
  process.cwd(),
  "templates/hangzhou-classic-001"
);

async function read(name) {
  return fs.readFile(path.join(templateDirectory, name), "utf8");
}

/**
 * 收集 render.js 动态生成的类名：
 * 既包含 HTML 字符串里的 class="..."，也包含 element.className = "..."。
 */
function collectRuntimeClassNames(source) {
  const names = new Set();

  for (const match of source.matchAll(/class="([^"$]+)"/g)) {
    match[1].split(/\s+/).filter(Boolean).forEach(name => names.add(name));
  }

  for (const match of source.matchAll(/className\s*=\s*"([^"]+)"/g)) {
    match[1].split(/\s+/).filter(Boolean).forEach(name => names.add(name));
  }

  return names;
}

test("style.css 非空", async () => {
  const css = await read("style.css");

  assert.ok(css.trim().length > 0, "style.css 不能是空文件");
});

test("index.ejs 具备完整 HTML 骨架并链接样式表", async () => {
  const ejs = await read("index.ejs");

  assert.match(ejs, /<!DOCTYPE html>/i, "缺少 DOCTYPE");
  assert.match(ejs, /<head>/i, "缺少 head");
  assert.match(
    ejs,
    /<link[^>]+rel="stylesheet"[^>]+href="\.\/style\.css"/,
    "缺少 style.css 的 link 标签"
  );
});

test("index.ejs 不含裸露的 CSS 规则", async () => {
  const ejs = await read("index.ejs");

  assert.doesNotMatch(
    ejs,
    /@font-face/,
    "CSS 不应留在 index.ejs 里，应归位到 style.css"
  );
});

test("render.js 使用的每个类名都在 style.css 中有定义", async () => {
  const [renderSource, css] = await Promise.all([
    read("render.js"),
    read("style.css")
  ]);

  const missing = [...collectRuntimeClassNames(renderSource)]
    .filter(name => !css.includes(`.${name}`))
    .sort();

  assert.deepEqual(
    missing,
    [],
    `以下类名缺少样式定义：${missing.join(", ")}`
  );
});
