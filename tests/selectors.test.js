import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import {
  selectTemplate,
  selectAssets,
  selectIcons
} from "../src/selectors.js";

const request = JSON.parse(
  await fs.readFile(
    path.join(process.cwd(), "fixtures/request.json"),
    "utf8"
  )
);

const plan = JSON.parse(
  await fs.readFile(
    path.join(process.cwd(), "fixtures/hangzhou-plan.json"),
    "utf8"
  )
);

test("selectTemplate 为杭州五日 3:4 请求选出已发布模板", async () => {
  const template = await selectTemplate(request, plan);

  assert.equal(template.templateId, "hangzhou-classic-001");
  assert.equal(template.status, "published");
});

test("天数超出模板支持范围时明确报错", async () => {
  const threeDayPlan = {
    ...plan,
    trip: { ...plan.trip, days: 3 },
    itinerary: plan.itinerary.slice(0, 3)
  };

  await assert.rejects(
    () => selectTemplate(request, threeDayPlan),
    /没有找到满足天数和比例要求的模板/
  );
});

test("比例不被任何模板支持时明确报错", async () => {
  const squareRequest = {
    ...request,
    output: { ...request.output, ratio: "1:1" }
  };

  await assert.rejects(
    () => selectTemplate(squareRequest, plan),
    /没有找到满足天数和比例要求的模板/
  );
});

test("selectAssets 为每个槽位选出互不重复的素材", async () => {
  const template = await selectTemplate(request, plan);
  const assets = await selectAssets(template);

  const templateManifest = JSON.parse(
    await fs.readFile(
      path.join(process.cwd(), template.manifestPath),
      "utf8"
    )
  );

  const slotIds = templateManifest.slots.map(slot => slot.slotId);

  assert.deepEqual(
    Object.keys(assets).sort(),
    [...slotIds].sort(),
    "每个槽位都应有素材"
  );

  const chosen = Object.values(assets).map(asset => asset.assetId);

  assert.equal(
    new Set(chosen).size,
    chosen.length,
    `同一素材被复用到多个槽位：${chosen.join(", ")}`
  );
});

test("selectIcons 覆盖 tips / budget / 章节标题的全部语义", async () => {
  const icons = await selectIcons();

  const required = [
    ...["date", "transport", "walking", "reservation", "crowd", "environment"]
      .map(type => `tip-${type}`),
    ...["ticket", "food", "transport", "other", "total"]
      .map(type => `budget-${type}`),
    ...["route", "schedule", "tips", "budget"]
      .map(name => `section-${name}`)
  ];

  for (const semantic of required) {
    assert.ok(
      icons[semantic],
      `语义「${semantic}」没有可用图标（会渲染出空图）`
    );

    assert.ok(icons[semantic].url, `语义「${semantic}」的图标缺少 url`);
  }
});

test("图标 semantic 与 iconId 均无重复", async () => {
  const icons = await selectIcons();
  const entries = Object.values(icons);

  const iconIds = entries.map(icon => icon.iconId);

  assert.equal(
    new Set(iconIds).size,
    iconIds.length,
    "iconId 重复会导致产物文件互相覆盖"
  );
});

test("注册的图标文件都真实存在", async () => {
  const icons = await selectIcons();

  for (const [semantic, icon] of Object.entries(icons)) {
    const file = path.join(
      process.cwd(),
      icon.url.replace(/^\/+/, "")
    );

    await fs.access(file).catch(() => {
      assert.fail(`语义「${semantic}」指向的文件不存在：${icon.url}`);
    });
  }
});

test("槽位标签完全相同时也不会把同一素材塞进多个槽位", async () => {
  const assets = await selectAssets({
    manifestPath: "fixtures/duplicate-slots.manifest.json"
  });

  const chosen = Object.values(assets).map(asset => asset.assetId);

  assert.equal(chosen.length, 3, "三个槽位都应有素材");

  assert.equal(
    new Set(chosen).size,
    3,
    `标签相同的槽位选中了重复素材：${chosen.join(", ")}`
  );
});
