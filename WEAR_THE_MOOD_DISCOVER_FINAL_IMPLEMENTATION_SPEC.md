# Wear The Mood — Discover Redesign & Shopping Experience
## Claude Code Implementation Specification

> **Version:** 2.0 — fully re-audited final specification  
> **Status:** Final product and engineering direction  
> **Primary goal:** Replace the currently empty/low-activity Community experience with a premium, personalized Discover experience that increases daily retention and creates an affiliate-shopping path without breaking any existing production feature.  
> **Platform:** Flutter mobile app, existing Supabase/Firebase/RevenueCat/AI try-on architecture.  
> **Important:** This is a production application. Do not perform a large rewrite. Work additively, preserve compatibility, and verify every phase before continuing.  
> **Final design call:** The top Discover hero is a modern portrait Story-card rail inspired by the browsing rhythm of Facebook/Instagram Stories, but it is a curated Wear The Mood discovery system—not a clone and not public user posting.

---

# 1. Executive Product Decision

The current `Social` tab must become `Discover`.

The public community feed, posting UI, and community discovery filters must be hidden for now, not deleted. Existing community data, backend tables, routes, profiles, follow relationships, reports, blocks, and internal code must remain compatible so the feature can return later as a shoppable `Looks` experience.

The new Discover experience will contain:

1. Personalized affiliate products
2. Try-before-you-buy
3. Closet-based product matching
4. Giveaways
5. Offers
6. Newsroom/editorial content
7. Saved products and recently viewed products
8. Daily refreshed discovery cards

The existing Giveaway feature is working and must remain behaviorally unchanged. Discover should surface it, not rebuild its domain logic. The existing **Create Giveaway** entry must remain reachable inside the Giveaway hub even while the public Community create-post action is hidden.

The final user loop is:

```text
Open app
→ Check today’s style cards
→ Browse personalized products
→ Save or try a product
→ Complete a look
→ Visit retailer
→ Return for fresh daily content
```

The app should feel active like a modern social product without requiring an active public community feed.

---

# 2. Non-Negotiable Safety Rules

Claude Code must obey all of the following:

1. **Do not delete the Community implementation.**
2. **Do not rewrite the Giveaway feature.**
3. **Do not change existing production database tables destructively.**
4. **Do not rename existing database columns or routes unless an alias preserves backward compatibility.**
5. **Do not break existing deep links, notifications, or Inbox flows.**
6. **Do not hard-code colors, typography, spacing, or gradients if equivalent design tokens already exist.**
7. **Do not replace the current app shell or central AI orb navigation.**
8. **Do not introduce a second state-management framework. Use the project’s existing approach.**
9. **Do not add a second networking layer if the project already has one.**
10. **Do not duplicate try-on business logic. Reuse the current try-on pipeline through a thin adapter.**
11. **Do not expose raw affiliate URLs directly in UI code.**
12. **Do not show fake stock, fake popularity, fake votes, or fake countdowns.**
13. **Do not remove old Home modules until the new Discover screen is stable behind a feature flag.**
14. **Do not continue implementation if the baseline test suite is already failing without first documenting the failures.**
15. **Every database migration must be additive and reversible.**
16. **Every new screen must have loading, empty, offline, and error states.**
17. **The app must still run when the shopping backend is unavailable.**
18. **Any failed AI generation must preserve existing refund behavior.**
19. **No direct production rollout. Use feature flags and staged enablement.**
20. **Run formatting, analysis, tests, and build checks before considering the task complete.**
21. **Do not add a new image host, analytics stack, feature-flag provider, or backend service when the project already has an equivalent. Reuse Cloudflare R2/CDN and existing infrastructure.**
22. **Do not change authentication gating or guest access behavior unless the audit proves a change is required and it is separately approved.**
23. **Do not create open redirects. Retailer domains and redirect destinations must be validated and allow-listed server-side.**
24. **Do not remove the existing Giveaway creation entry while hiding the Community post composer.**
25. **Do not let server-driven unknown feed item types crash the client; ignore them safely and log them.**

---

# 3. Required Pre-Implementation Audit

Before changing code, inspect the repository and write a short implementation audit in the terminal or a temporary internal note.

Identify:

- Existing app shell and bottom navigation
- Current `Social` tab route and widget
- Home screen modules
- Current Community routes and state
- Existing Giveaway routes, services, models, repositories, notifications, and chat flow
- Existing Offers and Newsroom implementations
- Existing product-like models, catalog code, or merchant code
- Existing Saved/Favorites architecture
- Existing Try-On entry points
- Current feature flag system
- Existing Supabase tables and migrations
- Existing analytics wrapper
- Existing notification/deep-link routing
- Current design tokens and shared card components
- Current image/CDN/cache utilities
- Current dependency injection and state-management style
- Existing widget, integration, and backend tests
- Existing auth gate, guest mode, and signed-out behavior
- Existing localization, currency formatting, and country resolution
- Existing Create Giveaway entry point and permission checks
- Existing Cloudflare R2/CDN asset path and image transformation utilities
- Existing crash/error monitoring and structured logging
- Existing product or editorial content ownership/licensing metadata

Record baseline commands and results:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Also run any backend test command already used by the project.

If the repository has pre-existing failures, list them clearly and do not misrepresent them as caused by this work.

---

# 4. Final Navigation Architecture

Bottom navigation must become:

```text
HOME · DISCOVER · AI ORB · INBOX · PROFILE
```

## Requirements

- Rename visible label `Social` to `Discover`.
- Use a compass or sparkle-compass icon.
- Keep the existing tab index stable where possible.
- Preserve the old Social route as a compatibility alias.
- Any old route or notification that points to Community should:
  - Open a safe read-only destination if the content still exists, or
  - Redirect to Discover with a non-blocking message.
- Do not show a broken or blank screen.
- Keep the central AI orb behavior unchanged.
- Keep Inbox unchanged because Giveaway chat and future merchant messaging depend on it.
- A subtle non-numeric dot may appear on the Discover navigation item only when genuinely fresh unseen Story content or a relevant active Giveaway/Offer exists. Do not show noisy counts; clear/update the dot from real seen state.

Recommended route strategy:

```text
/social       -> compatibility alias
/discover     -> new root
/community/*  -> hidden or read-only depending on feature flags
```

---

# 5. Final Discover Screen Concept

The previous single large hero card and three separate shortcut tiles must be replaced with a modern horizontal **Discover Stories rail**, inspired by the visual rhythm of Facebook/Instagram story cards.

This is not a public user-posting feature. It is a curated and personalized discovery module.

The Story rail becomes the top hero system and divides major experiences into clean, visual cards without clutter.

## Final first-screen hierarchy

```text
Discover                         Saved   Search
Picked for your Confident mood

[ Today’s Edit ] [ Closet Match ] [ New Drops ] [ Giveaway ] ...

Picked for You                                  Filter
[ Product ] [ Product ]
[ Product ] [ Product ]

[ Contextual full-width module ]

[ More products... ]
```

There is:

- No separate giant hero banner
- No permanent six-tab chip row
- No duplicate mood slider
- No large `Giveaways / Offers / Newsroom` shortcut row
- No community create button
- No `For You / Following / New / Near You` filters

The Story rail replaces the hero and shortcut area.

If no current-day mood exists, the subtitle must gracefully fall back to `Picked for you` rather than showing a stale mood. The Discover screen supports pull-to-refresh, but the feed must remain stable while the user is scrolling and must not visibly reorder itself mid-session.

---

# 6. Discover Stories Rail — Final UI Specification

## 6.1 Card inventory

The rail may contain up to six primary cards:

1. **Today’s Edit**
2. **Closet Match**
3. **New for You**
4. **Giveaways**
5. **Offers**
6. **Newsroom**

The first three are personalized. The last three are content destinations.

Dynamic rules:

- `Today’s Edit` is always first when content exists.
- `Closet Match` is shown only when the user has useful closet data.
- `New for You` is shown when fresh personalized products exist.
- `Giveaways` is shown only when there is an active or relevant Giveaway.
- `Offers` is shown only when there is a valid active offer.
- `Newsroom` is shown when there is a new or relevant story.
- Do not render empty placeholder cards.
- Maximum six cards.
- Minimum two cards before showing the rail.
- If fewer than two cards are available, use a compact fallback card instead of an awkward rail.

## 6.2 Dimensions

Use responsive layout, not fixed device-specific pixels.

Recommended phone dimensions:

- Card width: approximately `128–138 logical pixels`
- Card height: approximately `188–204 logical pixels`
- Border radius: use the existing premium radius token, approximately `20–24`
- Horizontal gap: `10–12`
- Outer horizontal padding: same as the current Home screen
- Show approximately `2.4–2.8 cards` in the viewport
- Do not make the first card larger than the others; consistent geometry feels cleaner
- Use portrait cards, not circular avatar-style Story bubbles
- Use a consistent portrait crop with an admin-provided focal point where available so faces, garments, and product details are not cut off
- Reserve a bottom text-safe zone in every asset; do not rely on text baked into remote images

Tablet behavior:

- Increase card width proportionally
- Keep a similar vertical ratio
- Show more cards at once
- Do not stretch cards into oversized banners

## 6.3 Visual structure of each card

Each story card contains:

- Full-bleed editorial image or premium gradient artwork
- Dark bottom gradient overlay for legibility
- Small uppercase category label
- Title with maximum two lines
- Optional one-line supporting text
- Optional subtle `NEW`, `LIVE`, or `PRICE DROP` badge
- Optional seen/unseen border treatment
- Remote-configurable accessibility label and destination metadata

Example:

```text
TODAY’S EDIT

Confident
Evening

92% match
```

Giveaway example:

```text
GIVEAWAY

Win the
full look

Ends tomorrow
```

Offer example:

```text
PRICE DROP

Saved dress
20% off
```

## 6.4 Seen and unseen states

Use a subtle premium ring, not a loud social-media rainbow ring.

- Unseen/fresh: existing purple-pink gradient border or glow
- Seen: low-contrast neutral border
- Active/selected: slightly elevated surface
- Never use red unless there is real urgency
- Seen state must persist locally
- If backend support exists, sync it to the user account
- Local persistence must still work offline

Suggested state fields:

```text
story_id
updated_at
seen_at
content_version
```

A story becomes fresh again only when its `content_version` or meaningful content changes.

## 6.5 Interaction

- Tap card: open the Discover Story Viewer
- Long press: no action in the first release
- Horizontal swipe: scroll the rail
- Preserve rail scroll position when returning
- Tapping a card should mark it seen only after viewer content successfully loads
- Failed loads must not mark a story as seen
- A pull-to-refresh may update the rail, but newly inserted cards must not unexpectedly shift the card currently under the user’s finger
- Opening a story from a notification or deep link must select the exact story and preserve safe fallback behavior if it has expired

## 6.6 Accessibility

- Each card must expose a semantic label
- Screen reader text should include category, title, freshness, and action
- Do not rely only on ring color for unseen state
- Respect reduced-motion preferences
- Maintain readable text contrast over imagery

---

# 7. Discover Story Viewer

Create a reusable full-screen or near-full-screen viewer for Discover Stories.

It should feel modern but remain consistent with Wear The Mood’s luxury identity.

## 7.1 Viewer structure

```text
[ progress indicators ]
[ close ]

[ full-screen visual ]

Category
Title
Supporting text

[ Primary action ]
Secondary text action
```

## 7.2 Navigation

- Tap right side: next story
- Tap left side: previous story
- Swipe down or tap close: exit
- Back button: exit safely
- Swipe horizontally may be supported if it does not conflict with vertical page gestures
- Restore the user to the same Discover scroll position after closing

## 7.3 Story types and actions

### Today’s Edit

Primary:

```text
Try This Look
```

Secondary:

```text
View Items
```

### Closet Match

Primary:

```text
See Matches
```

Secondary:

```text
Open Closet
```

### New for You

Primary:

```text
Explore Picks
```

Secondary:

```text
Adjust Preferences
```

### Giveaway

Primary:

```text
View Giveaway
```

Secondary only on the details screen:

```text
Try the Look
```

Do not put multiple competing buttons on the story itself.

### Offer

Primary:

```text
View Offer
```

### Newsroom

Primary:

```text
Read Story
```

## 7.4 Auto-advance

Do not introduce aggressive auto-advance in the first production version.

Initial behavior:

- Manual navigation
- Progress indicators show position, not a countdown
- No autoplay video
- No background audio

A timed auto-advance can be considered later behind a feature flag after user testing.

---

# 8. Discover Main Feed

Below the Story rail:

```text
Picked for You                                  Filter
```

Then show a two-column personalized product grid on phones. Use a responsive grid on tablets (normally 3–5 columns depending on width) with a maximum content width so cards do not become excessively wide.

## 8.1 Product card content

Each product card contains only:

- Product image
- Merchant/brand
- Product title, maximum two lines
- Current price
- Optional original price
- One match reason or match percentage
- Heart/save icon
- Small `Try On` action or badge when compatible

Do not show on the main card:

- Full description
- All sizes
- All colors
- Delivery details
- Merchant ratings
- Multiple CTAs
- Long recommendation explanations
- More than one status badge

## 8.2 Product card actions

- Tap card: Product Details
- Tap heart: Save/unsave
- Tap `Try On`: direct shopping Try-On flow
- Optional overflow menu:
  - More like this
  - Not my style
  - Too expensive
  - Wrong size
  - Hide this product
  - Hide this brand
  - Report incorrect information

Do not place the overflow menu on every card unless it fits the existing design language. A long-press or details-page action is acceptable.

## 8.3 Feed rhythm

The feed must avoid looking like a generic marketplace.

Required module rhythm:

```text
4 product cards
→ 1 contextual full-width module
→ 4 product cards
→ 1 relevant Giveaway or Offer module
→ 4 product cards
→ 1 Newsroom/Style module
→ continue personalized products
```

Rule:

> No more than one full-width special module after each four product cards.

The feed composer may adjust content when a module is unavailable, but must not show empty sections. It must also deduplicate the same product/campaign across the Story rail and the first visible feed modules unless a deliberate campaign rule allows repetition.

---

# 9. Contextual Feed Modules

## 9.1 Complete Your Look

This is the main retention module.

Example:

```text
COMPLETE YOUR LOOK

Your black dress
+ Shoes
+ Bag
+ Earrings

[ See Matches ]
```

Main card contains:

- One user-owned closet item
- Two or three matching product previews
- One CTA

Details screen may contain:

- Replace item
- Try full look
- Save outfit
- Shop missing items
- Similar alternatives

## 9.2 Giveaway Card

Use the existing Giveaway domain.

Main feed card:

```text
GIVEAWAY

Win the complete evening look
Ends in 2 days

[ View Giveaway ]
```

Do not add a second CTA on the feed card.

The existing create/request/accept/reject/chat/status behavior must remain unchanged.

The Giveaway hub must preserve the existing **Create Giveaway** action in its own header or existing appropriate location. Hiding the Community `+` composer must never remove the user’s ability to create a Giveaway. Preserve all existing permission checks, image selection limits, validation, moderation, request/accept flows, and Inbox deep links.

## 9.3 Offer Card

Use elegant personalized copy:

```text
A dress you saved is now 20% off
```

Card fields:

- Product or collection visual
- Real discount
- Old and current price
- Real expiry if provided
- One CTA: `View Offer`

No flashing red sale UI.

## 9.4 Newsroom Card

Visual-first editorial card:

```text
STYLE NOTE

One black dress,
three evening looks

1 min read  →
```

The article may end with:

- Try This Look
- Shop Similar
- Save Inspiration

Do not show full article paragraphs in the feed.

---

# 10. Home Screen Changes

The Home screen remains the user’s personal control center.

Keep:

- Greeting
- Plan and credit balance
- Mood slider
- Try-On Studio
- Smart Closet
- AI Stylist
- Outfit Maker
- Today’s Look

Clarification: Home `Today’s Look` should remain a personal/closet utility. Discover `Today’s Edit` is a curated or shoppable discovery story. They must use distinct copy, content rules, and analytics so the experience does not feel duplicated.

Change:

- Remove the large duplicated `Giveaways / Offers / Newsroom` section after Discover is stable.
- Replace the current weak/random `Inspiration for You` content with a compact `Shop Your Mood` preview.
- The preview may show three personalized products or one mini carousel.
- Add `View all` to open Discover.
- Do not duplicate the full Discover Stories rail on Home.
- At most one highly relevant Giveaway or Offer teaser may appear on Home.

Rollout requirement:

- Keep the old Home modules behind a fallback flag until Discover passes regression testing.

---

# 11. Search, Filter, and Saved

## 11.1 Search

Search opens a dedicated screen.

Possible sections:

- Recent searches
- Suggested searches
- Categories
- Personalized suggestions
- Brands/stores
- Products
- Giveaways
- Offers
- Newsroom

Example queries:

```text
Black modest dress
Office outfit
Under ৳3000
Wedding guest
Summer tops
Complete my black jeans look
```

## 11.2 Filter

Open filters in a bottom sheet or dedicated overlay.

Filters:

- Category
- Price
- Size
- Color
- Occasion
- Brand/store
- Try-On Ready
- Country/availability
- Discount

Do not display a permanent row of filter chips on Discover.

Persist the active filter/search state while the user opens Product Details and returns. Provide a clear `Reset` action and do not silently carry old filters into a new explicit search.

When applied, show only a compact indicator:

```text
Filters · 2
```

## 11.3 Saved

Header heart opens a Saved screen.

Sections:

- Products
- Looks
- Offers
- Newsroom
- Giveaways

Handle states:

- Available
- Price dropped
- Low stock
- Out of stock
- Offer ended

Do not send the user to a broken affiliate product.

---

# 12. Product Details Screen

Required order:

1. Product gallery
2. Merchant/brand
3. Product title
4. Current/original price
5. Available sizes
6. Available colors
7. Try-On compatibility
8. Personal match reason
9. Product description
10. Delivery region
11. Affiliate disclosure
12. Similar products
13. Complete the Look
14. Sticky action bar
15. Price/availability last-updated information when the source can become stale
16. Variant-level availability for size/color combinations when supplied by the merchant

For Try-On-ready products:

```text
[ Try On ]    [ Shop at Store ]
```

For non-Try-On products:

```text
[ Save ]      [ Shop at Store ]
```

Affiliate disclosure:

```text
Wear The Mood may earn a commission from eligible purchases.
```

Use the existing compliant external purchase path for physical goods. Do not mix digital credit purchases with retailer checkout.

---

# 13. Shopping Try-On Integration

Do not duplicate the current Try-On engine.

Create a thin adapter that converts an affiliate product into the input expected by the current Try-On flow.

Required flow:

```text
Product
→ Try On
→ Select existing body photo/model
→ Generate preview
→ Result
→ Save / Compare / Shop
```

Result actions:

Primary:

```text
Shop at Store
```

Secondary:

- Save Look
- Try another color
- Find similar

Requirements:

- Preserve existing generation state handling
- Preserve current credit checks
- Preserve refunds on failed generation
- Preserve upload/crop/body-photo flow
- Preserve result history where compatible
- Keep source metadata so the result can return to the product
- Do not copy affiliate product images into permanent user storage beyond the existing cached/derived-image policy
- Reuse existing secure body-photo handling; do not create a second body-photo store or broader retention policy
- Track whether an affiliate click occurred after Try-On

Suggested metadata:

```text
source = affiliate_product
product_id
merchant_id
affiliate_click_token
feed_placement
campaign_id
```

---

# 14. Community Hidden, Not Deleted

Use feature flags.

Suggested flags:

```text
discover_enabled = true
shopping_enabled = true
discover_stories_enabled = true
community_enabled = false
community_posting_enabled = false
community_notifications_enabled = false
legacy_home_discover_enabled = false
```

Hidden:

- Community feed
- Following/New/Near You filters
- Share a Look
- Public create-post button
- Community discovery notifications

Retained:

- Database tables
- Existing posts/media
- Public profiles
- Follow relationships
- Report/block systems
- Backend endpoints
- Existing migrations
- Internal admin access
- Future compatibility

Future return:

Community returns inside Discover as `Looks`, not as a separate `Social` tab.

Possible future structure:

```text
Discover
├── Shop
└── Looks
```

Shoppable post flow:

```text
Creator posts a look
→ Products are tagged
→ User tries the look
→ Affiliate purchase
→ Optional creator reward
```

Do not build this future phase now.

---

# 15. Suggested Flutter Architecture

Use the project’s existing conventions. The following names are conceptual and must be adapted to the repository.

Suggested feature structure:

```text
features/
  discover/
    data/
      discover_repository.dart
      discover_remote_data_source.dart
      discover_local_data_source.dart
      models/
    domain/
      entities/
      repositories/
      usecases/
    presentation/
      discover_screen.dart
      discover_controller.dart
      widgets/
        discover_header.dart
        discover_story_rail.dart
        discover_story_card.dart
        discover_story_viewer.dart
        product_grid.dart
        product_card.dart
        complete_look_card.dart
        giveaway_feed_card.dart
        offer_feed_card.dart
        newsroom_feed_card.dart
      search/
      saved/
      product_details/
```

Do not create this exact folder tree if it conflicts with existing architecture.

Prefer:

- Shared typed models
- Repository abstraction
- Cached paginated feed
- Reusable story-card renderer
- Typed feed item variants
- Stable keys
- Existing dependency injection
- Existing state management

Avoid:

- A giant Discover widget
- `dynamic` JSON everywhere
- Multiple nested scroll views with conflicting physics
- Business logic inside UI widgets
- Direct Supabase calls from presentation widgets
- Direct affiliate URL construction in the client

---

# 16. Feed Item Type System

Use a typed model, sealed class, enum-backed union, or existing equivalent.

Conceptual types:

```text
DiscoverFeedItem
├── ProductItem
├── CompleteLookItem
├── GiveawayItem
├── OfferItem
├── NewsroomItem
└── FallbackEditorialItem
```

Story types:

```text
DiscoverStory
├── DailyEditStory
├── ClosetMatchStory
├── NewForYouStory
├── GiveawayStory
├── OfferStory
└── NewsroomStory
```

Every item should include:

```text
id
type
rank
tracking_token
created_at
updated_at
expires_at?
content_version
destination
```

Do not let frontend code infer type from title strings.

---

# 17. Backend and Supabase Architecture

First inspect existing schema. Reuse existing tables whenever possible.

Any new migration must be additive.

Potential new tables only if equivalents do not already exist:

## 17.1 merchants

```text
id
name
logo_url
affiliate_network
supported_countries
shipping_countries
approved
feed_health
created_at
updated_at
```

## 17.2 products

```text
id
merchant_id
external_id
title
description
category
subcategory
audience
colors
sizes
price
original_price
currency
image_urls
affiliate_url_reference
country_availability
stock_status
try_on_status
image_rights_status
source_terms_reference
image_focal_point
active
last_synced_at
created_at
updated_at
```

## 17.3 product_variants (only if the existing catalog cannot represent variants)

```text
id
product_id
external_variant_id
color
size
price
original_price
stock_status
available
updated_at
```

Do not create this table if variants are already modeled safely elsewhere.

## 17.4 discover_stories

```text
id
story_type
title
subtitle
image_url
destination_type
destination_id
audience_rules
country_rules
starts_at
ends_at
content_version
active
priority
created_at
updated_at
```

## 17.5 saved_products

```text
user_id
product_id
saved_at
price_alert_enabled
availability_alert_enabled
```

## 17.6 product_interactions

```text
id
user_id
session_id
product_id
event_type
feed_placement
story_id
tracking_token
metadata
created_at
```

## 17.7 affiliate_clicks

```text
id
user_id
product_id
merchant_id
tracking_token
feed_placement
try_on_completed
destination_url_reference
clicked_at
conversion_status
commission_value
commission_currency
updated_at
```

## 17.8 newsroom

Reuse existing Newsroom storage if available. Do not create duplicate content tables.

## 17.9 offers

Reuse current Offer architecture where possible.

## 17.10 giveaways

Do not migrate or rewrite the working Giveaway domain unless a confirmed bug requires a minimal fix.

## Security and RLS

- Users may read active products and stories allowed for their region.
- Users may write only their own saves/interactions.
- Affiliate click creation must be validated server-side when possible.
- Admin/editor writes require proper roles.
- Do not expose confidential affiliate configuration to the client.
- Follow existing RLS migration style.
- Add idempotency/uniqueness protection for save, interaction, and affiliate-click writes where retries could create duplicates.
- Validate all client-supplied destination identifiers; never accept an arbitrary outbound URL from the app.
- Apply reasonable rate limits or abuse controls to interaction, redirect, search, and Giveaway creation endpoints.

---

# 18. Affiliate Redirect Architecture

Do not hard-code final retailer links in UI widgets.

Required flow:

```text
User taps Shop
→ App requests/creates tracking click
→ Backend returns safe redirect/deep link
→ Retailer opens
→ Conversion is imported or received later
```

Track:

- User/session
- Product
- Merchant
- Feed placement
- Story source
- Campaign
- Try-On completed before click
- Country
- Click time
- Conversion status

Use platform-approved browser behavior already present in the app (for example system browser, Custom Tabs, or SFSafariViewController through the existing launcher). Do not build a custom embedded physical-goods checkout.

If backend redirect is temporarily unavailable:

- Show a clear non-blocking error
- Keep the user on Product Details
- Do not open an empty browser page
- Offer retry

---

# 19. Personalization Engine

First release should use deterministic rule-based ranking, not complex machine learning.

## 19.1 Hard filters

Exclude products that are:

- Inactive
- Out of stock
- Unavailable in the user’s country
- Missing a valid image
- Missing a valid merchant
- Unsupported for the selected audience/category
- Expired
- Incorrectly marked Try-On-ready
- Missing required pricing/currency data

## 19.2 Suggested ranking weights

These are starting points, not hard-coded constants. Put them in config if possible.

```text
Style preference         25%
Closet compatibility     20%
Current mood             15%
Color preference         10%
Budget fit               10%
Behavioral signals       10%
Freshness                 5%
Merchant quality          5%
```

## 19.3 Positive signals

- Product open
- Save
- Try On
- Add to look
- Shop click
- Repeated category views
- Repeated merchant views

## 19.4 Negative signals

- Not my style
- Too expensive
- Wrong size
- Wrong category
- Hide product
- Hide merchant
- Rapid repeated skip

## 19.5 Cold start

When the user has limited data:

1. Use onboarding style tags
2. Use current mood
3. Use region and currency
4. Use curated high-quality products
5. Ask lightweight preference questions over time
6. Never show a blank feed
7. Ask optional shopping preferences progressively: size, budget, favorite categories, avoided colors, modest preference, and shopping country
8. Do not block Discover behind a long new onboarding flow

---

# 20. Daily Retention System

The app must provide a fresh reason to return daily without fake gamification.

Primary daily hooks:

1. Today’s Edit story
2. New-for-you story
3. Closet Match story
4. Fresh personalized product ranking
5. Relevant Giveaways
6. Real Offers/price drops
7. Newsroom style notes
8. Saved-product alerts

Do not add all of the following in the first release:

- Coins
- Spin wheel
- Multiple streaks
- Fake urgency
- Forced daily tasks
- Excessive popups

Optional later:

- Gentle Style Journey
- Weekly wardrobe recap
- Capsule wardrobe progress
- Packing planner
- Occasion reminders

---

# 21. Notification and Deep-Link Requirements

Keep existing transactional notifications.

Discover-related notification types:

- Today’s Edit ready
- Saved product price drop
- New Closet Match
- Relevant Giveaway
- Offer for a saved/tried item
- New products from a preferred merchant
- Try-On result ready

Rules:

- At most one marketing/re-engagement push per day
- Transactional messages are separate
- Respect quiet hours
- Respect user preferences
- Suppress duplicates
- Do not send expired offers
- Deep-link to the exact story, product, Giveaway, Offer, or article
- If content is no longer available, show a graceful fallback

---

# 22. Analytics

Use the existing analytics wrapper. Do not call analytics SDKs directly from many widgets.

Required events:

```text
discover_open
discover_feed_loaded
discover_feed_failed
discover_story_impression
discover_story_open
discover_story_seen
discover_story_action
discover_story_close
product_impression
product_open
product_save
product_unsave
product_feedback
product_hide
try_on_start
try_on_complete
try_on_fail
affiliate_click
complete_look_open
giveaway_open
offer_open
newsroom_open
search_open
search_submit
filter_applied
saved_open
feed_load_more
discover_session_duration
```

Useful parameters:

```text
user_plan
story_type
story_id
product_id
merchant_id
feed_position
feed_placement
match_reason
country
currency
try_on_compatible
campaign_id
tracking_token
```

Core KPIs:

- Daily Discover users
- Next-day return rate
- Discover sessions per user
- Story open rate
- Story action rate
- Products viewed per session
- Save rate
- Try-On start/completion rate
- Try-On-to-shop-click rate
- Affiliate clicks
- Cost per shopping Try-On
- Giveaway engagement
- Offer conversion
- Newsroom completion
- Hide/not-interested rate

Do not log body-photo URLs, private image data, exact private closet-image URLs, or sensitive raw user content. Respect the app’s existing analytics consent and privacy settings.

---

# 23. Performance Requirements

Discover is visual-heavy and must remain smooth.

Required:

- Paginated feed
- Thumbnail-first loading
- Existing CDN utilities
- WebP/AVIF where already supported
- Fixed image aspect ratios
- Lazy loading
- Prefetch the next small batch
- Cache first feed page
- Cache seen state
- Restore scroll position
- Skeleton placeholders
- No blocking full-screen spinner
- Cancel stale requests
- Avoid rebuilding the entire grid on one save action
- Stable keys for feed items
- Image error fallback
- Story image prefetch for the next one or two cards
- Safe offline fallback
- Session-stable ordering: pagination must not reshuffle already rendered items
- Cursor-based pagination or the project’s existing stable equivalent; avoid offset drift and duplicate cards
- Configurable cache TTLs and stale-while-revalidate behavior

Do not load all product images at once.

---

# 24. Loading, Empty, Offline, and Error States

## Discover loading

Show:

- Header
- Story skeleton cards
- Product skeleton cards

Do not show a blank page.

## No personalization data

Show curated content with:

```text
Start with a few picks
```

Offer lightweight preference setup.

## No products in region

Show:

- Broader curated content
- Giveaways/Newsroom if available
- Region settings action
- No fake unavailable products

## Offline

Show cached first-page content with an offline indicator.

## Story load failure

- Keep rail usable
- Show retry in viewer
- Do not mark seen

## Broken affiliate link

- Keep Product Details open
- Show retry
- Show similar products if available

## Try-On failure

- Preserve existing credit refund behavior
- Keep product context
- Offer retry and image guidance

---

# 25. Design System Rules

Reuse existing theme tokens first.

## Colors

- Background: current deep navy/black
- Gold: editorial headings, selected state, premium accents
- Purple-pink gradient: AI and primary CTA
- White/grey: product and utility information
- Red: real errors or urgency only
- Green: confirmed success/availability only

## Typography

- Existing serif: major editorial titles
- Existing sans serif: UI and product content
- Story title: maximum two lines
- Product title: maximum two lines
- Avoid very small low-contrast text

## Cards

- Premium rounded corners
- Subtle low-contrast border
- Minimal shadow
- Glow only for fresh stories, AI actions, or selected states
- Do not put a glow on every card

## Spacing

- Consistent outer padding
- Clear section gaps
- Consistent product-grid gap
- Comfortable touch targets
- No cramped badge stacking

---

# 26. Anti-Clutter Rules

These are mandatory:

1. No permanent category tab row at the top
2. No giant hero banner above the Stories rail
3. No separate three-tile shortcut row
4. Maximum six Story cards
5. One visible primary CTA per story
6. One visible primary CTA per special feed module
7. One match reason per product card
8. No full product details on the feed card
9. No duplicate Discover modules on Home
10. No fake countdown or popularity
11. No multiple bright gradients on one card
12. No nested carousels inside every feed module
13. No more than one special module after four products
14. No full article text in the feed
15. No empty modules
16. No public posting button while Community is disabled
17. No circular Story avatar row; use the approved portrait-card rail
18. No noisy numeric badge on the Discover bottom-navigation item

---

# 27. Admin and Content Operations

Discover must be maintainable without code releases.

Use existing admin tools if available. Otherwise add the minimum necessary admin capability.

Required operations:

- Create/edit/deactivate products
- Import products through CSV/API where supported
- Manage merchants
- Mark Try-On compatibility
- Schedule stories
- Feature Today’s Edit
- Schedule Offers
- Publish Newsroom content
- Moderate Giveaways
- Set country targeting
- Configure story priority
- Disable broken products
- View feed health
- View click analytics
- Record source/license status and image focal points
- Preview Stories and cards at phone and tablet breakpoints before publishing
- Detect stale price/stock feeds and automatically suppress unsafe items

Do not expose admin controls in the consumer app.

---

# 28. Implementation Phases

## Phase 0 — Baseline and safety net

- Audit codebase
- Run baseline tests
- Document existing failures
- Identify flags, routes, and shared components
- Add tests around current navigation, Create Giveaway access, and Giveaway entry points before modifying them

Exit criteria:

- Baseline understood
- No unknown destructive dependency
- Rollback plan defined

## Phase 1 — Navigation and feature flags

- Add/confirm Discover flags
- Rename visible Social label to Discover
- Add route alias
- Hide Community feed and create button
- Preserve old routes safely
- Keep Giveaway and Inbox functional

Exit criteria:

- Navigation works
- Old links do not crash
- Community is hidden
- Existing Giveaway regression tests pass
- Create Giveaway remains reachable from the Giveaway hub

## Phase 2 — Discover shell and Stories rail

- Build Discover header
- Build Story model and renderer
- Build horizontal Story rail
- Build seen/unseen persistence
- Build Story Viewer
- Add loading/error states
- Add analytics events

Use initial adapters for existing Giveaway/Offer/Newsroom content.

Exit criteria:

- Rail renders responsively
- Viewer navigation works
- No scroll conflicts
- Seen state persists
- Accessibility semantics exist

## Phase 3 — Product catalog and feed

- Add/reuse Product and Merchant models
- Add repository and pagination
- Build product grid/card
- Add Search, Filter, Saved
- Add full-width feed modules
- Add cold-start fallback

Exit criteria:

- Feed loads and paginates
- Offline cache works
- Empty/error states work
- Product cards are stable and performant
- Product variants, country, currency, and stale-source behavior are verified

## Phase 4 — Product details and affiliate redirect

- Build Product Details
- Add safe tracking redirect
- Add affiliate disclosure
- Add availability checks
- Add similar products

Exit criteria:

- Retailer links are tracked safely
- Broken links fail gracefully
- No raw affiliate configuration is exposed

## Phase 5 — Shopping Try-On adapter

- Connect Product to current Try-On flow
- Preserve credit/refund behavior
- Add source metadata
- Add result-to-product return path
- Track Try-On-to-shop conversion

Exit criteria:

- Existing non-shopping Try-On still works
- Shopping Try-On works
- Failures refund correctly
- No duplicated generation logic

## Phase 6 — Home cleanup

Only after Discover is stable:

- Remove duplicated Home shortcut cards
- Replace weak Inspiration content with Shop Your Mood preview
- Keep fallback flag
- Verify Home scroll and performance

## Phase 7 — QA, staging, and gradual rollout

- Enable for internal testers
- Validate Android and iOS
- Monitor crashes and analytics
- Gradually increase user percentage
- Keep instant rollback flag

---

# 29. Testing Requirements

## Unit tests

- Story ordering
- Story eligibility
- Seen/fresh logic
- Product eligibility
- Ranking score
- Feed composition rhythm
- Affiliate tracking token creation
- Feature-flag behavior
- Route compatibility
- Empty-state fallback

## Widget tests

- Discover header
- Story rail
- Story card text limits
- Story viewer navigation
- Product card save state
- Loading skeleton
- Error state
- Complete Your Look card
- Giveaway card
- Offer card
- Newsroom card
- Search and Filter
- Product Details sticky actions

## Integration/regression tests

- Bottom navigation
- Old Social route redirect
- Giveaway open/create/request/accept/chat path
- Inbox still receives Giveaway conversations
- Community hidden state
- Product → Try On → result → retailer
- Save and restore
- Offline cached Discover
- Deep links
- Notification destinations
- Credit refund on failed generation

## Required commands

Adapt to repository tooling, but at minimum:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Run backend tests and build checks already used by the project.

Do not mark complete with analyzer errors, new test failures, or an unverified production route.

---

# 30. Rollout and Rollback

Use staged feature flags.

Recommended rollout:

```text
Internal team
→ selected testers
→ 5%
→ 20%
→ 50%
→ 100%
```

Monitor:

- Crash-free sessions
- Feed load failures
- Story viewer failures
- Affiliate redirect failures
- Try-On failures
- Giveaway regressions
- Session time
- Next-day return
- Save rate
- Retailer click rate

Rollback must be possible by setting:

```text
discover_enabled = false
legacy_home_discover_enabled = true
community_enabled = previous_safe_value
```

The application must remain usable without a new binary release.

---

# 31. Acceptance Criteria

The work is complete only when all of the following are true:

## Navigation

- `Social` displays as `Discover`
- Compass-style icon is used
- AI orb and all other tabs remain intact
- Old Social links do not crash

## Community

- Public Community feed is hidden
- Create-post action is hidden
- Community data/code is preserved
- Future reactivation remains possible

## Stories

- Modern horizontal story cards are present
- Cards are responsive
- Maximum six cards
- No empty cards
- Seen/unseen state works
- Story Viewer works
- Story CTAs deep-link correctly
- Story rail restores position

## Shopping

- Product feed is paginated
- Product cards are clean and consistent
- Save works
- Search and Filter work
- Product Details works
- Affiliate redirect is tracked
- Broken products fail gracefully

## Try-On

- Shopping product can enter the existing Try-On flow
- Existing Try-On behavior remains unchanged
- Failed requests preserve refund behavior
- Result can return to the product
- Try-On-to-shop analytics works

## Existing features

- Giveaway remains fully functional
- Create Giveaway remains accessible from the Giveaway hub
- Giveaway chat remains in Inbox
- Offers remain accessible
- Newsroom remains accessible
- Notifications and deep links do not break

## Quality

- No new analyzer errors
- No new test failures
- No overflow on supported phone and tablet sizes
- Responsive grid and Story rail are manually verified on a small phone, large phone, 7-inch tablet, 10-inch/iPad-class tablet, portrait, and landscape where supported
- Dark theme remains premium and readable
- Accessibility semantics exist
- First useful content appears without a blank screen
- Feature can be disabled remotely

---

# 32. Explicitly Out of Scope

Do not build now:

- Full resale marketplace
- Creator monetization
- Public Community relaunch
- Live shopping
- In-app physical-goods checkout
- Complex machine-learning recommendation
- Multiple gamification currencies
- Spin wheels
- Aggressive streak systems
- Random banner ads
- Autoplay story video
- Public user-created shopping stories
- Large rewrite of the app shell
- Replacement of current Try-On engine

---

# 33. Content Freshness, Feed Stability, and Deduplication

Daily retention depends on real freshness, not random reshuffling.

## 33.1 Daily boundary

- Determine “today” using the user’s resolved local timezone, not a fixed UTC reset.
- Store canonical server timestamps and derive local display safely.
- A Today’s Edit should normally change once per local day, when mood changes meaningfully, or when the previous item becomes unavailable.
- Do not regenerate expensive AI imagery merely because the app reopened.

## 33.2 Session stability

- Create or reuse a feed/session identifier.
- The already rendered feed must not reorder while the user scrolls.
- New content may appear after explicit pull-to-refresh, app restart, meaningful preference change, or a configured freshness boundary.
- When the user returns from Product Details or Try-On, restore exact scroll position and loaded pages.

## 33.3 Deduplication

- Do not show the same product twice in one feed page.
- Do not show the same Giveaway/Offer/Newsroom campaign in both a Story and the first special module unless explicitly configured.
- Avoid recently viewed or dismissed products in the first positions for a configurable period.
- A changed price, new color, or materially updated campaign may qualify as fresh content; a timestamp-only update does not.

## 33.4 Refresh behavior

- Pull-to-refresh refreshes Stories, feed eligibility, prices, and availability without discarding valid cached content first.
- Show a subtle “New picks available” affordance if new items arrive while the user is deep in the feed; do not jump the scroll position.
- If refresh fails, keep the last valid content visible and show a non-blocking status.

---

# 34. Localization, Region, Currency, and Availability

The first implementation may target current supported regions, but architecture must not hard-code one country or currency.

Requirements:

- Use existing locale and currency formatting utilities.
- Store monetary values as numeric amounts plus ISO currency codes; never concatenate currency symbols manually.
- Resolve user shopping country from existing account/preferences first; do not request precise location solely for shopping.
- Weather-based styling, if used later, must be optional and must not require precise background location.
- Merchant shipping eligibility must be checked before ranking.
- Search, filters, price ranges, and offer copy must respect currency and locale.
- All user-facing copy must be externalized for localization.
- Do not expose products that cannot be delivered to the selected shopping country.
- Changing country/currency should invalidate only the relevant catalog cache, not unrelated closet or Try-On data.

---

# 35. Product Content Rights, Quality, and Staleness

Only use product content received through an authorized affiliate feed, merchant agreement, approved API/CSV, or another documented licensed source.

Requirements:

- Record merchant/source and rights status.
- Do not scrape arbitrary retailer pages without contractual permission.
- Store original source identifiers and synchronization timestamps.
- Validate minimum image quality, aspect ratio, background, and Try-On suitability.
- Allow admin-controlled image focal points.
- Suppress products with missing rights status, invalid images, broken destinations, stale unsafe pricing, or stale stock beyond a configurable threshold.
- Price/stock sync failure must not silently display indefinite old claims.
- Never label a product “Try-On Ready” until compatibility checks pass.
- Product description and brand attribution must remain accurate to source.
- Sponsored content must be clearly labeled and must never masquerade as an organic personalized recommendation.

---

# 36. Privacy and User Control

Discover personalization must be useful and understandable.

Required user controls:

- View and update shopping preferences
- Change shopping country and currency
- Clear recent searches
- Clear recently viewed products
- Delete saved products
- Disable price/availability alerts
- Disable shopping-personalization signals where existing privacy architecture supports it
- See a short reason such as `Matches your closet`, `Based on your mood`, or `Within your budget`
- Report incorrect product information

Body-photo and closet safeguards:

- Reuse current secure storage and deletion behavior.
- Do not send private closet/body images to affiliate merchants.
- Do not include private image URLs in analytics or affiliate redirects.
- Do not broaden data retention because Discover was added.
- Do not use precise location when country/region selection is sufficient.

---

# 37. API and Server-Driven Data Contract

Adapt this contract to the project’s existing backend style; do not add REST endpoints if Supabase RPC/functions or the current service layer already provide the equivalent.

## 37.1 Discover bootstrap request

Conceptual input:

```text
user_id/auth context
country
currency
locale
timezone
current_mood_id?
feed_session_id?
story_content_versions?
```

Conceptual response:

```text
schema_version
server_time
feed_session_id
stories[]
feed_items[]
next_cursor?
cache_ttl_seconds
feature_flags
```

## 37.2 Feed pagination

Conceptual input:

```text
feed_session_id
cursor
active_filters
search_query?
```

Requirements:

- Stable cursor semantics
- No duplicate item IDs in a session
- Unknown item types ignored safely by older clients
- Expired content excluded server-side
- Ranking reason returned as a typed code, not arbitrary display text
- Server may return a display-safe localized reason when existing localization architecture supports it

## 37.3 Interaction writes

Interaction writes should be idempotent when retried.

Examples:

```text
save_product
unsave_product
mark_story_seen
product_impression
product_open
product_feedback
affiliate_click
```

Each write should support a client event ID or equivalent deduplication key where appropriate.

## 37.4 Version compatibility

- Include a response/schema version.
- New optional fields must not break older app versions.
- Unknown Story/feed types must be skipped, not rendered as blank cards.
- If minimum app version is required for a future type, exclude that type for older clients.

---

# 38. Security, Abuse Prevention, and Data Consistency

Required safeguards:

- Allow-list merchant domains and validate redirect destinations server-side.
- Reject `javascript:`, custom malicious schemes, malformed URLs, and arbitrary client-provided redirect URLs.
- Use signed or opaque redirect tokens where practical.
- Add uniqueness/idempotency for saves and click records.
- Rate-limit abusive search, click, interaction, and Giveaway creation behavior using existing backend controls.
- Validate product IDs, merchant IDs, campaign IDs, country, and active state on the server.
- Never trust client-provided price, discount, stock, commission, or entitlement values.
- Preserve existing RevenueCat/server entitlement checks for digital Try-On benefits.
- Use least-privilege RLS/service roles.
- Record admin/editor changes where existing audit infrastructure supports it.

---

# 39. Sponsored and Commercial Content Guardrails

Sponsored placements may be added later without redesigning the feed, but must remain controlled.

Rules:

- Clearly label `Sponsored`, `Partner`, or equivalent.
- Do not disguise paid ranking as an organic match reason.
- Keep sponsored density configurable and low; organic utility must remain dominant.
- Do not show the same sponsored campaign repeatedly in Stories and feed.
- Apply the same stock, rights, region, image-quality, and redirect validation as organic products.
- Track sponsored impressions/clicks separately.
- Never sell or expose identifiable body-photo or private closet data to merchants.

---

# 40. Observability and Operational Readiness

Use the project’s existing crash/error monitoring and logging stack.

Add monitoring for:

- Discover bootstrap latency and failure rate
- Story image/viewer failures
- Feed pagination duplicates and failures
- Product image failures
- Stale catalog suppression counts
- Affiliate redirect failures
- Merchant/domain validation failures
- Try-On failures and refund outcomes
- Giveaway regressions
- Notification deep-link failures
- Unknown feed/story type counts

Operational requirements:

- Attach correlation/request IDs where existing infrastructure supports them.
- Logs must not contain private body/closet URLs or affiliate secrets.
- Create a minimal rollout dashboard before broad enablement.
- Define alert thresholds for severe redirect, feed, Try-On, or Giveaway regressions.
- Document which feature flag disables each risky path.

---

# 41. Responsive Layout and Manual QA Matrix

## Phone

- Two-column product grid
- Approximately 2.4–2.8 Story cards visible
- Verify smallest supported phone width
- Verify largest phone/text scaling
- Preserve bottom-navigation and safe-area spacing

## Tablet/iPad

- 3–5 product columns based on width
- Use a maximum content width and centered layout where appropriate
- Show more Story cards without making them oversized
- Verify portrait and landscape
- Product Details may use a wider two-pane layout only if it matches existing responsive patterns; do not invent a separate tablet architecture unnecessarily

## Required manual QA devices/breakpoints

- Small Android phone
- Large Android phone
- Current iPhone-class device
- 7-inch Android tablet
- 10-inch Android tablet
- iPad-class portrait
- Tablet/iPad landscape where supported
- Large text/accessibility font scaling
- Reduced motion
- Slow network and offline return

Also verify:

- No clipped Story text
- No product-card overflow
- No keyboard overlap in Search/Filter
- No nested-scroll conflict
- Correct restoration after Story Viewer, Product Details, Try-On, and retailer return

---

# 42. Experimentation Guardrails

Do not delay the initial release for experimentation infrastructure if none exists, but keep major decisions configurable.

Candidates for later testing:

- Story card ordering after Today’s Edit
- Number of visible Story cards
- Product-card CTA wording
- Position of Complete Your Look
- Daily notification copy/timing
- Free shopping Try-On allowance

Rules:

- One material experiment per surface at a time where possible.
- Define success and guardrail metrics before enabling.
- Do not optimize only for session duration; include return rate, save quality, Try-On cost, redirect success, and user-hide rate.
- Experiments must honor the same accessibility, privacy, and sponsored-content rules.

---

# 43. Final Delivery Package Required from Claude Code

At the end, Claude Code must provide a final implementation report containing:

1. Architecture discovered and reused
2. Files changed
3. New files added
4. Database migrations and rollback notes
5. Feature flags and default values
6. Routes/deep links added or aliased
7. Existing Giveaway behavior verified, including Create Giveaway
8. Existing Offers and Newsroom behavior verified
9. Try-On integration and refund behavior verified
10. Analytics events added
11. Security and redirect validation added
12. Tests added and full results
13. Android/iOS build checks performed
14. Manual QA matrix completed or still outstanding
15. Known limitations
16. Exact rollout steps
17. Exact rollback steps
18. Screenshots or concise visual QA notes for key surfaces

Do not state that the feature is complete if any acceptance criterion remains unverified. Mark each item as `PASS`, `FAIL`, or `NOT VERIFIED`.

---

# 44. Final Visual Summary

## Discover first viewport

```text
┌──────────────────────────────────────┐
│ Discover                    ♡    ⌕   │
│ Picked for your Confident mood       │
│                                      │
│ ┌────────────┐ ┌────────────┐ ┌───── │
│ │ TODAY’S    │ │ CLOSET     │ │ NEW  │
│ │ EDIT       │ │ MATCH      │ │ FOR  │
│ │            │ │            │ │ YOU  │
│ │ Confident  │ │ Black      │ │ 18   │
│ │ Evening    │ │ Dress      │ │ picks│
│ └────────────┘ └────────────┘ └───── │
│                                      │
│ Picked for You                Filter │
│ ┌──────────────┐ ┌──────────────┐    │
│ │ Product      │ │ Product      │    │
│ │ Price        │ │ Price        │    │
│ │ Match  Try   │ │ Match  Try   │    │
│ └──────────────┘ └──────────────┘    │
└──────────────────────────────────────┘
```

## Bottom navigation

```text
HOME · DISCOVER · AI ORB · INBOX · PROFILE
```

---

# 45. Final Instruction to Claude Code

Implement this work in small, reviewable phases.

Before editing:

1. Audit the repository.
2. Identify the current architecture.
3. Record baseline tests.
4. Produce a short impact plan.
5. Confirm which existing models and services can be reused.

During implementation:

1. Prefer additive changes.
2. Preserve backward compatibility.
3. Reuse shared design and business logic.
4. Keep the working Giveaway domain untouched.
5. Keep every phase runnable and testable.
6. Commit or checkpoint after each stable phase.
7. Do not hide failures.
8. Do not remove fallback code until rollout is proven.

At completion, provide:

- Files changed
- Migrations added
- Feature flags added
- Routes added/aliased
- Tests added
- Commands executed
- Test/build results
- Known limitations
- Rollback instructions
- Screens that require manual QA

The final result must feel like a polished, modern fashion-discovery product—not a crowded marketplace and not an empty social feed.

Before writing production code, Claude Code must stop after the audit and present: repository findings, reuse plan, risky areas, proposed phases, expected migrations, and the exact baseline test results. Implementation begins only after that plan is internally consistent with this specification.
