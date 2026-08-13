import test, { after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { generatePoster } from "../src/pipeline.js";
import { getBrowser, closeBrowser } from "../src/browser.js";

// 浏览器是单例且常驻，测试跑完必须关闭，否则测试进程不退出。
after(() => closeBrowser());

const request = JSON.parse(
  await fs.readFile(
    path.join(process.cwd(), "fixtures/request.json"),
    "utf8"
  )
);

test("端到端生成 768×1024 海报并通过质检", async () => {
  const jobId = "test-smoke";
  const outputDirectory = path.join(process.cwd(), "output", jobId);

  await fs.rm(outputDirectory, { recursive: true, force: true });

  const result = await generatePoster({ jobId, request });

  assert.equal(result.status, "completed");
  assert.equal(result.quality.passed, true);
  assert.deepEqual(result.quality.failures, []);

  const png = await fs.stat(path.join(outputDirectory, "poster.png"));

  assert.ok(png.size > 10000, `poster.png 过小：${png.size} 字节`);
});

test("产物自包含：资源与字体均为相对路径引用", async () => {
  const jobId = "test-selfcontained";
  const outputDirectory = path.join(process.cwd(), "output", jobId);

  await fs.rm(outputDirectory, { recursive: true, force: true });
  await generatePoster({ jobId, request });

  const html = await fs.readFile(
    path.join(outputDirectory, "poster.html"),
    "utf8"
  );

  assert.doesNotMatch(
    html,
    /file:\/\/\//,
    "产物不应包含 file:// 绝对路径，否则无法通过 HTTP 分享"
  );

  assert.match(html, /\.\/assets\//, "产物应引用 ./assets/ 下的资源");

  const assets = await fs.readdir(
    path.join(outputDirectory, "assets")
  );

  assert.ok(
    assets.length >= 11,
    `产物应包含 7 张素材 + 4 个图标，实际 ${assets.length} 个`
  );
});

test("并发渲染复用同一浏览器实例且都能出图", async () => {
  const jobIds = ["test-concurrent-a", "test-concurrent-b", "test-concurrent-c"];

  await Promise.all(
    jobIds.map(jobId =>
      fs.rm(path.join(process.cwd(), "output", jobId), {
        recursive: true,
        force: true
      })
    )
  );

  const before = await getBrowser();

  const results = await Promise.all(
    jobIds.map(jobId => generatePoster({ jobId, request }))
  );

  const after = await getBrowser();

  assert.equal(before, after, "并发渲染期间浏览器实例被重建了");

  for (const [index, result] of results.entries()) {
    assert.equal(
      result.status,
      "completed",
      `${jobIds[index]} 未完成`
    );

    const png = await fs.stat(
      path.join(process.cwd(), "output", jobIds[index], "poster.png")
    );

    assert.ok(png.size > 10000, `${jobIds[index]} 的 PNG 过小`);
  }
});
