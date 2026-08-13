import fs from "node:fs/promises";
import path from "node:path";
import ejs from "ejs";
import { writeSubsetFonts } from "./fonts.js";
import { materializeResources } from "./assets.js";
import { withPage } from "./browser.js";

function toFileUrl(filePath) {
  return new URL(`file://${path.resolve(filePath)}`).href;
}

async function qualityCheck(page) {
  return page.evaluate(() => {
    const failures = [];

    if (window.__POSTER_RENDER_ERROR__) {
      failures.push(window.__POSTER_RENDER_ERROR__);
    }

    document.querySelectorAll("img").forEach(image => {
      if (!image.complete || image.naturalWidth === 0) {
        failures.push(`图片加载失败：${image.src}`);
      }
    });

    document.querySelectorAll(
      ".day-content, .tip-row, .budget-item"
    ).forEach(element => {
      if (
        element.scrollHeight > element.clientHeight + 1 ||
        element.scrollWidth > element.clientWidth + 1
      ) {
        failures.push(
          `内容溢出：${element.className}`
        );
      }
    });

    const poster = document.getElementById("poster");
    const rect = poster.getBoundingClientRect();

    if (rect.width !== 768 || rect.height !== 1024) {
      failures.push(
        `画布尺寸错误：${rect.width} × ${rect.height}`
      );
    }

    return {
      passed: failures.length === 0,
      failures
    };
  });
}

export async function renderPoster({
  manifest,
  template,
  outputDirectory
}) {
  await fs.mkdir(outputDirectory, { recursive: true });
  await materializeResources(manifest, outputDirectory);

  const templatePath = path.join(
    process.cwd(),
    template.templatePath
  );

  const html = await ejs.renderFile(templatePath, {
    manifest,
    safeJson(value) {
      return JSON.stringify(value)
        .replaceAll("<", "\\u003c")
        .replaceAll(">", "\\u003e")
        .replaceAll("&", "\\u0026");
    }
  });

  const sourceTemplateDirectory = path.dirname(templatePath);
  const sourceCss = path.join(
    sourceTemplateDirectory,
    "style.css"
  );
  const sourceJs = path.join(
    sourceTemplateDirectory,
    "render.js"
  );

  const htmlPath = path.join(outputDirectory, "poster.html");
  const cssPath = path.join(outputDirectory, "style.css");
  const jsPath = path.join(outputDirectory, "render.js");
  const pngPath = path.join(outputDirectory, "poster.png");

  await Promise.all([
    fs.writeFile(htmlPath, html, "utf8"),
    fs.copyFile(sourceCss, cssPath),
    fs.copyFile(sourceJs, jsPath),
    writeSubsetFonts(manifest, outputDirectory, sourceTemplateDirectory)
  ]);

  return withPage(
    {
      viewport: {
        width: 768,
        height: 1024
      },
      deviceScaleFactor: 2
    },
    async page => {
      await page.goto(toFileUrl(htmlPath), {
        waitUntil: "load"
      });

      await page.waitForFunction(
        () =>
          window.__POSTER_RENDER_READY__ === true ||
          Boolean(window.__POSTER_RENDER_ERROR__),
        null,
        { timeout: 15000 }
      );

      const quality = await qualityCheck(page);

      if (!quality.passed) {
        throw new Error(
          `海报质检失败：${quality.failures.join("；")}`
        );
      }

      const poster = page.locator("#poster");

      await poster.screenshot({
        path: pngPath,
        type: "png",
        animations: "disabled"
      });

      return {
        status: "completed",
        htmlPath,
        imagePath: pngPath,
        quality
      };
    }
  );
}