# Try-On timing — how to take the measurement

Phase 7A shipped instrumentation only. Nothing about the try-on pipeline's
behaviour changed. This is how to get the numbers that decide what changes next.

You need **one cold run and one immediately-following warm run**. The cold one
includes the worker's container start; the warm one does not, and the difference
between them is the whole point.

---

## What it costs

| Run | Mode | Credits |
|---|---|---|
| Cold | Standard (AI Couture) | 1 |
| Warm | Standard (AI Couture) | 1 |
| **Total** | | **2 credits, maximum** |

Use **AI Couture**, not Full Look. Full Look is HD, costs 4 credits each, and is
Pro Max only. Two standard renders is the entire cost of this exercise.

If a render fails, the credits are refunded server-side automatically — that is
existing behaviour and this commit did not touch it.

---

## 1. Build and install

The APK must be a **debug** build (the client trace prints in debug only) built
against **prod** (so it talks to the real backend and the real worker).

```powershell
cd E:\dopplefit\app
flutter build apk --debug --dart-define-from-file=env/prod.json
```

> The `--dart-define-from-file` is not optional. Without it Supabase never
> initialises, and a build made from `env/dev.json` alone points at the
> emulator-only `10.0.2.2` and cannot reach the backend at all.

Install onto the device:

```powershell
$adb = "E:\SDK\platform-tools\adb.exe"
& $adb devices                     # confirm exactly one device is listed
& $adb install -r E:\dopplefit\app\build\app\outputs\flutter-apk\app-debug.apk
```

If the install fails with a signature mismatch, and **only** then:

```powershell
& $adb uninstall com.fashionos.app
& $adb install E:\dopplefit\app\build\app\outputs\flutter-apk\app-debug.apk
```

---

## 2. Start capturing the client log

In its own terminal, **before** you tap anything:

```powershell
$adb = "E:\SDK\platform-tools\adb.exe"
& $adb logcat -c                                   # clear the old buffer
& $adb logcat | Select-String "WTM-TIMING" | Tee-Object -FilePath tryon-timing.txt
```

Leave it running for both renders. Every finished try-on prints exactly one line.

---

## 3. The cold run

The worker is a scale-to-zero Azure Container Apps Job, so "cold" means nothing
has run for a while.

1. **Wait at least 15 minutes** since the last try-on, AI enhance or wardrobe
   add on this account. That is what guarantees the worker is asleep.
2. Open the app → **MoodMirror**.
3. Step 1: pick your body photo. Step 2: pick **one** garment. Step 3: choose
   **AI Couture**.
4. Tap **Generate** and leave the screen open until the render appears.

Do not background the app during the render — that changes what you are
measuring.

## 4. The warm run

**Immediately** after the first result appears (within a minute or two, while
the worker is still up):

1. Back to MoodMirror → same body photo, same single garment, **AI Couture**.
2. Tap **Generate**, wait for the result.

---

## 5. Collect the three log lines

### Client (the device)

One line per render, in `tryon-timing.txt`:

```
[WTM-TIMING] tryon.client trace=ab12cd34 total=48210ms tap=0ms+0 body_resolved=430ms+430 ...
```

**Copy both lines** (cold and warm). Note the `trace=` token on each — that is
what stitches the three processes together.

### Submit endpoint (Heroku)

```powershell
heroku logs --app wtm-api-prod --num 1500 | Select-String "tryon.submit"
```

Find the two lines whose `trace=` matches your two client lines.

### Worker (Azure)

```powershell
az containerapp job logs show `
  --name wtm-ai-orchestrator-job `
  --resource-group <your-rg> `
  --container orchestrator `
  --tail 500 | Select-String "tryon.worker|orchestrator batch"
```

Two things to grab:

* the `tryon.worker trace=...` line for each render, and
* the `orchestrator batch` line, which carries `startup_s` — the container's
  own cold-start cost, which is the number the cold/warm comparison hinges on.

---

## 6. What to send back

For each of the two runs, the three lines:

```
tryon.client  trace=xxxxxxxx total=...ms ...
tryon.submit  trace=xxxxxxxx total=...ms ...
tryon.worker  trace=xxxxxxxx total=...ms ...
```

plus the `startup_s` from the cold run's batch line.

Nothing in those lines identifies you or anyone else: they carry durations,
counts and byte sizes only, and the trace token is an 8-character prefix of the
request's idempotency key — enough to correlate three logs, not enough to replay
a request.

---

## What the stages mean

| Stage | Where | What it measures |
|---|---|---|
| `tap` | client | Generate pressed. Always 0. |
| `body_resolved` | client | Resolving the chosen body photo/model. **Runs before any navigation** — this is the "nothing happened when I pressed it" gap. |
| `ui_visible` | client | The generating screen is on screen. |
| `submit_sent` → `submit_accepted` | client | The full `POST /v1/tryon` round trip. |
| `resolve_inputs` | submit | DB lookups for the body + garment stack. |
| `freshen_urls` | submit | Re-signing expiring media URLs. |
| `moderate_person` | submit | Vision moderation of the body photo. |
| `moderate_garments` | submit | Vision moderation of each garment — **serial today**, one at a time. |
| `create_and_reserve` | submit | Job row + credit reservation. |
| `enqueue` | submit | Waking the worker. |
| *(gap)* | — | Queue wait + container start. Read from `startup_s` and the clock difference between the submit and worker lines. |
| `person_inline` | worker | Downloading the body photo and base64-encoding it (value = bytes). |
| `provider_accept` | worker | How long FASHN took to accept the job. |
| `provider_inference` | worker | How long FASHN took to render it (value = our poll count). |
| `result_download` | worker | Fetching the result (value = bytes). |
| `result_store` | worker | Re-uploading it to R2. |
| `first_poll` / `terminal` | client | Status polling; `terminal` carries the poll count. |
| `result_rendered` | client | The render is on screen. |

---

## Then what

Those numbers decide Phase 7B. Pre-approved once they confirm it: concurrent
moderation (fail-closed), a reused `httpx` client, an immediate first status
check, instant navigation after Generate, in-flight job restoration.

Still needing separate approval regardless of what the numbers say: the FASHN
`quality` → `balanced` mode, removing the person-image base64, any paid
infrastructure change, and anything touching credit pricing or charging rules.
