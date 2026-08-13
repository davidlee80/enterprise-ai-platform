import fs from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

/*
 * 给 registry 中标记 transparent 的素材去掉白色背景。
 *
 * 原始素材是无 alpha 通道的 BMP（扩展名却是 .webp），透明区域已被烧成白色。
 * sharp/libvips 不支持 BMP 输入，因此用 chromium 解码 + canvas 处理像素。
 *
 * 关键点：不能简单地"把近白像素变透明"——插画里的白墙、白色汤汁、
 * 车窗同样是白的，那样会把主体掏空。这里改用从图像四边 flood fill：
 * 只有与边缘连通的背景白被透明化，主体内部封闭的白色保留。
 */

const IMAGE_DIRECTORY = path.join(process.cwd(), "public/images");
const BACKUP_DIRECTORY = path.join(IMAGE_DIRECTORY, "original");
const REGISTRY = path.join(process.cwd(), "registry/assets.json");

// 与背景基准色的欧氏距离阈值：水彩边缘渐变需要略宽松。
const BACKGROUND_TOLERANCE = 26;
// 边缘羽化半径，避免透明区与主体之间出现硬锯齿。
const FEATHER = 1.5;

const QUALITY = 0.9;

function formatSize(bytes) {
  return `${(bytes / 1024).toFixed(1)} KB`;
}

/** 按魔数判断类型：原始素材有 BMP（伪装成 .webp）也有裁切出的 PNG。 */
function detectMimeType(buffer) {
  const head = buffer.subarray(0, 4);

  if (head.subarray(0, 2).toString("latin1") === "BM") return "image/bmp";
  if (head.toString("latin1") === "RIFF") return "image/webp";
  if (head[0] === 0x89 && head[1] === 0x50) return "image/png";

  return "image/jpeg";
}

async function processImage(page, buffer) {
  const dataUrl = `data:${detectMimeType(buffer)};base64,${buffer.toString("base64")}`;

  return page.evaluate(
    async ({ source, tolerance, feather, quality }) => {
      const image = new Image();

      image.src = source;

      await image.decode();

      const canvas = document.createElement("canvas");

      canvas.width = image.naturalWidth;
      canvas.height = image.naturalHeight;

      const context = canvas.getContext("2d", { willReadFrequently: true });

      context.drawImage(image, 0, 0);

      const { width, height } = canvas;
      const frame = context.getImageData(0, 0, width, height);
      const pixels = frame.data;

      const base = [pixels[0], pixels[1], pixels[2]];

      const isBackground = index => {
        const dr = pixels[index] - base[0];
        const dg = pixels[index + 1] - base[1];
        const db = pixels[index + 2] - base[2];

        return Math.sqrt(dr * dr + dg * dg + db * db) <= tolerance;
      };

      // 从四边开始 BFS，只标记与边缘连通的背景像素。
      const outside = new Uint8Array(width * height);
      const queue = [];

      const push = (x, y) => {
        if (x < 0 || y < 0 || x >= width || y >= height) return;

        const cell = y * width + x;

        if (outside[cell]) return;
        if (!isBackground(cell * 4)) return;

        outside[cell] = 1;
        queue.push(cell);
      };

      for (let x = 0; x < width; x++) {
        push(x, 0);
        push(x, height - 1);
      }

      for (let y = 0; y < height; y++) {
        push(0, y);
        push(width - 1, y);
      }

      for (let head = 0; head < queue.length; head++) {
        const cell = queue[head];
        const x = cell % width;
        const y = (cell - x) / width;

        push(x + 1, y);
        push(x - 1, y);
        push(x, y + 1);
        push(x, y - 1);
      }

      // 羽化：紧贴主体的背景像素给一点残留 alpha，避免硬边。
      const radius = Math.ceil(feather);
      let cleared = 0;

      for (let cell = 0; cell < outside.length; cell++) {
        if (!outside[cell]) continue;

        const x = cell % width;
        const y = (cell - x) / width;

        let nearSubject = false;

        for (let dy = -radius; dy <= radius && !nearSubject; dy++) {
          for (let dx = -radius; dx <= radius; dx++) {
            const nx = x + dx;
            const ny = y + dy;

            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;

            if (!outside[ny * width + nx]) {
              nearSubject = true;
              break;
            }
          }
        }

        pixels[cell * 4 + 3] = nearSubject ? 90 : 0;
        cleared += 1;
      }

      context.putImageData(frame, 0, 0);

      return {
        width,
        height,
        clearedRatio: cleared / (width * height),
        encoded: canvas.toDataURL("image/webp", quality).split(",")[1]
      };
    },
    {
      source: dataUrl,
      tolerance: BACKGROUND_TOLERANCE,
      feather: FEATHER,
      quality: QUALITY
    }
  );
}

const assets = JSON.parse(await fs.readFile(REGISTRY, "utf8"));
const targets = assets.filter(asset => asset.transparent);

if (!targets.length) {
  console.log("registry 中没有标记 transparent 的素材。");
  process.exit(0);
}

const browser = await chromium.launch({ headless: true });

try {
  const page = await browser.newPage();

  const backups = await fs.readdir(BACKUP_DIRECTORY);

  for (const asset of targets) {
    const fileName = path.basename(asset.url);
    const stem = fileName.replace(/\.[^.]+$/, "");
    const target = path.join(IMAGE_DIRECTORY, fileName);

    // 优先读 original/ 下的原始文件：它没有经过有损压缩，抠背景更干净。
    // 扩展名可能与 registry 里的 url 不同（BMP 伪装成 .webp，裁切产物是 .png）。
    const backupName = backups.find(
      name => name.replace(/\.[^.]+$/, "") === stem
    );

    const source = backupName
      ? path.join(BACKUP_DIRECTORY, backupName)
      : target;

    const original = await fs.readFile(source);
    const result = await processImage(page, original);

    const output = Buffer.from(result.encoded, "base64");

    await fs.writeFile(target, output);

    console.log(
      `${fileName.padEnd(24)} ${result.width}×${result.height}  ` +
        `抠除背景 ${(result.clearedRatio * 100).toFixed(1)}%  ` +
        `${formatSize(output.length)}`
    );
  }
} finally {
  await browser.close();
}

console.log(`\n已处理 ${targets.length} 张素材，原图保留在 public/images/original/`);
