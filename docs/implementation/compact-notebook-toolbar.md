# Compact notebook toolbar

Samartha supplied an app screenshot on 10 October 2026 and requested one compact row of icons below a separate notebook name. The [accepted design](../design/notes-app.md#accepted-compact-notebook-header-on-10-october-2026) records the request.

The previous layout had three sections: folder/export, page controls, and writing tools. The normal control rows alone required at least 144 points. The notebook now has its name on a separate top line and one 44-point toolbar. All action labels are icons. Menu options and accessibility labels retain words. The zoom percentage is a small numeric readout. Narrow windows scroll the same row horizontally.

Home, page Delete confirmation, page choice, the Add Page/Import PDF menu, direct Import from Files, both PDF export scopes, the six tool groups, paper, and appearance remain available. Undo, selection settings, and Finish typing are icons when applicable. Tool settings still use the same native hold-before-tap recognizers. No page content, gesture logic, storage, or PDF rendering code changed.

The export control now lives in the shared toolbar. Its position and view identity remain stable during page changes. Its rendering/cancellation task, temporary artifact, native Files sheet, and failure alert remain in that control. Rendering shows a spinner over its icon; status remains available through its accessibility value. Import and navigation messages appear below the toolbar, so the title stays at the top.

## Diagnosis and review

The supplied screenshot directly demonstrates the extra rows. The source confirms separate stacked controls. This is a layout request with a known cause, so a runtime failure loop, ranked fault hypotheses, and regression tests were not needed. Samartha forbids unit/integration tests and subagents. No test or subagent was used.

The pre-change fixed point is `8b08dc9`. The `code-review` skill was applied directly in two separate passes using the current user request as the spec and the global/project guides as standards. Standards: no findings in the checked changes. Spec: no findings in the checked changes. The review checked accessible names, icon-only action labels, one toolbar row, top title, retained menu actions, native tool controls, export state lifetime, and existing Delete/input/save guards. A source review does not prove physical input behavior.

## Checks

- `xcode-select -p`: `/Applications/Xcode.app/Contents/Developer`.
- `xcodebuild -version`: Xcode 27.0, build 27A266a.
- `xcrun swiftc -typecheck -swift-version 5 -warnings-as-errors -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk -target arm64-apple-ios26.0-simulator -module-cache-path /private/tmp/ipad-notes-main-module-cache prototypes/CanvasPrototype/CanvasPrototype/*.swift`: first and final passes, exit 0.
- `python3 /private/tmp/ipad-notes-issue4-build.py`: signed incremental physical build, exit 0. The inspected helper uses project `CanvasPrototype.xcodeproj`, scheme `CanvasPrototype`, SDK 27, deployment 26.0, and the existing free Personal Team.
- `python3 /private/tmp/ipad-notes-issue4-device.py install`: exit 0. The bundle stays `com.samarthab.CanvasPrototype`. No uninstall or data erase was used.
- `python3 /private/tmp/ipad-notes-issue4-device.py launch`: exit 0.
- `python3 /private/tmp/ipad-notes-issue4-device.py capture`: exit 0; that first capture showed the Home screen.
- `xcrun devicectl device process launch --device <private device> com.samarthab.CanvasPrototype --timeout 30 --activate`: exit 0. The existing process was activated without termination. The device argument is redacted here.
- `xcrun devicectl device capture screenshot --device <private device> --destination /private/tmp/ipad-notes-compact-toolbar-physical.png --timeout 30`: exit 0. The actual capture shows notebook Test with the name on its own top line and all control icons in one row. The existing PDF and added ink are visible. This establishes the displayed layout, not all action or Pencil checks.
- `git diff --check`: passed.
- `git diff --no-index --check /dev/null docs/implementation/compact-notebook-toolbar.md`: no whitespace errors; exit 1 reflects new content.
- A Python local-link check on the accepted design, this record, and prototype README found no missing targets.
- T3 `device_list` listed iOS simulators only. Android was unavailable because its SDK was absent. The physical update used the existing inspected platform helper.

Required manual checks are a single icon row with the name above it, Pages and Add menus, Import and Export native Files controls, Delete/Cancel, tool taps and holds, typing completion, light/dark appearance, and a narrow window. Physical Pencil quality and complete import/export/recovery checks remain subject to the prior feature records. No real note was deleted by automation.

The captured layout check passed in the notebook on the physical iPad. Native menu actions, press-and-hold behavior, both appearances, and narrow-window behavior were not newly reported as passed.

No new dependency, database, note cloud service, or production deployment was used. Lucide metadata and public Lucide SVG paths on GitHub were read for the icons. Private signing and device values stay out of this record. Screenshots stay outside the repository.
