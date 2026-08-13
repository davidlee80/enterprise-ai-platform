import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { assertValid } from "../src/validate.js";
import { generateTravelPlan } from "../src/ai/travel-planner.js";

const plan = JSON.parse(
  await fs.readFile(
    path.join(process.cwd(), "fixtures/hangzhou-plan.json"),
    "utf8"
  )
);

test("合法行程通过校验", async () => {
  await assertValid("travel-plan", plan);
});

test("缺少 visualPosition 时报错并指出字段路径", async () => {
  const broken = structuredClone(plan);

  delete broken.itinerary[2].visualPosition;

  await assert.rejects(
    () => assertValid("travel-plan", broken),
    /itinerary\/2.*visualPosition/
  );
});

test("budget.items[].type 越界时报错", async () => {
  const broken = structuredClone(plan);

  broken.budget.items[0].type = "hotel";

  await assert.rejects(
    () => assertValid("travel-plan", broken),
    /budget\/items\/0\/type/
  );
});

test("trip.days 非整数时报错", async () => {
  const broken = structuredClone(plan);

  broken.trip.days = 5.5;

  await assert.rejects(
    () => assertValid("travel-plan", broken),
    /trip\/days/
  );
});

test("itinerary[].color 非法色值时报错", async () => {
  const broken = structuredClone(plan);

  broken.itinerary[0].color = "绿色";

  await assert.rejects(
    () => assertValid("travel-plan", broken),
    /itinerary\/0\/color/
  );
});

test("generateTravelPlan 的输出满足行程契约", async () => {
  const generated = await generateTravelPlan({ destination: "杭州" });

  await assertValid("travel-plan", generated);
});

test("fixtures/request.json 满足请求契约", async () => {
  const request = JSON.parse(
    await fs.readFile(
      path.join(process.cwd(), "fixtures/request.json"),
      "utf8"
    )
  );

  await assertValid("poster-request", request);
});

test("缺少 output.ratio 的请求被拒绝", async () => {
  await assert.rejects(
    () => assertValid("poster-request", { destination: "杭州", output: {} }),
    /output.*ratio/
  );
});

test("缺少 destination 的请求被拒绝", async () => {
  await assert.rejects(
    () => assertValid("poster-request", { output: { ratio: "3:4" } }),
    /destination/
  );
});
