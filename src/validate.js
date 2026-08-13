import fs from "node:fs/promises";
import path from "node:path";
import Ajv from "ajv";

const ajv = new Ajv({ allErrors: true });
const validators = new Map();

async function getValidator(name) {
  if (!validators.has(name)) {
    const schema = JSON.parse(
      await fs.readFile(
        path.join(process.cwd(), "schemas", `${name}.schema.json`),
        "utf8"
      )
    );

    validators.set(name, ajv.compile(schema));
  }

  return validators.get(name);
}

/**
 * 校验数据，失败时抛出带字段路径的错误。
 * 字段路径让「模型输出不合规」这类问题能被直接定位。
 */
export async function assertValid(name, data) {
  const validate = await getValidator(name);

  if (!validate(data)) {
    const details = validate.errors
      .map(error => `${error.instancePath || "/"} ${error.message}`)
      .join("；");

    throw new Error(`${name} 数据校验失败：${details}`);
  }

  return data;
}
