# Privacy Policy — Wear The Mood

> **Internal note (stripped at build — never published).** This file is the
> single source of truth; run `python deploy/build_legal.py` after editing.
> A final lawyer review is still open (see LAUNCH_RUNBOOK.md). This policy must
> keep matching the Google Play **Data Safety** form, the Apple **App Privacy**
> questionnaire, and actual practice — inaccurate declarations get apps removed.

**Last updated:** August 14, 2026
**Controller:** Md Rabbi Hossain, operating as Wear The Mood
**Contact:** uprightseo24@gmail.com

Wear The Mood ("we", "us") lets you create an avatar, try clothes on virtually,
organize your wardrobe, get styling suggestions, and join a style community.
This policy explains what we collect, why, and your choices. **You must be 13+
to use Wear The Mood.**

## 1. Data we collect

| Category | Examples | Why |
|---|---|---|
| Account | email, display name, auth tokens | sign-in, account management |
| **Photos of you (sensitive)** | try-on/body photos and profile pictures you upload, body measurements you enter | create your avatar and render try-ons — see § 2 |
| Wardrobe | item photos, categories, cost, wear history | your digital closet + cost-per-wear |
| Try-on inputs/results | the photos you upload, generated images | produce the try-on |
| Community content | posts, comments, likes, follows, giveaway listings, reports | the community features |
| Messages | giveaway pickup chat between a listing owner and a requester | let members arrange a handover safely |
| Usage & analytics | in-app events, app version, device model, push token | reliability, product analytics, notifications |
| Diagnostics | crash reports, error logs, performance traces | find and fix bugs |
| Purchases | subscription and entitlement status (via RevenueCat) | manage entitlements |
| Coarse location | approximate latitude/longitude **only if you allow it** | weather for the stylist |

We do **not** sell your personal data.

## 2. AI Processing, User Photos, and Face Data

This section describes exactly what happens to a photo of you when you use an AI
feature. It is the section to read if you want to know who receives your image.

### 2.1 What we collect

Only images you choose and upload yourself: try-on/body photos, your profile
picture, and photos of your clothes. **These photos may show your face and
body.** We do not access your camera roll in the background and we do not capture
images without you selecting them.

### 2.2 Face data — what we do and do not do

**We do not create faceprints or biometric identifiers.** Specifically, Wear The
Mood does **not**:

- perform facial recognition, face matching, or face-based identification;
- create or store facial-geometry templates, faceprints, or face embeddings;
- build a biometric identity profile, or use your face to authenticate you;
- attempt to determine who you are from a photo.

Your photo is treated as an ordinary image file: it is stored, and it is passed
to the AI model that renders clothing onto it.

The one automated analysis we run is a **full-body check that happens entirely on
your device**, before any upload: we use on-device pose detection to confirm the
photo shows a whole body (so a cropped shot doesn't produce a poor result). It
detects body points such as shoulders, hips and ankles. It does not identify you,
it produces only a pass/fail and a quality score, and neither the landmarks nor
any derived template is stored or transmitted.

Because a photograph of your face and body can still be treated as **biometric
information** under laws such as the Illinois BIPA (US) and as **special-category
data** under the GDPR, we ask for your explicit consent before capture and again
before any third-party AI processing, and we apply the protections in this policy
to those images regardless of how they are classified.

### 2.3 Purpose

Your photos are used only to provide the feature you asked for: rendering a
garment onto your photo, keeping your saved results, and running the safety check
below. They are not used for advertising, profiling, or model training.

### 2.4 Who receives your photo, and why

When — and only when — you run an AI try-on using **your own photo**, that image
is sent to:

| Recipient | What they receive | Why | Where |
|---|---|---|---|
| **OpenAI, L.L.C.** | the image, for an automated safety check | required content moderation: we must screen inputs for sexual content, minors and graphic violence before rendering (see § Acceptable Use) | United States |
| **FASHN LTD ("FASHN.ai")** | the image, plus the garment image | performs the AI try-on render you requested | United States |

Nothing is sent to either provider until you have given the permission described
in § 2.6. If you decline, the request stops: no image is transmitted and no
credits are used.

Both providers act as our processors for this purpose. We do not authorise them
to use your images for their own purposes, and we do not sell or share your
photos for advertising.

**We do not use your photos to train AI models, and we do not grant our providers
the right to do so.** Both providers also commit to this in their own published
terms (checked August 12, 2026):

- **FASHN** — "FASHN will not use Customer Content to train, fine-tune, or
  otherwise improve FASHN or third-party AI models unless the Customer expressly
  opts in through a separately agreed service." We have not opted in. FASHN also
  states it will not use Customer Content for marketing or promotional purposes
  without express permission.
- **OpenAI** — "As of March 1, 2023, data sent to the OpenAI API is not used to
  train or improve OpenAI models (unless you explicitly opt in to share data with
  us)." We have not opted in. OpenAI's endpoint-specific data-controls table also
  lists the Moderations API (`/v1/moderations`) — the only OpenAI endpoint your
  photo reaches — as not used for training.

These are their terms, not ours, and they can change them; we re-check them when
we review this policy.

### 2.5 Features that do NOT send your photo anywhere

- **2D try-on preview** — runs entirely on your device. Your photo never leaves
  the phone.
- **Trying clothes on a Wear The Mood studio model** — the body used is our own
  catalog photograph, not you. No personal image is transmitted.
- **Background removal on clothing photos** — performed on your device, or by our
  own image service on our own infrastructure. It is not sent to a third-party AI
  provider.
- **AI Enhance and Catalog Model Shot** — these run on the photo of the *garment*
  you added to your closet (we ask you to photograph the item laid flat or on a
  hanger), and that image is sent to FASHN.ai to produce the result you asked for.

### 2.6 Your permission, and how to withdraw it

The first time you run an AI feature that would send a photo of you to a
third-party provider, we show you a disclosure naming what is sent, who receives
it and why, and ask you to allow it. Nothing is transmitted and nothing is
charged unless you tap **Allow & Continue**.

You can review that disclosure, or withdraw the permission at any time, at:

**Profile → Settings → Privacy → AI Photo Processing**

Withdrawing takes effect immediately for new requests: AI features that would use
your personal photo will ask again before sending anything. On-device 2D try-on
and studio-model try-on continue to work. Withdrawing does **not** delete photos
or results you have already saved — see § 7 and § 8 for deletion.

If we materially change which providers receive your photo, or why, we will ask
for your permission again rather than relying on the earlier answer.

## 3. How we use data

To provide and improve the features above, secure the service, prevent abuse and
moderate content (§ Acceptable Use), process subscriptions, and—where required—
comply with law. Legal bases (GDPR): **consent** (biometric data, location,
marketing), **contract** (providing the app), and **legitimate interests**
(security, analytics, fraud/abuse prevention).

## 4. Service providers

We share the minimum necessary with processors who help us run the app:

- **Supabase** — database, auth, storage
- **FASHN.ai (FASHN LTD)** — virtual try-on and AI image rendering. **Receives
  photos you choose, which may include your face and body** (see § 2.4)
- **OpenAI** — automated safety screening of images and text before they are
  rendered or published (§ 2.4, § 6); plus wardrobe/taste embeddings
- **Anthropic** — AI styling suggestions and text generation. Does **not**
  receive your photos
- **RevenueCat** — subscription management
- **Firebase Cloud Messaging** — push notifications
- **PostHog** — product analytics
- **Sentry** — crash/error reporting
- **Cloud hosting** — Heroku (Salesforce) — API hosting, United States; Microsoft Azure — background AI/image processing, Asia Pacific; Cloudflare — CDN, image storage and static site hosting

Each processes data under our instructions. Some may be outside your country;
we use appropriate safeguards for international transfers.

## 5. Affiliate links and commissions

Some products shown in Wear The Mood — in Discover, Shop Your Mood, shop-the-look
and closet-gap suggestions — are **affiliate links**. If you tap one and go on to
buy, **we may earn a commission from the retailer.**

- **It costs you nothing.** You pay the retailer's own price; a commission is
  paid by the retailer out of their margin, not added to your total.
- **We do not send the retailer your identity.** An affiliate link carries a
  fixed attribution tag that identifies *Wear The Mood* as the referrer. It does
  **not** contain your name, email, account ID, photos, or any per-user
  identifier.
- **Once you leave, the retailer's policy applies.** Opening the link hands you
  to the retailer's own site or app, which may set its own cookies and collect
  its own data. We do not control that, and their privacy policy — not this one
  — governs what happens there.
- **On our side we record the tap.** We log that a shop link was opened, and for
  which product, in our own product analytics (§ 4) so we can see which
  suggestions are useful. That record stays with us.
- **Paid placements are labelled.** Where a product or placement is sponsored,
  it is marked as such in the app.

We currently participate in the **AliExpress** affiliate programme. We will keep
this section current as programmes are added or removed.

## 6. Content moderation

To keep the community safe we screen try-on input images and user posts/comments
before they are rendered or published, and we act on reports (see the Acceptable
Use Policy). This screening is automated and performed by OpenAI on our behalf
(§ 2.4); it checks for sexual content, minors and graphic violence. It does not
identify anyone. We may store moderation decisions to enforce our policies.

## 7. Retention

Different things are kept for different lengths of time. We set these out
separately rather than giving one blanket figure, because one figure would be
wrong for most of them.

**a) Content in your account — kept until you remove it.**
Your try-on/body photos, wardrobe images, generated results and saved looks stay
in your account until you delete them individually or delete your account. They
are not auto-expired, because they are yours to keep and re-use — your body photo
gallery would otherwise empty itself between sessions. Delete a body photo in
**Profile → Body photo**, a result in **Saved Looks**, and everything at once with
**Settings → Delete Account**.

**b) Links used to move an image — minutes to about an hour.**
Your images live in private storage. To display one, or to let a provider read
one, we mint a **signed, expiring link** (currently about one hour). The link
stops working when it expires; the file itself is unaffected.

**c) At the AI providers.** Their published terms, checked August 12, 2026:

- **FASHN** — your photo is sent inside the request itself, Base64-encoded,
  rather than as a link FASHN fetches. FASHN's documentation states that full
  Base64 image data is used only to process and deliver the request, and that
  request history and stored prediction metadata keep a `<base64>` placeholder
  instead of the image itself. FASHN does not publish a retention period for
  submitted inputs, so we do not state one.
  Generated results are returned on FASHN's CDN, where **API outputs are
  scheduled for deletion after three days**. We download the finished image into
  our own private storage immediately, so your history never depends on that CDN
  copy.
- **OpenAI** — used only for the automated safety screening, which runs on
  OpenAI's **Moderations API** (`/v1/moderations`). OpenAI's current API
  data-controls documentation lists that endpoint as having **no abuse-monitoring
  retention and no application-state retention**, and as not used for model
  training. This describes the documented behaviour of that specific endpoint —
  it is not a special arrangement on our account, and it does not describe
  OpenAI's other endpoints, which do retain data for a period.

These periods are set by the providers, not by us, and they can change them; we
re-check when we review this policy. Nothing we hold depends on them.

**d) Operational logs — no image content.**
Our diagnostic logs record events, timings and error categories. They do not
contain your images, and we redact image links so a log entry can never be used
to open a photo.

**e) Account deletion.** When you delete your account we delete or anonymise your
personal data — including your stored photos and generated results — within 30
days, except where we must keep limited records for legal reasons.

## 8. Your rights

You can, in-app or by contacting us:

- **Export** your data — Settings → Privacy → Export my data
- **Delete** your account and everything in it — Settings → Delete Account
- **Delete individual items** — a body photo in Profile → Body photo, a result in
  Saved Looks, a garment in your closet
- **Withdraw permission for third-party AI processing of your photos** —
  Settings → Privacy → AI Photo Processing (§ 2.6). This stops future sharing; it
  does not delete content you have already saved
- **Withdraw consent to face/body capture** — this disables the avatar and
  personal-photo try-on features
- Access, correct, object to, or restrict processing (GDPR/CCPA, where applicable)

To exercise these, use the in-app controls above or email uprightseo24@gmail.com.

## 9. Children & teens

Wear The Mood is for users **13 and over**. We do not knowingly collect data from
anyone under 13; if we learn that we have, we delete the account and its data.

Some countries set a higher age for consenting to online services on your own
(in the EU/EEA this can be up to 16). If you are under that age where you live,
a parent or guardian must review this policy and give consent on your behalf —
including the **explicit consent** required before any face or body capture (§2).

## 10. Security

We use encryption in transit, scoped access controls, and signed, expiring URLs
for images. No system is perfectly secure; we work to protect your data and will
notify you of breaches as required by law.

## 11. Changes

We'll update this policy as the app evolves and post the new date above. Material
changes will be notified in-app.

## 12. Contact

Md Rabbi Hossain, operating as Wear The Mood · uprightseo24@gmail.com
