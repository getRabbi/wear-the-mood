import { FlatCompat } from "@eslint/eslintrc";

const compat = new FlatCompat({ baseDirectory: import.meta.dirname });

const eslintConfig = [
  ...compat.extends("next/core-web-vitals", "next/typescript"),
  { ignores: [".next/**", "node_modules/**"] },
  {
    // The console renders arbitrary user-uploaded image URLs (R2 / Supabase /
    // legacy) for moderation. next/image remote-pattern config for every possible
    // host is impractical, and we deliberately do NOT want to optimize/cache UGC
    // under review — so plain <img> is correct here.
    rules: { "@next/next/no-img-element": "off" },
  },
];

export default eslintConfig;
