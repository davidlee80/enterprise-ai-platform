import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { materializeResources } from "../src/assets.js";

test("materializeResources 复制资源并改写为相对路径", async () => {
  const outputDirectory = await fs.mkdtemp(
    path.join(os.tmpdir(), "poster-assets-")
  );

  const manifest = {
    assets: {
      hero: {
        assetId: "hero-hangzhou-001",
        url: "/public/images/hangzhou-hero.webp"
      }
    },
    icons: {
      ticket: {
        iconId: "ticket-classic",
        url: "/public/icons/ticket.svg"
      }
    }
  };

  await materializeResources(manifest, outputDirectory);

  assert.equal(
    manifest.assets.hero.resolvedUrl,
    "./assets/hero-hangzhou-001.webp"
  );

  assert.equal(
    manifest.icons.ticket.resolvedUrl,
    "./assets/ticket-classic.svg"
  );

  const copied = await fs.stat(
    path.join(outputDirectory, "assets", "hero-hangzhou-001.webp")
  );

  assert.ok(copied.size > 0, "素材未被复制");

  await fs.rm(outputDirectory, { recursive: true, force: true });
});

test("materializeResources 对同一资源不重复复制", async () => {
  const outputDirectory = await fs.mkdtemp(
    path.join(os.tmpdir(), "poster-assets-")
  );

  const shared = {
    assetId: "temple-001",
    url: "/public/images/temple.webp"
  };

  const manifest = {
    assets: { day2: shared, day5: { ...shared } },
    icons: {}
  };

  await materializeResources(manifest, outputDirectory);

  const entries = await fs.readdir(path.join(outputDirectory, "assets"));

  assert.deepEqual(entries, ["temple-001.webp"]);

  await fs.rm(outputDirectory, { recursive: true, force: true });
});
