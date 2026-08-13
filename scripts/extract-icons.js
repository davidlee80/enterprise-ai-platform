import fs from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

/*
 * 从设计素材总图裁切图标入库。
 *
 * public/287c37369ac7166021452f488b73b138.png 是一张 2048×2048 的组件雪碧图，
 * 其中第四行是章节标题图标（定位钉/日历/灯泡/钱包）与彩色花销图标
 * （票/碗/公交/购物袋/钱袋）。这些图标此前从未被切分入库，
 * 导致 public/icons/ 只有一批文件名与图案错配的旧文件。
 *
 * 给出的 left/width 是粗框，脚本会在框内自动收紧到实际内容的外接矩形，
 * 因此不依赖手工像素对齐。背景为近白，裁切后转为 alpha 通道。
 */

const SHEET = path.join(
  process.cwd(),
  "public/287c37369ac7166021452f488b73b138.png"
);

const ICON_DIRECTORY = path.join(process.cwd(), "public/icons");

// 第四行图标带的纵向范围，九个图标共用。
const ROW_TOP = 1355;
const ROW_HEIGHT = 185;

const ICONS = [
  { name: "section-route", left: 40, width: 140, label: "定位钉" },
  { name: "section-schedule", left: 230, width: 170, label: "日历" },
  { name: "section-tips", left: 430, width: 175, label: "灯泡" },
  { name: "section-budget", left: 610, width: 200, label: "钱包" },
  { name: "budget-ticket", left: 890, width: 230, label: "票" },
  { name: "budget-food", left: 1140, width: 200, label: "碗" },
  { name: "budget-transport", left: 1400, width: 170, label: "公交" },
  { name: "budget-shopping", left: 1640, width: 150, label: "购物袋" },
  { name: "budget-total", left: 1860, width: 160, label: "钱袋" }
];

/*
 * 插画：输出到 public/images/original/ 保留原始像素与白底，
 * 由 scripts/make-transparent.js 负责抠背景。
 * 现有素材缺少 DAY3「运河人文线」需要的石拱桥（canal-bridge.webp 实为木栈道）。
 */
const ILLUSTRATION_DIRECTORY = path.join(
  process.cwd(),
  "public/images/original"
);

const ILLUSTRATIONS = [
  {
    name: "stone-bridge",
    left: 40,
    top: 290,
    width: 680,
    height: 320,
    label: "石拱桥",
    // 相对收紧后图像的遮罩，用背景色抹掉邻近元素蹭进来的部分：
    // 左上角是柳枝，右上角是远山树影。
    masks: [
      { left: 0, top: 0, width: 228, height: 62 },
      { left: 556, top: 0, width: 116, height: 38 }
    ]
  }
];

const OUTPUT_SIZE = 128;
const PADDING = 6;

// 与背景色的欧氏距离：低于 NEAR 视为全透明，高于 FAR 视为全不透明，中间线性过渡。
const NEAR = 10;
const FAR = 34;

function distance(r, g, b, background) {
  return Math.sqrt(
    (r - background[0]) ** 2 +
      (g - background[1]) ** 2 +
      (b - background[2]) ** 2
  );
}

/** 在粗框内收紧到实际内容的外接矩形。 */
function tighten(data, width, height, channels, background) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const offset = (y * width + x) * channels;

      if (
        distance(
          data[offset],
          data[offset + 1],
          data[offset + 2],
          background
        ) > FAR
      ) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < 0) return null;

  return { minX, minY, maxX, maxY };
}

/** 把近背景色像素转成透明，边缘做线性过渡。 */
function applyAlpha(data, width, height, channels, background) {
  const output = Buffer.alloc(width * height * 4);

  for (let i = 0, o = 0; o < output.length; i += channels, o += 4) {
    const r = data[i];
    const g = data[i + 1];
    const b = data[i + 2];

    const d = distance(r, g, b, background);
    const alpha =
      d <= NEAR
        ? 0
        : d >= FAR
          ? 255
          : Math.round(((d - NEAR) / (FAR - NEAR)) * 255);

    output[o] = r;
    output[o + 1] = g;
    output[o + 2] = b;
    output[o + 3] = alpha;
  }

  return output;
}

async function extract(icon) {
  const region = {
    left: icon.left,
    top: ROW_TOP,
    width: icon.width,
    height: ROW_HEIGHT
  };

  const raw = await sharp(SHEET)
    .extract(region)
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const { data, info } = raw;
  const channels = info.channels;

  // 粗框左上角像素作为背景基准。
  const background = [data[0], data[1], data[2]];

  const box = tighten(data, info.width, info.height, channels, background);

  if (!box) {
    throw new Error(`${icon.name} 粗框内没有检测到内容`);
  }

  const tight = {
    left: region.left + Math.max(0, box.minX - PADDING),
    top: region.top + Math.max(0, box.minY - PADDING),
    width: Math.min(
      region.width - Math.max(0, box.minX - PADDING),
      box.maxX - box.minX + 1 + PADDING * 2
    ),
    height: Math.min(
      region.height - Math.max(0, box.minY - PADDING),
      box.maxY - box.minY + 1 + PADDING * 2
    )
  };

  const tightRaw = await sharp(SHEET)
    .extract(tight)
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const withAlpha = applyAlpha(
    tightRaw.data,
    tightRaw.info.width,
    tightRaw.info.height,
    tightRaw.info.channels,
    background
  );

  const file = path.join(ICON_DIRECTORY, `${icon.name}.png`);

  await sharp(withAlpha, {
    raw: {
      width: tightRaw.info.width,
      height: tightRaw.info.height,
      channels: 4
    }
  })
    .resize(OUTPUT_SIZE, OUTPUT_SIZE, {
      fit: "contain",
      background: { r: 0, g: 0, b: 0, alpha: 0 }
    })
    .png({ compressionLevel: 9 })
    .toFile(file);

  const size = (await fs.stat(file)).size;

  console.log(
    `${icon.name.padEnd(20)} ${icon.label.padEnd(4)} ` +
      `${tight.width}×${tight.height} → ${OUTPUT_SIZE}×${OUTPUT_SIZE}  ` +
      `${(size / 1024).toFixed(1)} KB`
  );
}

/** 裁切插画：自动收紧 bbox，保留原始尺寸与白底。 */
async function extractIllustration(item) {
  const region = {
    left: item.left,
    top: item.top,
    width: item.width,
    height: item.height
  };

  const raw = await sharp(SHEET)
    .extract(region)
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const background = [raw.data[0], raw.data[1], raw.data[2]];

  const box = tighten(
    raw.data,
    raw.info.width,
    raw.info.height,
    raw.info.channels,
    background
  );

  if (!box) {
    throw new Error(`${item.name} 粗框内没有检测到内容`);
  }

  const tight = {
    left: region.left + Math.max(0, box.minX - PADDING),
    top: region.top + Math.max(0, box.minY - PADDING),
    width: Math.min(
      region.width - Math.max(0, box.minX - PADDING),
      box.maxX - box.minX + 1 + PADDING * 2
    ),
    height: Math.min(
      region.height - Math.max(0, box.minY - PADDING),
      box.maxY - box.minY + 1 + PADDING * 2
    )
  };

  const file = path.join(ILLUSTRATION_DIRECTORY, `${item.name}.png`);

  const masks = (item.masks ?? []).map(mask => ({
    input: {
      create: {
        width: mask.width,
        height: mask.height,
        channels: 3,
        background: {
          r: background[0],
          g: background[1],
          b: background[2]
        }
      }
    },
    left: mask.left,
    top: mask.top
  }));

  await sharp(SHEET)
    .extract(tight)
    .composite(masks)
    .png()
    .toFile(file);

  console.log(
    `${item.name.padEnd(20)} ${item.label.padEnd(4)} ` +
      `${tight.width}×${tight.height}  ` +
      `${((await fs.stat(file)).size / 1024).toFixed(1)} KB  → original/`
  );
}

for (const icon of ICONS) {
  await extract(icon);
}

await fs.mkdir(ILLUSTRATION_DIRECTORY, { recursive: true });

for (const item of ILLUSTRATIONS) {
  await extractIllustration(item);
}

console.log(
  `\n已写入 ${ICONS.length} 个图标到 public/icons/，` +
    `${ILLUSTRATIONS.length} 张插画到 public/images/original/`
);
