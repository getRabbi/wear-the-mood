import { describe, expect, it } from "vitest";

import { setConfigSchema, upsertAdminSchema } from "@/lib/validation/admin";

describe("admin settings schemas", () => {
  it("upsert admin needs a valid email + known role", () => {
    expect(upsertAdminSchema.safeParse({ email: "a@b.com", role: "moderator" }).success).toBe(true);
    expect(upsertAdminSchema.safeParse({ email: "nope", role: "moderator" }).success).toBe(false);
    expect(upsertAdminSchema.safeParse({ email: "a@b.com", role: "wizard" }).success).toBe(false);
  });

  it("config toggle only accepts known keys + boolean strings", () => {
    expect(setConfigSchema.safeParse({ key: "maintenance_mode", value: "true" }).success).toBe(true);
    expect(setConfigSchema.safeParse({ key: "maintenance_mode", value: "yes" }).success).toBe(false);
    expect(setConfigSchema.safeParse({ key: "unknown_key", value: "true" }).success).toBe(false);
  });
});
