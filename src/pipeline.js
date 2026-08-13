import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { generateTravelPlan } from "./ai/travel-planner.js";
import {
  selectTemplate,
  selectAssets,
  selectIcons
} from "./selectors.js";
import { renderPoster } from "./render.js";

const isDirectRun =
  process.argv[1] &&
  path.resolve(process.argv[1]) ===
    path.resolve(fileURLToPath(import.meta.url));

async function readRequest() {
  const content = await fs.readFile(
    path.join(process.cwd(), "fixtures/request.json"),
    "utf8"
  );

  return JSON.parse(content);
}

function validatePlan(plan) {
  if (plan.trip.days !== plan.itinerary.length) {
    throw new Error("行程天数与 itinerary 数量不一致");
  }

  const budgetTotal = plan.budget.items.reduce(
    (sum, item) => sum + item.amount,
    0
  );

  if (budgetTotal !== plan.budget.total) {
    plan.budget.total = budgetTotal;
  }
}

function buildRoute(days) {
  return {
    type: "decorative",
    points: days.map(item => ({
      day: item.day,
      name: item.theme,
      x: item.visualPosition.x,
      y: item.visualPosition.y
    }))
  };
}

export async function generatePoster({
  jobId = `poster-${Date.now()}`,
  request
}) {
  const plan = await generateTravelPlan(request);

  validatePlan(plan);

  const template = await selectTemplate(request, plan);
  const assets = await selectAssets(template);
  const icons = await selectIcons();

  const manifest = {
    schemaVersion: "1.0",
    renderId: jobId,

    template: {
      id: template.templateId,
      version: template.version
    },

    output: {
      cssWidth: 768,
      cssHeight: 1024,
      width: 1536,
      height: 2048,
      format: "png",
      deviceScaleFactor: 2
    },

    content: {
      ...plan.content,
      itinerary: plan.itinerary,
      tips: plan.tips,
      budget: plan.budget
    },

    assets,
    icons,
    route: buildRoute(plan.itinerary)
  };

  const outputDirectory = path.join(
    process.cwd(),
    "output",
    jobId
  );

  await fs.mkdir(outputDirectory, { recursive: true });

  await fs.writeFile(
    path.join(outputDirectory, "manifest.json"),
    JSON.stringify(manifest, null, 2),
    "utf8"
  );

  const result = await renderPoster({
    manifest,
    template,
    outputDirectory
  });

  return {
    jobId,
    template: manifest.template,
    manifest,
    ...result
  };
}

if (isDirectRun) {
  const request = await readRequest();

  const result = await generatePoster({
    request
  });

  console.log(JSON.stringify(result, null, 2));
}