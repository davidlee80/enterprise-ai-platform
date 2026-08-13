import fs from "node:fs/promises";
import path from "node:path";
import subsetFont from "subset-font";

const FONT_SOURCES = {
  sans: "public/fonts/SourceHanSansSC-Regular.otf",
  serif: "public/fonts/SourceHanSerifSC-Bold.otf"
};

const ASCII_AND_PUNCTUATION =
  "0123456789" +
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
  "abcdefghijklmnopqrstuvwxyz" +
  " ·，。、：；！？（）()《》—–…¥/%~✓";

const sourceCache = new Map();

async function readSource(kind) {
  if (!sourceCache.has(kind)) {
    sourceCache.set(
      kind,
      await fs.readFile(path.join(process.cwd(), FONT_SOURCES[kind]))
    );
  }

  return sourceCache.get(kind);
}

function flattenStrings(value, collected) {
  if (typeof value === "string") {
    collected.push(value);
    return;
  }

  if (Array.isArray(value)) {
    value.forEach(item => flattenStrings(item, collected));
    return;
  }

  if (value && typeof value === "object") {
    Object.values(value).forEach(item => flattenStrings(item, collected));
  }
}

/**
 * 模板源码里的中文是固定文案（章节标题、"参考约"、"预算合计" 等），
 * 直接把整份源码纳入字符表，避免逐条手工维护而漏字。
 */
async function readTemplateLiterals(templateDirectory) {
  const sources = await Promise.all(
    ["index.ejs", "render.js"].map(name =>
      fs.readFile(path.join(templateDirectory, name), "utf8")
    )
  );

  return sources.join("");
}

export async function collectCharacters(manifest, templateDirectory) {
  const collected = [];

  flattenStrings(manifest.content, collected);
  flattenStrings(manifest.route, collected);

  const text =
    collected.join("") +
    ASCII_AND_PUNCTUATION +
    (await readTemplateLiterals(templateDirectory));

  return [...new Set([...text])].sort().join("");
}

export async function writeSubsetFonts(
  manifest,
  outputDirectory,
  templateDirectory
) {
  const text = await collectCharacters(manifest, templateDirectory);
  const fontDirectory = path.join(outputDirectory, "fonts");

  await fs.mkdir(fontDirectory, { recursive: true });

  const written = {};

  for (const kind of Object.keys(FONT_SOURCES)) {
    const buffer = await subsetFont(await readSource(kind), text, {
      targetFormat: "woff2"
    });

    const fileName = `${kind}-subset.woff2`;

    await fs.writeFile(path.join(fontDirectory, fileName), buffer);

    written[kind] = `./fonts/${fileName}`;
  }

  return written;
}
