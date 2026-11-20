# Allude

**English** · [简体中文](README.zh-CN.md)

An iOS app that collects parcel pickup codes. **Data stays on your device — no
networking, no uploads, no account.**

Preparing for App Store release. The source in this repository is the whole app;
build it yourself and check that nothing leaves the device.

---

## What it is

Allude pulls the pickup code out of a delivery SMS, files it under the right
pickup point, and shows it on a widget and in Live Activities.

Parsing is rule-based first: four independent regular-expression families behind a
priority chain, tuned against a corpus of real (anonymized) SMS with a regression
baseline you can re-run. When a rule set misses a field, Apple's on-device model is
asked to fill that gap — it never overrides what the rules already found, and if
the model is unavailable the app simply falls back to rules.

- SwiftUI, iOS 17 and later. Plain Xcode project, **no third-party dependencies, no SPM packages**
- Only network activity: StoreKit (Apple only) and optional iCloud sync into **your own** iCloud
- No developer server, no third-party SDK, no API keys

## Build

```bash
cd Allude
xcodebuild -project Allude.xcodeproj -scheme Allude \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/allude-verify build \
  CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-disable-sandbox"
```

`-disable-sandbox` exists so the macro plugin (`swift-plugin-server`) can spawn its
helper process. Without it, under a sandboxed build, you get a batch of *bogus*
errors (typically `'self' is immutable` in `SwipeActionRow.swift`). It is a toolchain
workaround, not a code fix.

## What's in the repository (development history)

| File | Contents |
|---|---|
| `AGENTS.md` | Project instructions: hard rules, layout, type scale, icon specs, release pipeline, module conventions |
| `交接说明_dsh.md` | Full handover document: measured status, three-level directory layout, file map by importance, known issues |
| `交接说明_workbuddy.md` | An earlier handover record |
| `快递短信解析规格_V803.md` | Parser spec: priority chain, three mis-parse gates, field conventions |
| `短信语料库_v1.md` | 514 real parcel SMS segments used as the regression corpus |
| `iPhone Duo 适配规范_v1.md`, `iPhone Duo 官方设计规范笔记_v1.md` | Foldable design notes and Apple Tech Talks summary |
| `产品与商业模式规格_v1.md` | Product scope and functional boundaries |
| `.workbuddy/memory/*.md` | Day-by-day development log: decisions, mistakes, reasons |
| `tools/` | Self-check harnesses: parser regression, station matching, brand table, dedupe, OCR pipeline, unit assertions |

Each harness's `main.swift` header lists the exact compile command. Example:

```bash
# Parser regression against the full corpus (baseline: 193/514 codes, 192/514 addresses)
swiftc -O -o /tmp/parser-regression \
  Allude/Allude/Models/PickupParser.swift tools/parser-regression/main.swift && \
/tmp/parser-regression 短信语料库_v1.md
```

## What is *not* in the repository

- **No IPA**, no build products (`build/`, `DerivedData/`), no provisioning profiles
- **No signing keys** (`tools/license-gen/private-key.pem` is git-ignored)
- No bundled binaries of other apps

Shipping builds go one way: Xcode Archive → App Store Connect.

## Credits

极客ZHANG · zhang_wangning@126.com

Third-party marks (courier and pickup-point logos) are used only to identify where a
parcel is waiting. Copyright remains with each brand; no partnership or endorsement
is implied.
