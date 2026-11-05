// Runs every end-to-end test one after the other: `npm test` (from e2e/).
import { spawnSync } from "node:child_process";
import { cleanup } from "./support.mjs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const tests = [
  "definitions.mjs",
  "device_setup.mjs",
  "device_sync.mjs",
  "devices_health.mjs",
  "coap_sync.mjs",
  "charts.mjs",
];
const failed = [];

for (const test of tests) {
  const run = spawnSync("node", [test], {
    cwd: dirname(fileURLToPath(import.meta.url)),
    stdio: "inherit",
  });
  if (run.status !== 0) failed.push(test);
}

// Leaves no test data behind
cleanup();

console.log(
  failed.length
    ? `\nFailed: ${failed.join(", ")}`
    : `\nAll ${tests.length} e2e tests passed`,
);
process.exitCode = failed.length ? 1 : 0;
