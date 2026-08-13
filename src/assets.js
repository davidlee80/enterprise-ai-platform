import fs from "node:fs/promises";
import path from "node:path";

/**
 * 把 manifest 引用的素材与图标复制进 output/<jobId>/assets/，
 * 并把 resolvedUrl 改写为 ./assets/<id>.<ext> 相对路径。
 *
 * 相对路径让同一份 poster.html 在 Playwright 的 file:// 截图
 * 与 Express 的 /results/<jobId>/ HTTP 分享下都能加载资源。
 */
export async function materializeResources(manifest, outputDirectory) {
  const assetDirectory = path.join(outputDirectory, "assets");

  await fs.mkdir(assetDirectory, { recursive: true });

  const copied = new Set();

  async function materialize(resource, id) {
    const relativeSource = resource.url.replace(/^\/+/, "");
    const fileName = `${id}${path.extname(relativeSource)}`;

    if (!copied.has(fileName)) {
      await fs.copyFile(
        path.join(process.cwd(), relativeSource),
        path.join(assetDirectory, fileName)
      );

      copied.add(fileName);
    }

    resource.resolvedUrl = `./assets/${fileName}`;
  }

  for (const resource of Object.values(manifest.assets)) {
    await materialize(resource, resource.assetId);
  }

  for (const resource of Object.values(manifest.icons)) {
    await materialize(resource, resource.iconId);
  }

  return manifest;
}
