import { describe, expect, it } from "vitest";

import { can, ROLES, type Role } from "@/lib/auth/permissions";
import {
  merchantFeedStateSchema,
  networkDiscoverySchema,
  newsItemUpdateSchema,
  newsSourceUpsertSchema,
  productTryOnImageSchema,
} from "@/lib/validation/catalog";

const UUID = "11111111-2222-3333-4444-555555555555";

describe("try-on image validation", () => {
  it("accepts an absolute http(s) URL", () => {
    for (const url of ["https://cdn.test/a.png", "http://cdn.test/a.png"]) {
      expect(
        productTryOnImageSchema.safeParse({ productId: UUID, imageUrl: url }).success
      ).toBe(true);
    }
  });

  it("accepts empty, which clears the override", () => {
    expect(productTryOnImageSchema.safeParse({ productId: UUID, imageUrl: "" }).success).toBe(true);
  });

  it.each([
    "not-a-url",
    "/relative.png",
    "data:image/png;base64,iVBOR",
    "file:///etc/passwd",
    "javascript:alert(1)",
    "https://nohost",
  ])("refuses %s — this URL is handed to a paid render", (url) => {
    expect(productTryOnImageSchema.safeParse({ productId: UUID, imageUrl: url }).success).toBe(
      false
    );
  });
});

describe("news source validation", () => {
  const base = {
    slug: "hypebeast",
    name: "Hypebeast",
    feedUrl: "https://hypebeast.com/feed",
  };

  it("accepts a well-formed https feed", () => {
    expect(newsSourceUpsertSchema.safeParse(base).success).toBe(true);
  });

  it("refuses plain http — the ingester fetches this server-side", () => {
    expect(
      newsSourceUpsertSchema.safeParse({ ...base, feedUrl: "http://hypebeast.com/feed" }).success
    ).toBe(false);
  });

  it.each(["Bad Slug", "UPPER", "with_underscore", "a"])("refuses slug %s", (slug) => {
    expect(newsSourceUpsertSchema.safeParse({ ...base, slug }).success).toBe(false);
  });

  it("defaults to untrusted, so a new source cannot publish itself", () => {
    const parsed = newsSourceUpsertSchema.parse(base);
    expect(parsed.autoPublish).toBe("false");
  });
});

describe("news item editing", () => {
  it("refuses a summary long enough to be the article", () => {
    const parsed = newsItemUpdateSchema.safeParse({
      itemId: UUID,
      title: "A headline",
      summary: "x".repeat(1201),
    });
    expect(parsed.success).toBe(false);
  });

  it("accepts a real summary", () => {
    expect(
      newsItemUpdateSchema.safeParse({
        itemId: UUID,
        title: "A headline",
        summary: "Two sentences about the story.",
      }).success
    ).toBe(true);
  });
});

describe("catalog + newsroom permissions", () => {
  it("owner can do everything", () => {
    for (const p of [
      "view_catalog",
      "manage_products",
      "manage_merchants",
      "run_product_sync",
      "view_newsroom",
      "manage_news_items",
      "manage_news_sources",
    ] as const) {
      expect(can("owner", p)).toBe(true);
    }
  });

  it("content_manager merchandises but cannot approve a merchant or start a sync", () => {
    // Approving a merchant decides what gets imported and which affiliate
    // account earns; a sync spends someone else's rate limit.
    expect(can("content_manager", "manage_products")).toBe(true);
    expect(can("content_manager", "manage_merchants")).toBe(false);
    expect(can("content_manager", "run_product_sync")).toBe(false);
  });

  it("content_manager edits news items but cannot trust a source", () => {
    expect(can("content_manager", "manage_news_items")).toBe(true);
    expect(can("content_manager", "manage_news_sources")).toBe(false);
  });

  it("support and moderator can look but not touch the catalog", () => {
    for (const role of ["support", "moderator"] as const) {
      expect(can(role, "view_catalog")).toBe(true);
      expect(can(role, "manage_products")).toBe(false);
      expect(can(role, "manage_merchants")).toBe(false);
    }
  });

  it("only owner and admin can mutate merchants", () => {
    const allowed = ROLES.filter((r: Role) => can(r, "manage_merchants"));
    expect([...allowed].sort()).toEqual(["admin", "owner"]);
  });

  it("every new permission is deniable — none is granted to all roles by accident", () => {
    for (const p of ["manage_products", "manage_merchants", "manage_news_sources"] as const) {
      const denied = ROLES.filter((r: Role) => !can(r, p));
      expect(denied.length).toBeGreaterThan(0);
    }
  });
});

describe("affiliate network input", () => {
  it("accepts a feed row id and an on/off decision", () => {
    for (const enabled of ["true", "false"]) {
      expect(merchantFeedStateSchema.safeParse({ feedId: UUID, enabled }).success).toBe(true);
    }
  });

  it("refuses anything that is not one of our own feed rows", () => {
    // Notably a NETWORK feed number: the console addresses our own row, never
    // the network's id, so a typed feed number is not a thing it can send.
    for (const feedId of ["90001", "", "../../etc", UUID + "x"]) {
      expect(merchantFeedStateSchema.safeParse({ feedId, enabled: "true" }).success).toBe(false);
    }
  });

  it("has no field for a URL, a credential or a network feed number", () => {
    // The shape IS the security boundary: an admin cannot point the importer at
    // an arbitrary endpoint, because there is nowhere to put one. Everything the
    // connector needs it discovered for itself.
    const parsed = merchantFeedStateSchema.parse({ feedId: UUID, enabled: "true", reason: "x" });
    expect(Object.keys(parsed).sort()).toEqual(["enabled", "feedId", "reason"]);
    const extra = merchantFeedStateSchema.parse({
      feedId: UUID,
      enabled: "true",
      feedUrl: "https://productdata.awin.com/datafeed/download/apikey/leaked/fid/1/",
      apiKey: "leaked",
    } as Record<string, unknown>);
    expect(JSON.stringify(extra)).not.toContain("leaked");
  });

  it("only knows networks this build has a connector for", () => {
    expect(networkDiscoverySchema.safeParse({ network: "awin" }).success).toBe(true);
    expect(networkDiscoverySchema.parse({}).network).toBe("awin");
    for (const network of ["aliexpress", "cj", "AWIN", ""]) {
      expect(networkDiscoverySchema.safeParse({ network }).success).toBe(false);
    }
  });
});
