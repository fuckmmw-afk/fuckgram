# Articles backport onto Telegram-iOS 11.15

## Baseline

- Official Telegram-iOS **11.15** commit `b1ebdab0dc3ae29dfda266f4bba0780bc842e73d` (API layer 214, Xcode 16.2).
- Rich-text source snapshot: official **release-12.9.2** `6ad963e5b62d354da79040f388ae2b9132fb17b8` (API layer 228).
- Binary evidence: `telegram_12.9.3.ipa` (12.9.3 / 34622, `ph.telegra.Telegraph`). No public 12.9.3 tag; 12.9.2 is the nearest public source. IPA-only conclusions are marked below.
- Product IPA sample: `siftgram_11.15.ipa` (11.15 / 242, `app.swiftgram.ios`). Swiftgram/TGExtra dylibs are **not** part of this feature.

## Evidence (IPA)

| Item | 11.15 | 12.9.3 |
|---|---|---|
| `LC_ENCRYPTION_INFO_64` cryptid | 0 | 0 |
| `RichTextAttachmentScreen` / editor classes | absent | present in `TelegramUIFramework` |
| `RichTextEditorUIKitResources.bundle` | absent | present |
| `Chat/Attach Menu/Article` | absent | present (binary path string) |
| Injected dylibs (`Lead.dylib`, `zxPluginsInject`, …) | present in sample IPA | present; **not ported** |

## What was ported

- TelegramApi generated schema **layer 228** (12.9.2 `Api0…Api42`, `Cons_*` constructors).
- TelegramCore 12.9.2: `ChatInputContent`, `RichTextMessageAttribute`, InstantPage V2 models, rich upload/edit/draft, `getRichMessage` / `requestFullRichText`.
- Postbox typing-draft views required by Core 12.9.2.
- InstantPageUI V2 renderer (formulas fall back to monospaced LaTeX; SwiftMath was not vendored).
- `RichTextEditorCore` / `RichTextEditorUIKit` / media / conversion / attachment screen / composer bridges / rich bubble.
- Attachment-menu **Article** entry using 11.15 `AttachmentUI` primitives (no 12.9 AttachmentUI / Liquid Glass chrome).
- 11.15-styled adapters for `GlassBackgroundComponent` / `EdgeEffect` (no iOS 26 `UIGlassEffect`).

## What was not ported

- Global Liquid Glass UI, 12.9 `TelegramUIFramework` binary, full `AttachmentUI` 12.9, Assets.car / lproj from 12.9.
- Injected dylibs, stories/gifts/ads/calls unrelated deltas.
- Native rich composer as the default chat input (11.15 input panel kept). Article authoring is the attachment-menu editor. `ChatRichTextInputNode` is in-tree for a later panel hook.
- People Nearby engine was restored against layer 228 `Cons_*` constructors; live nearby updates from `AccountStateManager` are not re-streamed. `PreferencesKeys.peersNearby` (value 21) is kept from 11.15 because 12.9.2 dropped the public key while Core still writes it.

## Feature flag

`ArticlesFeature.isEnabled` (default `true`). Disable with `UserDefaults` key `articles.enabled` = `false`. Ordinary send/receive does not go through the article editor.

## Build

GitHub Actions on `article-backport-11.15` produces **unsigned** `Telegram-11.15-articles-unsigned.ipa` via official `fake-codesigning` profiles (ExpirationDate 2029). Device IPA **must** keep those profiles attached: `--disableProvisioningProfiles` makes `rules_apple` fail with `provisioning_profile` unset (Build #7). Runner: macOS 15 / Xcode 16.4 (16.2 on `macos-15` has no iPhoneOS SDK). Not installable on stock iOS without a later signature.

Metadata written next to the IPA: source SHA, build date, layer 228.
