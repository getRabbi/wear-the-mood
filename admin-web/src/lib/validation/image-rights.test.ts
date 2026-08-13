import { describe, expect, it } from "vitest";

import { can, ROLES, type Role } from "@/lib/auth/permissions";
import {
  merchantImageRightsSchema,
  productImageRightsSchema,
} from "@/lib/validation/catalog";

/**
 * The console half of the AI image-rights gate.
 *
 * Every rule here is also enforced in SQL (migration 0067) — these are the
 * first of three checks, not the only one. What they pin is the part a
 * database cannot: that the acknowledgement is required BEFORE a request is
 * ever sent, and that no role short of admin can send one at all.
 */

const UUID = "11111111-2222-3333-4444-555555555555";

describe("merchant image-rights validation", () => {
  it("accepts the three canonical values and nothing else", () => {
    for (const rights of ["unknown", "restricted"]) {
      expect(
        merchantImageRightsSchema.safeParse({ merchantId: UUID, rights }).success
      ).toBe(true);
    }
    for (const invented of ["approved", "granted", "yes", "LICENSED", ""]) {
      expect(
        merchantImageRightsSchema.safeParse({ merchantId: UUID, rights: invented }).success
      ).toBe(false);
    }
  });

  it("refuses to license without the acknowledgement", () => {
    // The one mutation in the console that asserts a permission somebody has to
    // have actually obtained. A form is not a gate, so this is checked in the
    // action too — not only in the dialog that renders the checkbox.
    const result = merchantImageRightsSchema.safeParse({
      merchantId: UUID,
      rights: "licensed",
      acknowledged: "false",
    });
    expect(result.success).toBe(false);
    expect(result.success === false && result.error.issues[0].message).toMatch(/Confirm/);
  });

  it("licenses when the acknowledgement is present", () => {
    expect(
      merchantImageRightsSchema.safeParse({
        merchantId: UUID,
        rights: "licensed",
        acknowledged: "true",
      }).success
    ).toBe(true);
  });

  it("does not demand an acknowledgement to WITHDRAW rights", () => {
    // Rollback must never be harder than the thing it undoes.
    for (const rights of ["restricted", "unknown"]) {
      expect(
        merchantImageRightsSchema.safeParse({
          merchantId: UUID,
          rights,
          acknowledged: "false",
        }).success
      ).toBe(true);
    }
  });

  it("rejects a merchant id that is not a uuid", () => {
    expect(
      merchantImageRightsSchema.safeParse({ merchantId: "aliexpress-pl", rights: "unknown" })
        .success
    ).toBe(false);
  });
});

describe("product image-rights override validation", () => {
  it("accepts the three values plus empty, which means inherit", () => {
    for (const rights of ["unknown", "licensed", "restricted", ""]) {
      expect(
        productImageRightsSchema.safeParse({ productId: UUID, rights }).success
      ).toBe(true);
    }
  });

  it("refuses anything outside the enum", () => {
    for (const invented of ["inherit", "default", "null", "approved"]) {
      expect(
        productImageRightsSchema.safeParse({ productId: UUID, rights: invented }).success
      ).toBe(false);
    }
  });
});

describe("who may change image rights", () => {
  it("is owner and admin only", () => {
    const allowed: Role[] = ["owner", "admin"];
    for (const role of ROLES) {
      expect(can(role, "manage_image_rights")).toBe(allowed.includes(role));
    }
  });

  it("is narrower than ordinary product merchandising", () => {
    // A content manager curates the catalog — titles, categories, publishing,
    // even the preferred try-on image. Asserting that somebody else's
    // photographs may be sent to a generative model is a different decision.
    expect(can("content_manager", "manage_products")).toBe(true);
    expect(can("content_manager", "manage_image_rights")).toBe(false);
  });

  it("is not granted by being able to read the catalog", () => {
    for (const role of ["moderator", "support"] as Role[]) {
      expect(can(role, "view_catalog")).toBe(true);
      expect(can(role, "manage_image_rights")).toBe(false);
    }
  });
});
