import { chromium } from "playwright";

const MAX_CONCURRENT_PAGES = 2;

let browserPromise = null;
let active = 0;
const waiting = [];

/**
 * 惰性单例：首次调用才启动 chromium，后续渲染复用同一实例。
 * 原实现每个任务都 chromium.launch()，一次冷启动约 300-600ms 且常驻内存。
 */
export function getBrowser() {
  if (!browserPromise) {
    browserPromise = chromium.launch({ headless: true });
  }

  return browserPromise;
}

function acquire() {
  if (active < MAX_CONCURRENT_PAGES) {
    active += 1;
    return Promise.resolve();
  }

  return new Promise(resolve => waiting.push(resolve));
}

function release() {
  const next = waiting.shift();

  if (next) {
    next();
    return;
  }

  active -= 1;
}

/**
 * 在受并发上限保护的页面里执行 fn。
 * 截图是 CPU 密集操作，无上限并发会把内存和 CPU 打满。
 */
export async function withPage(options, fn) {
  await acquire();

  const browser = await getBrowser();
  const page = await browser.newPage(options);

  try {
    return await fn(page);
  } finally {
    await page.close();
    release();
  }
}

export async function closeBrowser() {
  if (!browserPromise) return;

  const browser = await browserPromise;

  browserPromise = null;

  await browser.close();
}
