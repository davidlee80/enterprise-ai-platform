import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { collectCharacters, writeSubsetFonts } from "../src/fonts.js";

const templateDirectory = path.join(
  process.cwd(),
  "templates/hangzhou-classic-001"
);

const manifest = {
  content: {
    title: "杭州5天旅行攻略重点总结",
    subtitle: "人间天堂 · 诗画江南",
    itinerary: [{ theme: "西湖经典线", summary: "雷峰塔" }],
    tips: [{ text: "错峰出行更从容" }],
    budget: { items: [{ name: "门票" }] }
  },
  route: { points: [{ name: "西湖经典线" }] }
};

test("collectCharacters 覆盖 manifest 文本与模板固定文案", async () => {
  const characters = await collectCharacters(manifest, templateDirectory);

  for (const needed of "杭州旅行攻略雷峰塔门票核心路线示意图预算合计") {
    assert.ok(characters.includes(needed), `子集字符表缺少「${needed}」`);
  }

  assert.ok(characters.includes("D"), "缺少 ASCII 字符 D（DAY 标签）");
  assert.ok(characters.includes("¥"), "缺少人民币符号");
});

test("writeSubsetFonts 产出可用的 woff2 且体积合理", async () => {
  const outputDirectory = await fs.mkdtemp(
    path.join(os.tmpdir(), "poster-fonts-")
  );

  const written = await writeSubsetFonts(
    manifest,
    outputDirectory,
    templateDirectory
  );

  assert.deepEqual(Object.keys(written).sort(), ["sans", "serif"]);
  assert.equal(written.sans, "./fonts/sans-subset.woff2");

  for (const kind of ["sans", "serif"]) {
    const file = path.join(
      outputDirectory,
      "fonts",
      `${kind}-subset.woff2`
    );

    const buffer = await fs.readFile(file);

    assert.equal(
      buffer.subarray(0, 4).toString("latin1"),
      "wOF2",
      `${kind} 不是合法 woff2`
    );

    assert.ok(
      buffer.length > 8000,
      `${kind} 子集仅 ${buffer.length} 字节，可能未包含 CJK 字形`
    );
  }

  await fs.rm(outputDirectory, { recursive: true, force: true });
});
