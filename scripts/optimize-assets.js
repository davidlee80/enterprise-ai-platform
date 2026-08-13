import fs from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

/*
 * public/images/*.webp 实际是未压缩的 BMP 位图（魔数 "BM"），只是扩展名叫 webp。
 * sharp/libvips 不支持 BMP 输入，因此改用 chromium 解码（浏览器原生支持 BMP），
 * 经 canvas 重新编码为真正的 WebP。
 *
 * 注意：BMP 没有 alpha 通道，原本应透明的插画背景已被烧成白色，
 * 转码无法恢复透明度 —— 那需要重新导出素材。
 */

const IMAGE_DIRECTORY = path.join(process.cwd(), "public/images");
const BACKUP_DIRECTORY = path.join(IMAGE_DIRECTORY, "original");

const MAX_WIDTH = 1600;
const QUALITY = 0.82;

function formatSize(bytes) {
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

async function transcode(page, buffer, mimeType) {
  const dataUrl = `data:${mimeType};base64,${buffer.toString("base64")}`;

  const result = await page.evaluate(
    async ({ source, maxWidth, quality }) => {
      const image = new Image();

      image.src = source;

      await image.decode();

      const scale = Math.min(1, maxWidth / image.naturalWidth);
      const canvas = document.createElement("canvas");

      canvas.width = Math.round(image.naturalWidth * scale);
      canvas.height = Math.round(image.naturalHeight * scale);

      canvas
        .getContext("2d")
        .drawImage(image, 0, 0, canvas.width, canvas.height);

      return {
        sourceWidth: image.naturalWidth,
        width: canvas.width,
        height: canvas.height,
        encoded: canvas.toDataURL("image/webp", quality).split(",")[1]
      };
    },
    { source: dataUrl, maxWidth: MAX_WIDTH, quality: QUALITY }
  );

  return {
    sourceWidth: result.sourceWidth,
    width: result.width,
    height: result.height,
    buffer: Buffer.from(result.encoded, "base64")
  };
}

async function optimize(page, fileName) {
  const source = path.join(IMAGE_DIRECTORY, fileName);
  const backup = path.join(BACKUP_DIRECTORY, fileName);

  // 已备份说明这张图之前处理过，跳过以免二次有损编码。
  const alreadyBacked = await fs
    .access(backup)
    .then(() => true)
    .catch(() => false);

  if (alreadyBacked) {
    console.log(`跳过 ${fileName}（已存在原图备份）`);
    return null;
  }

  const original = await fs.readFile(source);

  const isBitmap = original.subarray(0, 2).toString("latin1") === "BM";

  const converted = await transcode(
    page,
    original,
    isBitmap ? "image/bmp" : "image/webp"
  );

  await fs.copyFile(source, backup);
  await fs.writeFile(source, converted.buffer);

  console.log(
    `${fileName.padEnd(24)} ` +
      `${isBitmap ? "BMP" : "WebP"} ${converted.sourceWidth}px → ` +
      `WebP ${converted.width}px  ` +
      `${formatSize(original.length)} → ${formatSize(converted.buffer.length)}  ` +
      `(-${Math.round((1 - converted.buffer.length / original.length) * 100)}%)`
  );

  return {
    originalSize: original.length,
    optimizedSize: converted.buffer.length
  };
}

await fs.mkdir(BACKUP_DIRECTORY, { recursive: true });

const files = (await fs.readdir(IMAGE_DIRECTORY)).filter(name =>
  name.endsWith(".webp")
);

const browser = await chromium.launch({ headless: true });

let totalBefore = 0;
let totalAfter = 0;

try {
  const page = await browser.newPage();

  for (const fileName of files) {
    const result = await optimize(page, fileName);

    if (result) {
      totalBefore += result.originalSize;
      totalAfter += result.optimizedSize;
    }
  }
} finally {
  await browser.close();
}

if (totalBefore > 0) {
  console.log(
    `\n合计 ${formatSize(totalBefore)} → ${formatSize(totalAfter)}  ` +
      `(-${Math.round((1 - totalAfter / totalBefore) * 100)}%)`
  );
  console.log(
    `原图已备份至 ${path.relative(process.cwd(), BACKUP_DIRECTORY)}`
  );
} else {
  console.log("没有需要处理的图片。");
}
