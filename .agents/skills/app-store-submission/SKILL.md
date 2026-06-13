---
name: app-store-submission
description: End-to-end submission of an iOS/iPadOS app to the App Store, driven almost entirely by the App Store Connect API + Xcode CLI (no manual portal clicking where avoidable). Use when archiving, uploading a build, setting metadata/screenshots/pricing, and submitting for review. Covers the hard-won gotchas (iPhone-screenshot quirk for iPad-only apps, App Privacy being UI-only, CloudKit Production schema deploy, required fields that block submission).
license: MIT
metadata:
  author: Tertiary Infotech Academy
  version: "1.0.0"
---

# App Store Submission (API-first)

Submit a native iOS/iPadOS app to the App Store with the **App Store Connect (ASC) API**
and the **Xcode command line**, doing as much as possible programmatically. This skill
captures a complete, repeatable workflow plus the non-obvious blockers that waste hours.

Use the bundled scripts in [scripts/](scripts/). Per-project values and the metadata copy
go in the project's `.env` and the template at the end of this doc.

## What the API CAN and CANNOT do

**API can:** create/read the app record, set category & pricing, set version metadata
(description, keywords, subtitle, promo text, support/marketing URLs, copyright,
**privacyPolicyUrl**), create the **App Review contact**, upload builds (via `altool`),
attach a build, upload screenshots, create a review submission, and **submit for review**.

**API CANNOT (must be done once in the web UI):**
- **App Privacy "nutrition label"** (`appDataUsages`). There is **no public API** — the
  app resource exposes no `appDataUsages` relationship; every path 404s. Set it in the UI:
  *App Privacy → Get Started → "No, we do not collect data" (if true) → Publish*.
- **Age rating / content rights** declarations are also effectively UI-only.
- **Deleting an empty draft review submission** returns 403 — harmless, leave or delete in UI.

Plan for one short UI visit per app for the App Privacy publish. Everything else is scriptable.

## Prerequisites (one-time per Apple account)

1. **Paid Apple Developer Program** membership (accept the latest PLA in the portal).
2. **Generate the App Store Connect API key — the ONE unavoidable portal step.**
   An ASC API key **cannot be created via API** (chicken-and-egg); the account holder must
   generate it once in the web UI. After that, this skill drives everything else without
   touching the portal. Hand the user these exact clicks:

   > 1. Sign in at <https://appstoreconnect.apple.com> as the **Account Holder / Admin**.
   > 2. **Users and Access** → top tab **Integrations** → **App Store Connect API** →
   >    **Team Keys**.
   > 3. Click **+** (Generate API Key). Name it (e.g. "automation"), set **Access = Admin**
   >    (or at least **App Manager**), **Generate**.
   > 4. **Download** the **`AuthKey_<KEYID>.p8`** — this is offered **only once**. Save it to
   >    `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` then `chmod 600` it.
   > 5. Copy the **Key ID** (the 10-char id in the row) and the **Issuer ID** (UUID shown
   >    above the keys list).

   These three values are all the skill needs. If a key is ever lost/leaked, **Revoke** it
   in the same screen and generate a new one.
3. Put the **Key ID** and **Issuer ID** in a local **`.env`** (gitignored) and point
   `ASC_PRIVATE_KEY_PATH` at the `.p8`. See [.env.example](.env.example). The `.p8` lives
   outside the repo and is **never** committed (`.gitignore` excludes `.env` and `*.p8`).

```bash
# .env  (gitignored)
ASC_KEY_ID=YQHNLVGDWK
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_PRIVATE_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_YQHNLVGDWK.p8
```

Load it before running scripts: `set -a; source .env; set +a`

## The workflow

### 0. Pre-flight code checklist (in the repo)
- App icon **1024×1024, no alpha** in the asset catalog.
- `CFBundleShortVersionString` (marketing, e.g. `1.0`) and `CFBundleVersion` (build, integer,
  **bump on every upload**).
- `ITSAppUsesNonExemptEncryption = false` in Info.plist (skips the export-compliance prompt)
  — only if you use no non-exempt crypto.
- Usage-description strings for every permission (`NSMicrophoneUsageDescription`, etc.).
- `UIRequiredDeviceCapabilities = arm64` (never the legacy `armv7`).
- **`PrivacyInfo.xcprivacy`** privacy manifest (tracking false, collected types, required-reason APIs).
- For **iPad-only**: `TARGETED_DEVICE_FAMILY = 2`. For iPhone-only: `1`. Universal: `1,2`.
- **Per-config entitlements** if using CloudKit/push: Debug → `aps-environment=development`,
  Release → `production`.

### 1. Archive + upload the build (Xcode CLI)
```bash
xcodebuild -project App.xcodeproj -scheme App -configuration Release \
  -archivePath /tmp/App.xcarchive archive
xcodebuild -exportArchive -archivePath /tmp/App.xcarchive \
  -exportPath /tmp/export -exportOptionsPlist ExportOptions.plist   # method: app-store
xcrun altool --validate-app -f /tmp/export/App.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
xcrun altool --upload-app   -f /tmp/export/App.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```
`altool` reads the `.p8` from `~/.appstoreconnect/private_keys/` automatically.
Build processing takes ~5–30 min; poll until state is `VALID`.

### 2. Everything else (ASC API)
Use [scripts/asc_submit.py](scripts/asc_submit.py) — it loads `.env`, mints a JWT via
[scripts/asc_jwt.swift](scripts/asc_jwt.swift), and exposes subcommands:

```bash
python3 scripts/asc_submit.py status                 # app id, version, build, blockers
python3 scripts/asc_submit.py set-metadata           # copyright, privacyPolicyUrl, URLs
python3 scripts/asc_submit.py review-contact         # App Review contact (required)
python3 scripts/asc_submit.py attach-build  --build 2
python3 scripts/asc_submit.py screenshots   --type APP_IPAD_PRO_3GEN_129 a.png b.png
python3 scripts/asc_submit.py submit                 # create review submission + submit
```

### 3. Submit for review
`submit` creates a `reviewSubmission`, adds the version as a `reviewSubmissionItem`, then
PATCHes `submitted=true`. On success the version state becomes `WAITING_FOR_REVIEW`. The
command prints any blocker codes returned in `associatedErrors`.

### 4. CloudKit Production schema deploy (if the app uses CloudKit/SwiftData+CloudKit)
**Not a review blocker, but ships broken sync if skipped.** App Store builds use the
**Production** CloudKit environment; the schema you developed against is in **Development**.
In **CloudKit Console → your container → Schema → Record Types → Deploy Schema Changes…**,
review the Development→Production diff and **Deploy**.
- A record type only exists in the schema **after a record of that type was created** in the
  Development environment. Production **cannot auto-create** new record types. So if a model
  was never exercised in dev (e.g. a rarely-used `CD_AudioNote`), its type is **absent** and
  that data won't sync until you create one record in a Debug build and **re-deploy**.

## Submission blockers cheat-sheet (the 409 `associatedErrors`)

| Blocker code / message | Fix |
|---|---|
| `appInfoLocalizations … privacyPolicyUrl` required | PATCH `appInfoLocalizations/{id}` `privacyPolicyUrl` |
| `appStoreVersions … copyright` required | PATCH `appStoreVersions/{id}` `copyright` (e.g. `2026 Acme Pte Ltd`) |
| `appStoreReviewDetail … was not found` | POST `appStoreReviewDetails` with contact name/phone/email, `demoAccountRequired` |
| `APP_DATA_USAGES_REQUIRED` | **UI-only**: App Privacy → publish "Data Not Collected" (or fill labels) |
| `SCREENSHOT_REQUIRED.APP_IPHONE_65` | See the iPhone-screenshot quirk below |

## Gotchas (the time-savers)

- **iPhone 6.5" screenshot demanded for an iPad-only app.** The API submission validator
  spuriously requires an `APP_IPHONE_65` screenshot even when the binary is `UIDeviceFamily=2`.
  The **web UI** usually won't ask, but the **API** will. Fastest unblock: generate valid
  1242×2688 (or 1284×2778) images and upload them to an `APP_IPHONE_65` set —
  [scripts/make_iphone_screenshot.swift](scripts/make_iphone_screenshot.swift) frames an
  existing iPad capture on a branded gradient so it looks intentional, not letterboxed.
  Harmless for an iPad-only listing (the binary still determines device compatibility).
- **A stale earlier build keeps the app "universal."** If build 1 was uploaded universal
  (before you set `TARGETED_DEVICE_FAMILY=2`) and is still `VALID`, expire it
  (`PATCH /v1/builds/{id}` `expired=true`) so it stops influencing device support.
- **Screenshot upload is a 3-step dance**, not a single PUT: (1) `POST /v1/appScreenshots`
  reserve with `fileSize`+`fileName` → returns `uploadOperations`; (2) PUT the bytes to each
  operation's `url` with its `requestHeaders`; (3) `PATCH /v1/appScreenshots/{id}`
  `uploaded=true` + `sourceFileChecksum` = **MD5 hex** of the file. Then poll
  `assetDeliveryState.state == COMPLETE`.
- **Bundle ID already taken** → pick a namespaced reverse-DNS id you control
  (`com.yourorg.appname`); update `project.yml`/Info.plist and the iCloud container to match.
- **Device not registered / iCloud container mismatch** when test-installing on hardware →
  register the device UDID in the portal and ensure the iCloud container is created and
  assigned to the App ID.
- **JWT lifetime** ≤ 20 min (`exp = iat + 1200`), `aud = "appstoreconnect-v1"`, ES256.
  Regenerate per script run; don't cache.
- **Empty draft review submissions** created during testing can't be deleted via API (403).
  Ignore them or remove in the UI.

## Screenshot display types (common)

| Device | `screenshotDisplayType` | Required size (px) |
|---|---|---|
| iPad 13" / 12.9" | `APP_IPAD_PRO_3GEN_129` | 2064×2752 or 2048×2732 (portrait) |
| iPhone 6.9" | `APP_IPHONE_67` | 1290×2796 |
| iPhone 6.5" (legacy, the quirk) | `APP_IPHONE_65` | 1242×2688 or 1284×2778 |

Only the **first 3** screenshots per set appear on the install sheet.

## Per-project template

Fill these per app — keep them in the project's `.env` (credentials/URLs/contact) and a short
note in the repo (identity + the marketing copy). Example values from NotePad shown.

```
App name:        Tertiary NotePad
App ID (ASC):    6779909944               # numeric; resolved from bundle id if blank
Bundle ID:       com.tertiaryinfotech.notepadapp
iCloud container: iCloud.com.tertiaryinfotech.notepadapp   # if using CloudKit
Team ID:         GU9WTSTX9M
Platform:        iPadOS 18+ (iPad only, TARGETED_DEVICE_FAMILY=2)
Category:        Productivity (secondary: Education)
Price:           Free
Version / Build: 1.0 / 2
```

Marketing copy to paste into the version localization (subtitle ≤30 chars, keywords ≤100
chars CSV, promo text ≤170 chars, description ≤4000 chars):

```
Subtitle:    Apple Pencil notes & flowcharts
Keywords:    notes,handwriting,apple pencil,notebook,flowchart,pdf,annotate,blackboard,ipad
Promo text:  A fast, native iPad notebook for Apple Pencil — handwriting, shapes,
             flowcharts, PDF markup, and blackboard mode, synced with iCloud.
Description: <full long description>
```
