import Ajv2020 from "ajv/dist/2020";
import addFormats from "ajv-formats";
import { expect } from "vitest";
import schema from "../../../../contracts/scan-result.schema.json";

// ajv compiles with new Function; workerd allows it under @cloudflare/vitest-plugin (D-alief-B07).
const ajv = new Ajv2020({ strict: false, allErrors: true });
addFormats(ajv);
const validate = ajv.compile(schema);

/** Fails the test unless `item` is a valid ScanResult (contracts/scan-result.schema.json). */
export function expectScanResult(item: unknown): void {
  const ok = validate(item);
  expect(ok, JSON.stringify(validate.errors)).toBe(true);
}
