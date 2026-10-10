# Custom notebook folders

Issue: [5](https://github.com/SamarthaB10/Personal-Note-app-for-iPad/issues/5).

The library has Unfiled and custom folders at one level. Each folder has a stable ID, its own notebook grid, and a notebook count. Create Folder checks empty, duplicate, reserved, and multiline names. Create Notebook uses the selected folder and opens seven blank pages. Move is available on a notebook card and inside an open notebook. Home saves first, then reads current membership and returns to that folder. Folders returns to the folder list.

Old indexes decode with no custom folders and revision zero. Old Unfiled identities remain unchanged. Folder creation and notebook moves use the FIFO index permit. All index writers retain the folder list and advance the revision. Atomic replacement checks the previous disk revision. A folder move changes membership only; page files, ink, text, paper, and cover files stay in place. A failed write preserves the old membership and shows an error.

## Checks

- Mandatory instruction discovery found the global and project AGENTS.md files. Both were read. No parent or nested guide was found. The same original checkout is used.
- `xcode-select -p`: `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -version`: Xcode 27.0, build 27A266a.
- `git apply --check /private/tmp/ipad-notes-issue5-folders-draft/issue5-folders.patch`: passed before integration.
- `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.0-simulator -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk prototypes/CanvasPrototype/CanvasPrototype/*.swift`: passed, exit 0, after folder integration.
- `python3 /private/tmp/ipad-notes-issue4-build.py`: signed physical build passed, exit 0. The helper runs `xcodebuild -quiet -project prototypes/CanvasPrototype/CanvasPrototype.xcodeproj -scheme CanvasPrototype -destination id=<device> -derivedDataPath /private/tmp/CanvasPrototypeSignedBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<team> -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`. Device and team values stay private.

The first source-review worker stopped at the account usage limit without a report. This is not a pass. A fresh round-2 Standards and Spec review found no errors. `python3 /private/tmp/ipad-notes-issue4-device.py install` passed with exit 0 for this folder build. The launch helper failed with exit 1 because iPadOS reported the device as locked. Screenshot capture returned exit 0, but it does not establish app behavior. Physical create, move, Home, folder-list return, and offline restart checks remain pending. Earlier issue 2 and issue 3 passes remain recorded results.

No unit or integration tests were written or run. No dependency, database, note cloud service, paid service, or production deployment was added. GitHub was used to read the assigned issues. Trash and deletion are separate issue 11 work. PDF and image import and export remain separate issue 9 and issue 10 work.
