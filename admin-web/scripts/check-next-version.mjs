// Fail the build/dev if Next.js is below the patched security baseline
// (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §4.1):
//   15.x must be >= 15.5.18 ; 16.x must be >= 16.2.6 ; >16 assumed OK.
import { createRequire } from "node:module";

const MIN = { 15: [15, 5, 18], 16: [16, 2, 6] };

function parse(v) {
  return v.split("-")[0].split(".").map((n) => parseInt(n, 10));
}
function gte(a, b) {
  for (let i = 0; i < 3; i++) {
    if ((a[i] ?? 0) > (b[i] ?? 0)) return true;
    if ((a[i] ?? 0) < (b[i] ?? 0)) return false;
  }
  return true;
}

try {
  const require = createRequire(import.meta.url);
  const { version } = require("next/package.json");
  const v = parse(version);
  const major = v[0];
  const min = MIN[major];

  if (min && !gte(v, min)) {
    console.error(
      `\n[admin-web] Next.js ${version} is below the required security baseline ` +
        `${min.join(".")} for the ${major}.x line. Run: npm i next@latest\n`
    );
    process.exit(1);
  }
  if (major < 15) {
    console.error(`\n[admin-web] Next.js ${version} is too old (need >= 15.5.18).\n`);
    process.exit(1);
  }
  console.log(`[admin-web] Next.js ${version} OK (security baseline satisfied).`);
} catch (err) {
  console.error("[admin-web] Could not resolve Next.js version:", err.message);
  process.exit(1);
}
