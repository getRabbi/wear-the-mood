# Apple App Review — privacy response (Guidelines 5.1.1(i), 5.1.2(i), 2.1)

Everything below is generated from the shipped implementation and the published
Privacy Policy, not from intent. Each claim names the file that proves it so a
reviewer — or a future maintainer — can check rather than trust.

- Privacy Policy: <https://wearthemood.com/legal/privacy> (updated August 12, 2026)
- The relevant section is **§ 2 "AI Processing, User Photos, and Face Data"**.

---

## A. How the reviewer can verify the consent flow

### A1. The just-in-time disclosure (the main path)

1. Sign in with the review account.
2. Open **MoodMirror** (bottom navigation).
3. **Step 1 — Body:** choose **My photo** and add/select a real personal photo.
   (Tap *Update* → add a full-body photo if the gallery is empty.)
4. **Step 2 — Garments:** select at least one item.
5. **Step 3 — Mode:** choose **AI Couture Try-On** (or **Try-On Max**).
6. Tap **Generate Look**.
7. **The disclosure sheet appears — before anything is transmitted.** It states
   what is sent (the chosen photo, which may include face and body), who receives
   it (FASHN.ai / FASHN LTD, and OpenAI for the safety check), why, and that the
   permission is optional. It links to the Privacy Policy.
8. Tap **Not Now** → the sheet closes, you stay on Step 3, the outfit and mode are
   still selected, **no credits are used and no AI request is made**.
9. Tap **Generate Look** again → the disclosure reappears.
10. Tap **Allow & Continue** → consent is recorded server-side, and only then is
    the try-on submitted and rendered normally.
11. Generate again → **no sheet.** The permission is remembered for the account.

### A2. Reviewing and withdrawing the permission

**Profile → ⋯ (top right) → Settings → Privacy & data → AI Photo Processing**

- Shows the current status: **ALLOWED** / **NOT ALLOWED**.
- **Review disclosure** re-opens the exact same sheet — deliberately available
  even when consent has already been granted, so this flow stays verifiable on an
  account that has already used it.
- **Withdraw permission** revokes it. The next AI request that would use a
  personal photo asks again.
- The same screen holds **Privacy Policy** and **Export my data**.

### A3. Paths that correctly do NOT show the disclosure

These are not omissions; no personal image is transmitted in any of them.

| What to try | Expected | Why |
|---|---|---|
| Step 3 → **2D Try-On** → *Open 2D Studio* | no sheet, no network | The 2D preview composes on-device. Nothing is uploaded. |
| Step 1 → pick a **studio model** → AI mode → Generate | no personal-photo sheet | The body is a Wear The Mood catalog photograph, not the user. The server re-resolves the model from its id (`model_source=studio_model`). |
| Closet → **AI Enhance** / **Catalog Model Shot** | no personal-photo sheet | These run on the photo of the *garment* (the app asks for it laid flat or on a hanger). Disclosed in Privacy Policy § 2.5 on its own terms. |

---

## B. Answers to the Guideline 2.1 face-data questions

### 1. What face data does the app collect?

Photographs that the user chooses and uploads: try-on/body photos, profile
pictures, and photos of clothing. These images may show the user's face and body.

**No face data beyond the photograph itself is collected or derived.** The app
does not create faceprints, facial-geometry templates, face embeddings, or any
biometric identifier, and performs no facial recognition or face matching.

The only automated image analysis is an **on-device full-body check** using
platform pose detection (`app/lib/features/profile/pose_validator.dart`,
Google ML Kit **Pose** Detection). It locates body points such as shoulders, hips
and ankles to confirm the photo shows a whole body, returns a pass/fail plus a
0–100 quality score, and stores and transmits nothing. It is not face detection
and cannot identify anyone.

*Verification:* the codebase contains no face-detection, face-recognition or
face-embedding dependency; `google_mlkit_pose_detection` is the only ML Kit
package in `app/pubspec.yaml`. The vector embeddings used elsewhere
(`backend/app/services/taste.py`) are of wardrobe items and outfits, never of a
person's face or body.

### 2. Complete explanation of use, sharing, retention, deletion and storage

**Use.** Solely to provide the feature the user requested — rendering a garment
onto their photo — and to run the mandatory safety check on the input. Not used
for advertising, profiling, identification, or model training.

**Sharing.** Only when the user runs an AI try-on with their own photo, and only
after they have granted the explicit permission described in section A. Two
processors receive the image:

- **OpenAI, L.L.C.** (United States) — automated content moderation of the input
  before any render (`backend/app/services/moderation/openai_moderator.py`).
- **FASHN LTD, "FASHN.ai"** (United States) — performs the try-on render
  (`backend/app/services/tryon/fashn.py`).

Nothing else receives it. Anthropic powers text-based styling and never receives
photos. We do not sell or share photos for advertising, and do not authorise
either provider to use them for their own purposes or to train models.

**Storage.** Images are held in private storage (Supabase Storage / Cloudflare
R2), never in a public bucket. They are readable only through **short-lived
signed URLs** (~1 hour). Row-level security scopes every record to its owner.
Generated results are downloaded into our own private storage immediately, so
history does not depend on the provider retaining anything.

**Retention.** See question 4.

**Deletion.** In-app and immediate: an individual body photo (Profile → Body
photo), a generated result (Saved Looks), a garment (closet), or the whole
account with all its images (**Settings → Delete Account**, double-confirmed).
Account deletion removes stored personal data within 30 days.

### 3. Is face-containing data shared with third parties? With whom? Where?

**Yes — with the user's explicit prior permission, and only for AI try-on using
their own photo.**

| Party | Receives | Purpose | Location |
|---|---|---|---|
| OpenAI, L.L.C. | the input image | required safety screening before rendering | United States |
| FASHN LTD (FASHN.ai) | the input image + garment image | performs the requested render | United States |

Two implementation details matter for how the image travels:

- **FASHN never fetches a URL of ours.** The photo is inlined as base64 into the
  request body over TLS (`backend/app/workers/tryon_worker.py`,
  `_inline_person_image`), so the private bucket is never exposed to a third
  party and there is no link that could outlive the request.
- **OpenAI is given a freshly signed, short-lived URL** which its servers fetch
  for the moderation call.

The permission check runs **before the moderation call**, not merely before the
render — moderation is itself a transmission of the same image
(`backend/app/routers/v1/tryon.py`, `require_ai_personal_image_consent`).

### 4. How long is it retained?

Stated in layers, because a single number would be wrong for most of them
(Privacy Policy § 6):

| Layer | Retention |
|---|---|
| Photos and results in the user's account | Until the user deletes them, or deletes the account. Not auto-expired — the body-photo gallery is a library the user re-uses. |
| Signed URLs used to display or transfer an image | ~1 hour, then the link stops working (the file is unaffected). |
| At the AI providers | Governed by each provider's own published terms. We download and store the result ourselves immediately, so nothing of ours depends on their retention. |
| Diagnostic logs | Events, timings and error categories only — no image content, and image URLs are redacted. |
| After account deletion | Deleted or anonymised within 30 days. |

### 5. Which Privacy Policy section contains this information?

**§ 2 "AI Processing, User Photos, and Face Data"** at
<https://wearthemood.com/legal/privacy>, with sub-sections:

- § 2.1 What we collect
- § 2.2 Face data — what we do and do not do
- § 2.3 Purpose
- § 2.4 Who receives your photo, and why
- § 2.5 Features that do NOT send your photo anywhere
- § 2.6 Your permission, and how to withdraw it

Retention is § 6; user rights and deletion are § 7; processors are § 4.

### 6. Exact Privacy Policy text

From § 2.2:

> **We do not create faceprints or biometric identifiers.** Specifically, Wear The
> Mood does **not**:
>
> - perform facial recognition, face matching, or face-based identification;
> - create or store facial-geometry templates, faceprints, or face embeddings;
> - build a biometric identity profile, or use your face to authenticate you;
> - attempt to determine who you are from a photo.
>
> Your photo is treated as an ordinary image file: it is stored, and it is passed
> to the AI model that renders clothing onto it.

From § 2.4:

> When — and only when — you run an AI try-on using **your own photo**, that image
> is sent to:
>
> | Recipient | What they receive | Why | Where |
> |---|---|---|---|
> | **OpenAI, L.L.C.** | the image, for an automated safety check | required content moderation … | United States |
> | **FASHN LTD ("FASHN.ai")** | the image, plus the garment image | performs the AI try-on render you requested | United States |
>
> Nothing is sent to either provider until you have given the permission described
> in § 2.6. If you decline, the request stops: no image is transmitted and no
> credits are used.
>
> **We do not use your photos to train AI models, and we do not grant our providers
> the right to do so.**

From § 2.6:

> You can review that disclosure, or withdraw the permission at any time, at:
>
> **Profile → Settings → Privacy → AI Photo Processing**

---

## C. Suggested "App Review Information → Notes" text

> Wear The Mood is a virtual try-on and wardrobe app. Users upload their own
> photo and the app renders clothing onto it.
>
> FACE DATA: we do not perform facial recognition and do not create faceprints,
> facial-geometry templates or biometric identity profiles. Photos are used only
> to render the requested try-on. On-device pose detection is used to check a
> photo shows a full body; it stores and transmits nothing.
>
> CONSENT: before a user's own photo is first sent to a third-party AI provider
> (FASHN LTD for rendering; OpenAI for the required safety screening), the app
> shows a disclosure naming what is sent, who receives it and why, and requires
> an explicit "Allow & Continue". Declining transmits nothing and charges nothing.
> The permission can be reviewed and withdrawn at any time in
> Profile → Settings → Privacy & data → AI Photo Processing.
>
> TO REPRODUCE: MoodMirror → Step 1 select "My photo" and add a photo → Step 2
> select a garment → Step 3 choose "AI Couture Try-On" → Generate Look. The
> disclosure appears before any network transmission.
>
> The free 2D preview runs entirely on-device, and trying clothes on a Wear The
> Mood studio model sends no personal photo — neither shows the disclosure,
> by design.
>
> Privacy Policy: https://wearthemood.com/legal/privacy (section 2, "AI
> Processing, User Photos, and Face Data").

---

## D. Suggested reply to App Review

> Thank you for the detailed review. We have addressed both points.
>
> **Guidelines 5.1.1(i) and 5.1.2(i) — consent before third-party data sharing.**
> The app now obtains explicit, just-in-time consent before a user's own photo is
> transmitted to any third-party AI provider. On the first such request the user
> sees a disclosure identifying what is sent (the photo they selected, which may
> include their face and body), who receives it (FASHN LTD for the try-on render,
> and OpenAI for the mandatory safety screening), and why. Processing begins only
> after an explicit "Allow & Continue". Declining transmits nothing, creates no
> job and charges no credits, and preserves the user's selections. The permission
> is recorded per account, is versioned so a material change re-asks, and can be
> reviewed or withdrawn at any time at Profile → Settings → Privacy & data → AI
> Photo Processing. The check is also enforced server-side, before any image
> leaves our systems, so it cannot be bypassed by the client.
>
> Features that transmit no personal image — the on-device 2D preview and try-ons
> on our own studio models — intentionally do not show the prompt.
>
> **Guideline 2.1 — face data.** Wear The Mood does not perform facial
> recognition and does not create faceprints, facial-geometry templates, face
> embeddings, or biometric identity profiles. User photographs are used only to
> render the clothing the user asked to try on. The single automated analysis is
> an on-device pose check confirming the photo shows a full body; it returns a
> pass/fail and stores or transmits nothing. Complete answers to each of your six
> questions — collection, use, sharing, retention, deletion and storage — are in
> section 2, "AI Processing, User Photos, and Face Data", of our Privacy Policy at
> https://wearthemood.com/legal/privacy, with retention in section 6 and deletion
> and withdrawal rights in section 7.
>
> Reproduction steps for the consent flow are in App Review Information → Notes.
> We are happy to provide anything further.

---

## E. App Store Connect — App Privacy answers

Recommended answers, each with the code path that justifies it. **Do not
over-declare.** Every "Yes" below is something the app genuinely does.

### Declare: YES

| Data type | Linked to user | Tracking | Purpose | Why |
|---|---|---|---|---|
| **User Content → Photos or Videos** | Yes | No | App Functionality | Try-on/body photos, profile pictures and wardrobe images are uploaded and stored against the account (`/v1/tryon-photos`, `/v1/wardrobe`, private buckets keyed by user id). |
| **User Content → Other User Content** | Yes | No | App Functionality | Posts, comments, giveaway listings and pickup-chat messages. |
| **Contact Info → Email Address** | Yes | No | App Functionality | Account sign-in via Supabase Auth. |
| **Contact Info → Name** | Yes | No | App Functionality | Display name on the profile. |
| **Identifiers → User ID** | Yes | No | App Functionality | Supabase user id; RevenueCat app user id for entitlements. |
| **Purchases → Purchase History** | Yes | No | App Functionality | Subscription/entitlement state via RevenueCat (`/v1/billing`). |
| **Diagnostics → Crash Data** | Yes | No | App Functionality | Sentry. |
| **Diagnostics → Performance Data** | Yes | No | App Functionality | Sentry + stage timings (`backend/app/core/timing.py`). |
| **Usage Data → Product Interaction** | Yes | No | Analytics | PostHog event taxonomy. **See the note below before answering.** |
| **Location → Coarse Location** | Yes | No | App Functionality | Weather for the stylist, **only** with the OS permission (`/v1/weather`). If you ship with the location permission removed, answer No. |
| **Health & Fitness → Fitness** | Yes | No | App Functionality | Only if the optional body measurements (height/weight) are treated as fitness data. **See the note below.** |

### Declare: NO

| Data type | Why not |
|---|---|
| **Sensitive Info (biometric)** | No biometric identifier is created or stored: no faceprints, facial-geometry templates, face embeddings or facial recognition anywhere in the codebase. A photograph that happens to show a face is *User Content → Photos*, not a biometric template. Answering Yes here would be an over-declaration that also contradicts the Privacy Policy. **If Apple's guidance for your submission asks you to treat body/face photos as sensitive, declare them and keep § 2.2 of the policy as the explanation — do not change the code answer.** |
| **Contacts** | The app never reads the address book. |
| **Browsing History / Search History** | Not collected. |
| **Financial Info** | Payments are handled entirely by the App Store / RevenueCat; no card data reaches us. |
| **Precise Location** | Only coarse location is requested. |
| **Tracking (App Tracking Transparency)** | No data is shared with data brokers or used for cross-app advertising. No ATT prompt is required. |

### Two answers to settle before submitting

1. **Usage Data → Product Interaction.** The analytics wrapper is present but the
   PostHog key is empty in the app config and on the production backend, so
   `analyticsProvider` is currently a no-op and **nothing is actually collected**.
   If you ship without a key, answer **No** and add the key + declaration
   together later. If you add the key before submission, answer **Yes**.
2. **Health & Fitness → Fitness.** Body measurements (height/weight) are optional
   free-text profile fields used for fit, not health tracking. Many comparable
   apps do not declare this. Decide once and keep the policy consistent with it.

### Manual App Store Connect actions (nothing in this repo can do these)

- Update the App Privacy answers per the table above.
- Set the Privacy Policy URL to `https://wearthemood.com/legal/privacy`.
- Paste section C into **App Review Information → Notes**.
- Paste section D as the reply in Resolution Center.
- Ensure the review account has (or can add) a body photo so step A1.3 works.

---

## F. Open item requiring the founder's verification

**FASHN and OpenAI terms on training and retention.** The policy states what *we*
do: we do not use photos to train models and do not grant providers that right,
and provider-side retention is governed by their own terms. It deliberately does
**not** assert that FASHN or OpenAI do not train on submitted content, because
nothing in this repository evidences their current terms.

Before submission, read the current FASHN API terms and the OpenAI API data-usage
policy and confirm the no-training position for API traffic. If confirmed, § 2.4
can be strengthened to say so explicitly — which is a stronger answer to Apple's
question 2 — and `LICENSES.md` should record the date checked. Until then the
current wording is the accurate one.
