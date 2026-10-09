# Free notes on one iPad

Research date: 9 October 2026. Sources: Apple, WebKit, W3C, and the Saber project. Prices below are from the US App Store or Apple US pages.

## Your requirements

The app must support smooth Apple Pencil handwriting and typed notes. It must use native iOS/iPadOS tools. Notes must stay on your iPad. There must be no app fee, subscription, paid API, paid server, or paid developer membership. This report proposes a design. It does not implement an app.

## Main result

**Free options exist. Apple Notes is the closest existing match. For a custom app, use SwiftUI, PencilKit, UIKit, and local files. The main constraint is installation, not the cost of these tools.**

Apple allows a free developer account to test apps on personal devices. But a free Personal Team profile expires after seven days. Apple says to rebuild and reinstall the app after expiry. Thus, a custom standalone app can cost no money, but it needs regular maintenance. The standard Apple Developer Program is $99 per year, so it does not meet your requirement. [Free Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account), [Apple program price](https://developer.apple.com/programs/).

## Existing options

### Apple Notes: first app to try

Apple lists Notes as Free. It supports typed text, Apple Pencil drawing, folders, handwriting search, and lines or grids. These features make it a useful reference for our app. [Apple Notes listing](https://apps.apple.com/us/app/notes/id1110145109).

Enable **Settings → Apps → Notes → “On My iPad” Account**. Create notes in that account. Apple states that these notes appear only on the iPad. However, Apple also states that they are included in iCloud device backups. Local storage does not, by itself, stop cloud backup. [Notes account settings](https://support.apple.com/en-gb/guide/ipad/ipad368e8d09/ipados).

For strict device-only storage, inspect the device's iCloud Backup settings too. Apple permits you to exclude many apps from backup, but some apps cannot be excluded. Do not assume Notes has a separate backup switch on your device. If needed, disable iCloud Backup for the device after you review the effect on other data. No settings were changed during this research. [Apple backup controls](https://support.apple.com/en-gb/108922).

### Saber: free open-source reference

Saber is a handwriting app. Its US App Store listing is Free and supports iPadOS 15 or later. Its source uses Flutter and Dart, with a GPL-3.0 license. It runs as an iPad app, but its UI stack is cross-platform. It does not meet a strict requirement to use Apple's native UI tools. [Saber listing](https://apps.apple.com/us/app/saber-handwritten-notes/id1671523739), [Saber source](https://github.com/saber-notes/saber).

Saber's own policy states that cloud storage is optional and is not needed for the app to function. Error reporting is opt-in, and ads were removed in September 2024. For local use, do not enable cloud sync or error reporting. Also inspect the device backup settings. Its smoothness and palm handling were not tested on your iPad. [Saber privacy policy](https://github.com/saber-notes/saber/blob/main/privacy_policy.md).

This is useful evidence that a free personal handwriting app is practical. It is also a source reference if we need to study notebook or page behavior. We should not copy its code without first checking its license obligations.

## Proposed custom app

Use only Apple's frameworks. No third-party runtime, account system, server, analytics, or cloud sync is needed in this proposed design.

- **SwiftUI:** notebook list, note list, title controls, and settings.
- **PencilKit:** handwriting canvas and drawing tools. Apple provides low-latency input, erasing, and line selection through `PKCanvasView` and `PKDrawing`. Apple uses PencilKit in Notes. This is the strongest technical fit for smooth handwriting. [PencilKit documentation](https://developer.apple.com/documentation/PencilKit?language=objc), [Apple PencilKit presentation](https://developer.apple.com/videos/play/wwdc2019/221/).
- **UIKit `UITextView`:** native keyboard entry and editable multiline text. It can support rich text if we later need it. [UITextView documentation](https://developer.apple.com/documentation/uikit/uitextview?changes=latest_major_3___1&language=objc).
- **Local files:** one folder per note, with title/date metadata, text, and drawing data. `PKDrawing.dataRepresentation()` contains the complete drawing, so ink stays editable. [Drawing data API](https://developer.apple.com/documentation/pencilkit/pkdrawing-swift.struct/datarepresentation%28%29?changes=_3__3).

For the first version, place a typed text section above a handwriting section in each note. This permits both input types in one note with a small data model. Arbitrary text boxes over ink, automatic text reflow around drawings, and PDF annotation are separate features. PencilKit does not supply that full document editor for us.

**Example:** open “Study”, create “Chapter 3”, type a short heading and summary, then write equations below it with Apple Pencil. Use the system pen, highlighter, eraser, and selection tools. Save changes automatically. Reopen the note without internet access. Export an editable copy or a PDF to **On My iPad**, rather than iCloud Drive, when requested.

Use Pencil-only drawing mode so finger input does not become ink. Apple provides a drawing policy for this distinction. Palm rejection, scrolling, undo, keyboard movement, save recovery, and long-note performance still need checks on your real iPad. Native tools reduce this work; they do not prove the completed app will be smooth. [PencilKit drawing policy](https://developer.apple.com/videos/play/wwdc2020/10107/).

## Free ways to run our app

**Xcode on an existing compatible Mac:** build and install using a free Personal Team. Apple limits this to three apps per device, three registered devices, and ten App IDs. Profiles expire after seven days. This is the documented route for a standalone app without a paid membership. It still uses Apple signing services during installation. Offline note use is a separate requirement. [Apple account limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

**Swift Playground on the iPad:** Apple provides this tool for free. It can run an app playground full screen in its own window. This is a useful native prototype route without a Mac purchase or weekly Xcode installation. It is an app run through Swift Playground, not evidence of a separate installed app with its own Home Screen icon. Local file retention across runs, project changes, and app updates must be verified before using it for important notes. Keep the project out of iCloud Drive for device-only use. [Free Swift Playground](https://developer.apple.com/swift-playground/?contentId=com.apple.playgrounds.getstartedwithapps), [Run an app playground](https://support.apple.com/guide/playgrounds-ipad/run-your-app-itc650868b1f/ipados).

For either route, inspect backup settings. Apple's `isExcludedFromBackup` documentation warns that the flag is for support/cache files and should not be used on user documents. Do not use that flag as a promise that notes can never enter a backup. [Apple backup flag](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup?changes=l__8).

## Why a web app is not the recommendation

A Home Screen web app can use browser storage offline and does not need native app signing. But it fails your native-tool requirement. WebKit storage is best-effort by default and can be deleted under storage pressure or other conditions. A persistent-storage request can help, but approval depends on browser rules. [WebKit storage policy](https://webkit.org/blog/14403/updates-to-storage-policy/).

The Pointer Events standard supplies pen type, pressure, and tilt where supported. It does not promise Apple PencilKit behavior or equal handwriting quality. A browser drawing editor would require its own ink and gesture work. [W3C Pointer Events](https://www.w3.org/TR/pointerevents2/).

## Recommendation and checks before a build

Try Apple Notes with On My iPad first. For a custom native app, build a small SwiftUI/PencilKit/UITextView prototype with local files. Use Swift Playground if running through its editor is acceptable. Use Xcode Personal Team if you need a standalone app and accept the seven-day install cycle.

Confirm the iPad model, iPadOS version, Pencil model, and compatible Mac access. Then confirm which free run method is acceptable. These facts affect tool support and installation. No paid backend is required by the proposed design.

No app was built, installed, or tested. Public websites were used for research. No database, private cloud account, deployment, or device settings were used or changed. Only this research file was added.

Research file checks:

- `cat /Users/samarthab/.codex/AGENTS.md /Users/samarthab/.agents/skills/research/SKILL.md`: read both instruction files.
- `git status --short --branch`: before the edit, the repository had no commits and no file changes. After the edit, only the new `docs/` directory was untracked.
- `git diff --check`: passed for tracked files. The report is untracked, so this command does not check its content. The report was checked manually for the requested scope and source links.

The parent task completed repository instruction discovery before delegation. No application checks were run because there is no application code in this repository.
