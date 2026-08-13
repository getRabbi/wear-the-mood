import { describe, expect, it } from "vitest";

import { can, ROLES, type Role } from "@/lib/auth/permissions";
import {
  bulkProductTryOnSchema,
  merchantImageRightsSchema,
  merchantTryOnModeSchema,
  productImageRightsSchema,
  productTryOnOverrideSchema,
} from "@/lib/validation/catalog";

/**
 * The console half of try-on COVERAGE (migration 0068).
 *
 * Every rule here is enforced again in SQL — these are the first of three
 * checks. What they pin is the part a database cannot: that coverage and rights
 * never travel in the same request, that widening carries an acknowledgement
 * while narrowing does not, and that bulk enabling is bounded.
 */

const UUID = "11111111-2222-3333-4444-555555555555";
const UUID2 = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

describe("merchant try-on coverage validation", () => {
  it("accepts exactly the three modes", () => {
    for (const mode of ["off", "selected"]) {
      expect(merchantTryOnModeSchema.safeParse({ merchantId: UUID, mode }).success).toBe(true);
    }
    for (const invented of ["all_products", "auto", "on", "partial", ""]) {
      expect(
        merchantTryOnModeSchema.safeParse({ merchantId: UUID, mode: invented }).success
      ).toBe(false);
    }
  });

  it("carries the acknowledgement as a plain field, decided server-side", () => {
    // The waiver for an already-licensed merchant depends on STORED rights, so
    // the schema cannot decide it — a browser that simply omitted the tick would
    // otherwise be granting itself the waiver. Both shapes parse; the Server
    // Action is what refuses.
    for (const acknowledged of ["true", "false"]) {
      expect(
        merchantTryOnModeSchema.safeParse({ merchantId: UUID, mode: "all", acknowledged }).success
      ).toBe(true);
    }
    expect(
      merchantTryOnModeSchema.safeParse({ merchantId: UUID, mode: "all", acknowledged: "yes" })
        .success
    ).toBe(false);
  });

  it("defaults the acknowledgement to false rather than to granted", () => {
    const parsed = merchantTryOnModeSchema.safeParse({ merchantId: UUID, mode: "all" });
    expect(parsed.success && parsed.data.acknowledged).toBe("false");
  });

  it("never blocks switching a merchant OFF", () => {
    // This is the emergency shutdown. Anything standing between an operator and
    // it is a delay in an outage.
    expect(
      merchantTryOnModeSchema.safeParse({ merchantId: UUID, mode: "off", acknowledged: "false" })
        .success
    ).toBe(true);
    expect(
      merchantTryOnModeSchema.safeParse({
        merchantId: UUID,
        mode: "selected",
        acknowledged: "false",
      }).success
    ).toBe(true);
  });

  it("carries no rights field at all", () => {
    // The independence claim, at the wire. A coverage request that could smuggle
    // a rights value would make "the operational toggle never overrides the
    // rights gate" a matter of discipline rather than of shape.
    const parsed = merchantTryOnModeSchema.safeParse({
      merchantId: UUID,
      mode: "all",
      acknowledged: "true",
      rights: "licensed",
      image_rights_default: "licensed",
    });
    expect(parsed.success).toBe(true);
    expect(parsed.success && Object.keys(parsed.data)).not.toContain("rights");
    expect(parsed.success && Object.keys(parsed.data)).not.toContain("image_rights_default");
  });
});

describe("product try-on override validation", () => {
  it("accepts on, off, and empty meaning inherit", () => {
    for (const override of ["on", "off", ""]) {
      expect(productTryOnOverrideSchema.safeParse({ productId: UUID, override }).success).toBe(
        true
      );
    }
  });

  it("refuses anything else, including a rights word", () => {
    for (const invented of ["inherit", "true", "enabled", "licensed", "yes"]) {
      expect(
        productTryOnOverrideSchema.safeParse({ productId: UUID, override: invented }).success
      ).toBe(false);
    }
  });
});

describe("bulk try-on validation", () => {
  it("requires at least one product and caps the selection", () => {
    expect(bulkProductTryOnSchema.safeParse({ productIds: [], override: "on" }).success).toBe(
      false
    );
    expect(
      bulkProductTryOnSchema.safeParse({ productIds: [UUID, UUID2], override: "on" }).success
    ).toBe(true);
    const tooMany = Array.from({ length: 501 }, () => UUID);
    expect(bulkProductTryOnSchema.safeParse({ productIds: tooMany, override: "on" }).success).toBe(
      false
    );
  });

  it("accepts clearing back to inherit", () => {
    expect(bulkProductTryOnSchema.safeParse({ productIds: [UUID], override: "" }).success).toBe(
      true
    );
  });

  it("rejects a non-uuid in the selection rather than dropping it", () => {
    // Silently discarding one id would report "3 updated" for a selection of
    // four, which is how an operator comes to believe something is live.
    expect(
      bulkProductTryOnSchema.safeParse({ productIds: [UUID, "product-42"], override: "on" }).success
    ).toBe(false);
  });

  it("has no rights field", () => {
    const parsed = bulkProductTryOnSchema.safeParse({
      productIds: [UUID],
      override: "on",
      rights: "licensed",
    });
    expect(parsed.success).toBe(true);
    expect(parsed.success && Object.keys(parsed.data)).not.toContain("rights");
  });
});

describe("rights evidence", () => {
  it("accepts the closed basis vocabulary and rejects invention", () => {
    for (const basis of [
      "merchant_permission",
      "product_permission",
      "programme_terms",
      "network_permission",
      "other",
      "",
    ]) {
      expect(
        merchantImageRightsSchema.safeParse({
          merchantId: UUID,
          rights: "licensed",
          acknowledged: "true",
          basis,
        }).success
      ).toBe(true);
    }
    expect(
      merchantImageRightsSchema.safeParse({
        merchantId: UUID,
        rights: "licensed",
        acknowledged: "true",
        basis: "we-asked-nicely",
      }).success
    ).toBe(false);
  });

  it("is optional — it is evidence, not a gate", () => {
    expect(
      merchantImageRightsSchema.safeParse({
        merchantId: UUID,
        rights: "licensed",
        acknowledged: "true",
      }).success
    ).toBe(true);
    expect(productImageRightsSchema.safeParse({ productId: UUID, rights: "licensed" }).success).toBe(
      true
    );
  });

  it("bounds the free-text reference", () => {
    expect(
      productImageRightsSchema.safeParse({
        productId: UUID,
        rights: "licensed",
        reference: "x".repeat(501),
      }).success
    ).toBe(false);
  });
});

describe("who may change try-on coverage", () => {
  it("is owner and admin", () => {
    const allowed: Role[] = ["owner", "admin"];
    for (const role of ROLES) {
      expect(can(role, "manage_tryon_coverage")).toBe(allowed.includes(role));
    }
  });

  it("is a separate capability from asserting rights", () => {
    // Same holders today, deliberately different permissions: they answer
    // different questions, and the day one of them needs to move the other must
    // not move with it.
    expect(can("content_manager", "manage_tryon_coverage")).toBe(false);
    expect(can("content_manager", "manage_products")).toBe(true);
  });

  it("is not granted by being able to read the catalog", () => {
    for (const role of ["moderator", "support"] as Role[]) {
      expect(can(role, "view_catalog")).toBe(true);
      expect(can(role, "manage_tryon_coverage")).toBe(false);
    }
  });
});
