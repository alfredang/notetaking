# App Store Submission — NotePad

Status: **build uploaded & attached; metadata set via API. Two web-UI steps remain
before Submit for Review** (App Privacy publish + the Submit button). See §3.

## 1. App identity

| Field | Value |
|---|---|
| App name | Tertiary NotePad |
| App ID (ASC) | `6779909944` |
| Bundle ID | `com.tertiaryinfotech.notepadapp` |
| iCloud container | `iCloud.com.tertiaryinfotech.notepadapp` |
| Team | Alfred Ang — `GU9WTSTX9M` (App Store Connect: Chew Hoe Ang) |
| Platform | iPadOS 18+ (iPad only — `TARGETED_DEVICE_FAMILY = 2`) |
| Version / Build | 1.0 / 2 (build 2 VALID + attached; build 1 expired) |
| Category | Productivity (secondary: Education) |
| Price | Free ($0.00) — set via API |

## 2. Pre-submission checklist (code) — done

- [x] App icon 1024×1024 (no alpha) in `Assets.xcassets/AppIcon`.
- [x] `CFBundleShortVersionString` 1.0, `CFBundleVersion` 1.
- [x] `ITSAppUsesNonExemptEncryption = false` (no export-compliance prompt).
- [x] `NSMicrophoneUsageDescription` (audio notes).
- [x] `UIRequiredDeviceCapabilities = arm64` (was the invalid `armv7`).
- [x] **Privacy manifest** `Resources/PrivacyInfo.xcprivacy` — no tracking, no data
      collected; required-reason APIs declared (UserDefaults, file timestamp, disk space).
- [x] **Per-config entitlements**: Debug → `aps-environment = development`,
      Release → `production` (CloudKit Production for App Store builds).
- [x] iPad-only orientations + multiple scenes + pointer/indirect input.

## 3. Submission status

### Done via App Store Connect API (no UI needed) ✅
- App record created (`6779909944`), category Productivity, price Free.
- Build 2 uploaded, processed VALID, and attached to v1.0. Build 1 expired.
- Description, subtitle, promo text, keywords, support/marketing URLs — set.
- **Privacy policy URL** → `https://www.tertiaryinfotech.com` — set.
- **Copyright** → `2026 Tertiary Infotech Academy Pte Ltd` — set.
- **App Review contact** (Alfred Ang, angch@tertiaryinfotech.com, no demo account
  needed) — created.
- iPad 12.9" screenshots uploaded (2).

### Must be done in the web UI — Apple's API can't do these ⚠️
These are hard limitations of Apple's public API, not optional. ~5 minutes total at
<https://appstoreconnect.apple.com> → **Apps → Tertiary NotePad**:

1. **App Privacy → "Data Not Collected" → Publish.** App Privacy ("nutrition label")
   is **not writable via any public API** — it must be set in the UI. Click **App
   Privacy** (left sidebar) → **Get Started** → answer **"No, we do not collect data
   from this app"** → **Publish**. (Matches `PrivacyInfo.xcprivacy`: no tracking, no
   collected data.)

2. **Submit for Review.** Open the **1.0 Prepare for Submission** version →
   **Add for Review** / **Submit for Review**. The version's build, metadata,
   screenshots, pricing and review contact are already filled in.
   - Note on screenshots: the **API** validator spuriously demands an iPhone 6.5"
     screenshot even though the binary is iPad-only (`UIDeviceFamily = 2`). The
     **web UI** only shows the iPad screenshot slot for an iPad-only app, so Submit
     there should not ask for iPhone shots. If it ever does, that means a non–iPad
     build leaked in — re-check `TARGETED_DEVICE_FAMILY`.

3. **CloudKit — deploy schema to Production.** In the CloudKit Console for
   `iCloud.com.tertiaryinfotech.notepadapp`, **Deploy Schema Changes** from
   Development → Production. App Store builds use the Production environment; sync
   will fail for shipped users if the schema isn't deployed. (Do this before/with
   submission.)

4. **Encryption**: already answered via `ITSAppUsesNonExemptEncryption = false` — no
   action needed.

## 4. Build & upload

```bash
xcodegen generate
# Archive a Release build in Xcode (Product ▸ Archive) with automatic signing,
# then Distribute App ▸ App Store Connect ▸ Upload.
```
Verify in the Organizer that the archive's entitlements show
`aps-environment = production`.

## 5. Screenshots (required)

App Store requires iPad screenshots at **13" (2064 × 2752)** and optionally
**11"**. Capture on device (Top + Volume Up) and upload 3–5:
1. Editor with handwriting + a flowchart (white paper).
2. Blackboard template with notes.
3. Notebook dashboard with tagged notebooks.
4. PDF annotation.
5. Sidebar page thumbnails / multi-select.

(Drop the same images into `docs/screenshots/editor.png` and `dashboard.png` to
refresh the README.)

## 6. Metadata (paste into App Store Connect)

**Subtitle (30 chars):** Apple Pencil notes & flowcharts

**Promotional text:** A fast, native iPad notebook for Apple Pencil — handwriting,
shapes, flowcharts, PDF markup, and blackboard mode, synced with iCloud.

**Description:**
```
NotePad is a clean, native iPad note-taking app built for Apple Pencil. It feels
like a paper notebook with the power of digital ink.

• Handwriting with pressure & tilt, low latency, and palm rejection — the Pencil
  draws while a finger scrolls and two fingers zoom.
• GoodNotes-style tool bar: pen, highlighter, erasers, color dropdown and widths.
• White paper or blackboard templates, applied across the whole notebook.
• Shapes and flowcharts (process, decision, start/end, connectors) with editable
  vector overlays; connectors re-route when you move a node.
• Type directly into sticky notes and flowchart nodes (multi-line, with background
  colors).
• Lasso to move, delete or copy multiple strokes; recolor and edit shapes.
• Import PDFs and annotate them; export pages or whole notebooks to PDF/PNG/JPG.
• Organize with nested notebooks and tags, and search inside your handwriting.
• Record voice memos per notebook.
• Everything syncs across your devices with iCloud.

Powered by Tertiary Infotech Academy Pte Ltd.
```

**Keywords:** notes,handwriting,apple pencil,notebook,flowchart,pdf,annotate,
blackboard,ipad,drawing,study,diagram

**Support URL:** https://www.tertiaryinfotech.com
**Marketing URL (optional):** https://www.tertiaryinfotech.com

## 7. Known follow-ups (not blockers)

- Live collaboration (current sharing is file-based `.notebook`).
- Lined / grid paper templates.
- Handwriting-to-text conversion.
