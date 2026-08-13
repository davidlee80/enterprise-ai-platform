import fs from "node:fs/promises";
import path from "node:path";

const root = process.cwd();

async function readJson(relativePath) {
  const content = await fs.readFile(
    path.join(root, relativePath),
    "utf8"
  );

  return JSON.parse(content);
}

function normalizeTags(values = []) {
  return new Set(
    values
      .flat()
      .filter(Boolean)
      .map(value => String(value).toLowerCase())
  );
}

function tagScore(sourceTags, candidateTags) {
  const source = normalizeTags(sourceTags);
  const candidate = normalizeTags(candidateTags);

  let matched = 0;

  for (const tag of source) {
    if (candidate.has(tag)) matched += 1;
  }

  return source.size === 0 ? 0 : matched / source.size;
}

export async function selectTemplate(request, plan) {
  const templates = await readJson("registry/templates.json");

  const requestTags = [
    request.destination,
    request.profile?.travelers,
    request.profile?.pace,
    request.profile?.visualPreferences,
    plan.content?.keywords
  ];

  const candidates = templates
    .filter(item => item.status === "published")
    .filter(item => item.ratios.includes(request.output.ratio))
    .filter(item => {
      const days = plan.trip.days;
      return days >= item.minDays && days <= item.maxDays;
    })
    .map(item => ({
      ...item,
      score: tagScore(requestTags, item.tags)
    }))
    .sort((a, b) => b.score - a.score);

  if (!candidates.length) {
    throw new Error("没有找到满足天数和比例要求的模板");
  }

  return candidates[0];
}

export async function selectAssets(template) {
  const assets = await readJson("registry/assets.json");
  const templateManifest = await readJson(template.manifestPath);

  const result = {};

  // 同一张素材不应出现在多个槽位，否则海报会出现重复插画。
  const used = new Set();

  for (const slot of templateManifest.slots) {
    const candidates = assets
      .filter(asset => asset.commercialUse)
      .filter(asset => !used.has(asset.assetId))
      .map(asset => {
        const score =
          tagScore(slot.requiredTags, asset.tags) * 0.85 +
          asset.qualityScore * 0.15;

        return { ...asset, score };
      })
      .sort((a, b) => b.score - a.score);

    if (!candidates.length || candidates[0].score < 0.3) {
      throw new Error(`槽位 ${slot.slotId} 没有匹配素材`);
    }

    used.add(candidates[0].assetId);

    result[slot.slotId] = candidates[0];
  }

  return result;
}

/*
 * 返回 semantic → icon 的扁平表。
 * semantic 带用途前缀（tip- / budget- / section-），因此 tips 与 budget
 * 都有的 transport 不会互相覆盖，模板按 `tip-${type}` 这样取用。
 */
export async function selectIcons() {
  const icons = await readJson("registry/icons.json");

  return Object.fromEntries(icons.map(item => [item.semantic, item]));
}