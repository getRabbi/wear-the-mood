import { describe, expect, it } from "vitest";

import { createSeedAccountSchema, createSeedPostSchema } from "@/lib/validation/seed";

const UUID = "11111111-1111-1111-1111-111111111111";

describe("seed schemas", () => {
  it("accepts a valid seed account", () => {
    const r = createSeedAccountSchema.safeParse({
      displayName: "WTM Studio",
      username: "wtm_studio",
      bio: "",
      seedType: "studio",
      publicLabel: "WTM Studio",
    });
    expect(r.success).toBe(true);
  });

  it("rejects bad usernames and seed types", () => {
    expect(
      createSeedAccountSchema.safeParse({
        displayName: "X",
        username: "Bad Name!",
        seedType: "studio",
        publicLabel: "L",
      }).success
    ).toBe(false);
    expect(
      createSeedAccountSchema.safeParse({
        displayName: "X",
        username: "ok_name",
        seedType: "spaceship",
        publicLabel: "L",
      }).success
    ).toBe(false);
  });

  it("seed post needs a uuid author + valid image url", () => {
    expect(
      createSeedPostSchema.safeParse({ seedUserId: UUID, imageUrl: "https://x/y.jpg" }).success
    ).toBe(true);
    expect(createSeedPostSchema.safeParse({ seedUserId: UUID, imageUrl: "not-a-url" }).success).toBe(
      false
    );
    expect(
      createSeedPostSchema.safeParse({ seedUserId: "nope", imageUrl: "https://x/y.jpg" }).success
    ).toBe(false);
  });
});
