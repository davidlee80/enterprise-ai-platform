import fs from "node:fs/promises";
import path from "node:path";

export async function generateTravelPlan(request) {
  const mode = process.env.AI_MODE || "fixture";

  if (mode === "fixture") {
    const content = await fs.readFile(
      path.join(
        process.cwd(),
        "fixtures/hangzhou-plan.json"
      ),
      "utf8"
    );

    return JSON.parse(content);
  }

  /*
   * remote 模式在这里调用实际 AI 服务。
   *
   * 必须要求模型按 travel-plan.schema.json 输出，
   * 不允许模型直接返回 HTML、图片地址或图标地址。
   */
  throw new Error("尚未配置远程 AI Provider");
}