# App Store Submission Guide — NotePad

A step-by-step guide to submitting **NotePad** (iPadOS 18+) to the App Store.

> TL;DR: register the App ID → archive in Xcode → upload to App Store Connect →
> fill in metadata + screenshots → submit for review.

---

## 0. Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Apple Developer Program** | Paid membership, **$99/year** — <https://developer.apple.com/programs/> |
| **Xcode 16+** | Full Xcode (not just command-line tools) on a Mac |
| **App Store Connect access** | <https://appstoreconnect.apple.com> |
| **A real iPad** (recommended) | For final testing via TestFlight |

This repo uses **XcodeGen**, so generate the project first:

```bash
brew install xcodegen
xcodegen generate
open NotePadApp.xcodeproj
```

---

## 1. Assets checklist

| Asset | Status | Where |
|-------|--------|-------|
| **App icon — 1024×1024, no alpha** | ✅ Included | `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |
| **iPad screenshots (13") — 1 to 10** | ⬜ You capture | See [§6](#6-screenshots) |
| App preview video (optional) | ⬜ Optional | `.mov`, up to 3 |
| Export-compliance key | ✅ Set | `ITSAppUsesNonExemptEncryption = false` in `App/Info.plist` |

The icon is **regenerable** at any time:

```bash
swift scripts/generate_icon.swift
```

Xcode auto-creates every smaller icon size from this single 1024 image (iOS
single-size asset catalog). No other icon files are needed.

---

## 2. One-time setup in the Apple Developer portal

1. **Register the App ID / Bundle Identifier.**
   - <https://developer.apple.com/account/resources/identifiers/list>
   - Bundle ID: **`com.notepad.app`** (matches `project.yml`). Change it to a
     unique reverse-DNS you own if `com.notepad.app` is taken, and update
     `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, then re-run `xcodegen generate`.
   - Capabilities: none required (the app is fully offline/local). Leave defaults.

2. **Create the app record in App Store Connect.**
   - <https://appstoreconnect.apple.com/apps> → **+** → **New App**
   - Platform: **iOS** · Name: **NotePad** (must be globally unique — pick an
     available name, e.g. "NotePad — Paper Notebook") · Primary language: English
   - Bundle ID: select `com.notepad.app` · SKU: any unique string (e.g. `notepad-001`)
   - User Access: Full Access

---

## 3. Signing in Xcode

1. Select the **NotePadApp** target → **Signing & Capabilities**.
2. **Automatically manage signing** ✓ · **Team**: your Apple Developer team.
3. Xcode provisions a distribution profile automatically.

> Because the `.xcodeproj` is generated, set the Team once in Xcode each time you
> regenerate, **or** pin it in `project.yml` under the target's settings:
> ```yaml
> settings:
>   base:
>     DEVELOPMENT_TEAM: ABCDE12345   # your 10-char Team ID
> ```

---

## 4. Versioning

| Field | Build setting | Example |
|-------|---------------|---------|
| Marketing version | `MARKETING_VERSION` / `CFBundleShortVersionString` | `1.0` |
| Build number | `CURRENT_PROJECT_VERSION` / `CFBundleVersion` | `1` |

Every upload to App Store Connect needs a **unique, increasing build number**.
Bump `CFBundleVersion` in `App/Info.plist` (or set `CURRENT_PROJECT_VERSION` in
`project.yml`) for each new upload.

---

## 5. Archive & upload

### Option A — Xcode GUI (easiest)

1. Toolbar device selector → **Any iOS Device (arm64)**.
2. **Product → Archive**.
3. When the **Organizer** opens → select the archive → **Distribute App** →
   **App Store Connect** → **Upload** → follow prompts (let Xcode manage signing).
4. Wait for the build to finish **processing** in App Store Connect (a few minutes
   to ~1 hour). It then appears under **TestFlight** and is selectable for release.

### Option B — Command line

```bash
xcodegen generate

# 1) Archive
xcodebuild -project NotePadApp.xcodeproj -scheme NotePadApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/NotePad.xcarchive \
  archive

# 2) Export a signed .ipa  (see ExportOptions.plist below)
xcodebuild -exportArchive \
  -archivePath build/NotePad.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist

# 3) Upload (use an App Store Connect API key — recommended)
xcrun altool --upload-app -f build/export/NotePadApp.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
# (or upload build/export/NotePadApp.ipa with the Transporter app)
```

`ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>          <string>app-store</string>
  <key>destination</key>     <string>export</string>
  <key>teamID</key>          <string>ABCDE12345</string>
  <key>signingStyle</key>    <string>automatic</string>
  <key>uploadSymbols</key>   <true/>
</dict>
</plist>
```

> App Store Connect **API keys**: App Store Connect → Users and Access → Integrations
> → Keys. Download the `.p8` once and note the Key ID + Issuer ID.

---

## 6. Screenshots

This is an **iPad-only** app (`TARGETED_DEVICE_FAMILY = 2`), so App Store Connect
requires only **iPad** screenshots — specifically the **13-inch** set.

| Display | Accepted pixel sizes (portrait) | Device to use |
|---------|--------------------------------|---------------|
| **iPad 13" (required)** | **2064 × 2752** or **2048 × 2732** | iPad Pro 13" (M4) / iPad Pro 12.9" simulator |
| iPad 11" (optional) | 1668 × 2388 | iPad Pro 11" |

- 1–10 images, PNG or JPG, **no alpha, no rounded corners**, RGB.
- Landscape is allowed (swap the dimensions) but be consistent.

**Capture from the Simulator:**

```bash
# Boot a 13" iPad simulator, run the app, then:
xcrun simctl boot "iPad Pro 13-inch (M4)"
open -a Simulator
# In Simulator: File ▸ Save Screen  (⌘S)  → saves a correctly-sized PNG
```

Suggested shots (the app's strengths): Dashboard grid · A page with handwriting +
highlighter · A flowchart with connectors · Shapes with fill/opacity · Export sheet.

> Tip: add captions in a design tool, but Apple also accepts raw device screenshots.

---

## 7. App Store Connect metadata

On the app's **1.0 version** page fill in:

| Field | Suggested value |
|-------|-----------------|
| **Name** | NotePad — Paper Notebook (≤ 30 chars, unique) |
| **Subtitle** | Apple Pencil notes & flowcharts (≤ 30 chars) |
| **Category** | Primary: **Productivity** · Secondary: Utilities |
| **Description** | See suggested copy below |
| **Keywords** | `notes,notebook,apple pencil,handwriting,drawing,flowchart,pdf,sketch,ipad,journal` (≤ 100 chars) |
| **Promotional text** | "Write, draw, and diagram naturally on your iPad." |
| **Support URL** | A page you control (e.g. GitHub repo or site) |
| **Marketing URL** | Optional |
| **Privacy Policy URL** | Required — see [§8](#8-app-privacy) |
| **Copyright** | `2026 Alfred Ang` |
| **Price** | Free (or set a tier) |

**Suggested description:**

```
NotePad turns your iPad into a clean, distraction-free paper notebook.

• Write and draw naturally with Apple Pencil — pressure, tilt, and low latency
• Pen, highlighter, and pixel/object erasers with a full color palette
• Add shapes and build flowcharts with connectors that snap to nodes
• Organize work into notebooks and nested sub-notebooks
• Continuous A4 pages with pinch-to-zoom and two-finger pan
• Everything saves automatically — fully offline, no account needed
• Export any page to PNG, JPG, or PDF, or a whole notebook to PDF

Fast, native, and private. Your notes stay on your device.
```

---

## 8. App Privacy

NotePad is **local-first and offline** — it collects no data, has no analytics, no
accounts, no network calls.

In App Store Connect → **App Privacy**:
- **Data Collection: "No, we do not collect data from this app."**
- This still requires a **Privacy Policy URL**. A minimal policy stating "This app
  does not collect, store, or transmit any personal data; all notes remain on your
  device" is sufficient. Host it anywhere you control (GitHub Pages works).

---

## 9. Export compliance

Already handled: `App/Info.plist` sets

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

so you won't be asked the encryption question on each upload. (The app uses no
custom or non-exempt encryption.)

---

## 10. TestFlight (recommended before release)

1. After the build finishes processing, go to **TestFlight**.
2. Provide **Test Information** (what to test, contact email).
3. Add yourself as an **Internal Tester** → install via the TestFlight app on iPad.
4. Verify: drawing, palm rejection, zoom/pan, shapes/flowcharts, autosave across
   relaunch, and export.

---

## 11. Submit for review

1. On the version page, under **Build**, click **+** and select the processed build.
2. Set **Age Rating** (questionnaire — NotePad is **4+**: no objectionable content).
3. Choose release option: **Automatically** on approval, or **Manually**.
4. Click **Add for Review** → **Submit for Review**.
5. Status flows: *Waiting for Review → In Review → Pending Developer Release /
   Ready for Sale*. First reviews typically take 24–48 hours.

---

## 12. Common rejection reasons (and how this app avoids them)

| Reason | Mitigation |
|--------|------------|
| Crashes / bugs on review device | Test thoroughly on TestFlight first |
| Missing/incorrect privacy info | "Data not collected" + privacy policy URL ([§8](#8-app-privacy)) |
| Icon has alpha / rounded corners | Icon is generated flat with **no alpha** ([§1](#1-assets-checklist)) |
| Screenshots wrong size | Use the **13" iPad** sizes in [§6](#6-screenshots) |
| Placeholder / incomplete metadata | Fill every required field in [§7](#7-app-store-connect-metadata) |
| "App is not useful enough" (4.2) | Highlight handwriting, shapes, flowcharts, export in screenshots/description |

---

## Quick reference

```bash
# Regenerate the project
xcodegen generate

# Regenerate the app icon
swift scripts/generate_icon.swift

# Archive from the command line
xcodebuild -project NotePadApp.xcodeproj -scheme NotePadApp -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/NotePad.xcarchive archive
```

Bundle ID: `com.notepad.app` · Min OS: iPadOS 18.0 · Device family: iPad only.
