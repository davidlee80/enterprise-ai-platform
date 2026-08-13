import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { generatePoster } from "../src/pipeline.js";

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
