# Fashion OS — Setup, Stack & Claude Code Workflow Guide
*(Flutter mobile + FastAPI + Supabase | solo dev + Claude Code | VS Code)*

---

## 0. Boro Picture: Tumi-Ami kivabe kaj korbo

- **Ei chat (Claude.ai)** = planning, architecture, debugging strategy, stuck hole solve kora, blueprint update.
- **Claude Code (terminal/VS Code-er moddhe)** = actual file create, code likha, command chalano, git commit, run/test.
- **Tumi** = Claude Code chalabe, decisions debe, app store-e dibe, real device-e test korbe.

Workflow: ei chat-e amra blueprint thik kori → tumi `CLAUDE.md` (niche dewa) project-e rakho → Claude Code-e bolo "read CLAUDE.md and build Phase 1, Step 1" → o code likhe dey → tumi run koro → atke gele ei chat-e screenshot/error niye asho.

---

## 1. Stack (Final)

| Layer | Tech | Keno |
|---|---|---|
| Mobile (iOS+Android) | **Flutter (Dart)** | Ek codebase, dut platform, native-feel, bhalo camera/image support |
| State management | **Riverpod** | Modern, testable, Claude Code bhalo chea |
| Backend API | **FastAPI (Python)** | Tomar existing skill; AI orchestration layer |
| DB + Auth + Storage + Realtime | **Supabase (Postgres)** | Tomar existing skill; sob ek jaygay |
| Subscriptions / IAP | **RevenueCat** | iOS+Android IAP ek SDK-te |
| Image CDN | **Cloudflare R2 + CDN** | Sosta, fast image delivery |
| AI: Try-on | **FASHN.ai API** ($0.075/img) | Funnel hook; provider abstract korte hobe |
| AI: Background removal | **PhotoRoom / remove.bg** | Wardrobe item cutout |
| AI: Tagging | **Vision LLM (Claude/Gemini)** | Auto category/color/pattern tag |
| AI: Stylist | **Claude (Haiku/Sonnet)** | Conversational stylist |
| Push | **Firebase Cloud Messaging** | Notification |

**Mathay rakho:** Flutter = Dart, eta tomar jonno notun language. Backend Python-ei thakbe. Dart syntax C-style, TypeScript jano bole 1-2 sptah-e comfortable hobe. Claude Code Dart likhe dibe, tumi pore bujhe nibe.

---

## 2. VS Code + Flutter Setup (step by step)

### 2.1 Ki ki install korte hobe
1. **Flutter SDK** — flutter.dev/docs/get-started/install (tomar OS onujayi). PATH-e add koro.
2. **Dart SDK** — Flutter-er sathei ashe, alada lage na.
3. **VS Code** — already ache dhore nilam.
4. **VS Code Extensions:**
   - `Flutter` (Dart-Code.flutter) — must
   - `Dart` (auto ashe Flutter-er sathe)
   - `Error Lens` — inline error dekhay
   - `Claude Code` extension / ottoba terminal-e Claude Code CLI
5. **Android Studio** — Android SDK + emulator-er jonno (full IDE use korte hobe na, shudhu SDK + AVD lagbe).
6. **Xcode** (shudhu Mac thakle) — iOS build + simulator. **Windows/Linux-e iOS build hoy na** — eta important, niche dekho.
7. **Python 3.11+** — backend (already ache).
8. **Node** — Supabase CLI / kichu tooling-er jonno (optional).
9. **Git** — version control (already ache).

### 2.2 Setup verify
```bash
flutter doctor
```
Eta bolbe ki ki baki ache (Android licenses, Xcode, etc.). Sob ✓ na howa porjonto fix koro. `flutter doctor` = tomar best friend setup-er somoy.

### 2.3 iOS niye honest kotha
- **Mac na thakle iOS app build/publish korte parba na** locally. Options:
  - (a) **Mac kino / borrow koro** (Mac Mini sosta option).
  - (b) **Cloud Mac** (MacStadium, Codemagic CI/CD — Codemagic Flutter-er jonno bana, free tier ache, cloud-e iOS build kore App Store-e dey).
  - (c) **Android-first launch koro**, iOS pore Codemagic diye.
- **Suggestion:** Android-e develop + test koro (tomar machine-e), iOS build + App Store deploy **Codemagic** diye koro. Eta solo dev-er jonno cleanest path.

### 2.4 Project create
```bash
flutter create --org com.fashionos fashionos_app
cd fashionos_app
flutter run   # emulator/device-e cholbe
```

---

## 3. Project Structure (Claude Code ke ei structure follow korte bolbe)

```
fashionos/
├── CLAUDE.md                  # blueprint (niche dewa) — Claude Code ei file age porbe
├── app/                       # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/              # theme, constants, router, env
│   │   ├── data/              # models, repositories, supabase + api clients
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── profile/        # avatar, body data
│   │   │   ├── tryon/          # try-on hook
│   │   │   ├── wardrobe/       # digital almira
│   │   │   ├── stylist/        # AI stylist chat
│   │   │   ├── social/         # OOTD feed, follow
│   │   │   └── news/           # fashion news feed
│   │   └── shared/             # widgets, utils
│   └── pubspec.yaml
├── backend/                   # FastAPI
│   ├── app/
│   │   ├── main.py
│   │   ├── routers/           # tryon, wardrobe, stylist, news, social
│   │   ├── services/          # fashn_client, bg_removal, claude_stylist, tagging
│   │   ├── core/              # config, auth (supabase jwt verify), credits
│   │   └── models/
│   ├── requirements.txt
│   └── .env.example
└── supabase/
    └── FASHIONOS_COMPLETE.sql  # tomar single-file schema pattern
```

---

## 4. Claude Code Workflow (tomar daily routine)

1. **Notun feature shuru:** Claude Code-e bolo — `"Read CLAUDE.md. Build Phase 1 Step 2 (wardrobe item add + background removal). Follow the project structure."`
2. **Choto step-e bhag koro** — ek bare pura app na, ek feature ek feature. Claude Code choto scoped task-e bhalo kore.
3. **Run + test koro** — `flutter run` (app), `uvicorn app.main:app --reload` (backend).
4. **Error pele** — error ta copy kore Claude Code-ke dao, o fix korbe. Boro/confusing hole ei chat-e niye asho.
5. **Kaj hole git commit** — `git add . && git commit -m "feat: wardrobe add"`. Choto choto commit, jate revert kora jay.
6. **Provider abstract rakho** — FASHN/remove.bg/Claude shob `services/`-e wrapper-er pichone, jate pore swap kora jay.

**Tip:** prottek feature-er por Claude Code-ke bolo "write a short test / show me how to test this manually." Solo dev-er jonno test discipline life-saver.

---

## 5. Cost Control (din 1 theke)

- Free tier-e **daily credit cap** rakho (e.g. din-e 3-5 free try-on). Naile FASHN bill ($0.075/img) bere jabe.
- Supabase-e ekta `credits` table, prottek AI call-e decrement.
- Claude stylist-e **prompt caching** on koro — 90% porjonto sosta.
- Background removal-e sosta provider (PhotoRoom ~$0.01-0.02) diye shuru.

---

## 6. Build Order (summary — detail CLAUDE.md-te)

- **Phase 0 (sptah 1-2):** Setup, Supabase schema, FastAPI skeleton, Flutter skeleton, auth.
- **Phase 1 (sptah 3-8):** Try-on hook + wardrobe (add/tag/cutout/closet view/outfit build/share). **= launchable MVP.**
- **Phase 2 (sptah 8-12):** Claude stylist + OOTD social feed. **= public launch.**
- **Phase 3 (mash 4-6):** News feed + "shop the look" affiliate.
- **Phase 4+ (mash 6+):** Subscription depth, analytics, packing planner, shoes/glasses, resale.

**Ekhon na korbe:** custom diffusion model train, native AR, biometric body scan, multi-language. Pore.
