# TiqianUI — Apple (SwiftUI / AppKit / UIKit) frontend

The Apple peer of [`frontend/compose`](../compose): a reusable Swift Package that vends
content-agnostic views over the Tiqian CJK typesetting engine, so apps consume a component instead
of copying view code.

> **Scope: macOS 14+ and iOS 15+ read-only frontend.** The generated Swift engine, the Core Text
> pipeline and the views build from source for macOS and iOS (ADR 0064). `CJKText` uses
> `NSViewRepresentable` on macOS and `UIViewRepresentable` on iOS. Both preserve source text for
> selection and accessibility; clipboard text follows the Web frontend's annotation projection.
> Editor / IME remains a separate follow-up.

- **`CJKTextView`** — the native AppKit/UIKit scrolling view (`NSScrollView` / `UIScrollView`). It
  takes the same `[CJKBlock]` content on both platforms and can be embedded without SwiftUI.
- **`CJKText`** — the thin SwiftUI bridge (`NSViewRepresentable` / `UIViewRepresentable`) over
  `CJKTextView`. It takes `[CJKBlock]` content authored as native `AttributedString`, lays out at the viewport
  width, and scrolls. Rotation and split-view width changes reuse the lowered document builder and
  only rerun line breaking when the whole-character column changes. It knows nothing about *what*
  the content is (the analogue of Compose's `CjkText`). Selection and hit testing consume engine
  `LayoutQueries`: iOS delegates gestures, handles and the edit menu to non-editable
  `UITextInteraction`; macOS uses AppKit mouse/responder actions and `NSPasteboard`.
- Depends on two sibling packages: `../engine` (`TiqianEngine`, the Swift engine boring generates from
  `engine-haxe/src`) and `../shaping` (`TiqianCoreText`, the Core Text shaper and font metrics). The
  internal `Tiqian` module holds the Core Text renderer and the document facade. Consumers only
  `import TiqianUI` to reach `CJKTextView` / `CJKText` + the `CJKBlock` / `AttributedString` authoring
  API; engine and facade types stay internal to the package.

Native word selection delegates semantic word expansion to Apple's simplified-Chinese
`NLTokenizer`; caret and selection geometry remain engine-owned. Ruby annotations carry their own
language: `.bopomofo(...)` uses `zh-TW` without changing the base paragraph's `zh-Hans` locale or
mainland-horizontal profile.

Native `AttributedString.link` runs keep Apple's authoring syntax. They are lowered to exact source
ranges, while hit testing and underline geometry come from the engine's placed glyphs. `CJKText`
dispatches through SwiftUI's `OpenURLAction`; `CJKTextView.onOpenURL` provides the AppKit/UIKit hook
and otherwise opens the URL with the platform default. A selection drag does not activate a link.

```swift
var clreq = AttributedString("中文排版需求")
clreq.link = URL(string: "https://www.w3.org/TR/clreq/")!

CJKText([.paragraph(clreq)], fontSize: 18)
```

Pagination is **not** here — that is the [pageflow](https://github.com/tiqian-cjk/pageflow) engine's
job; the reading view will *consume* pageflow's page model.

iOS 15 is the natural lower bound because native Swift `AttributedString` is part of the authoring
contract. Supporting iOS 12 would require a separate `NSAttributedString`/plain-text surface and a
pre-`UITextInteraction` selection implementation, rather than a deployment-target change.

UIKit and AppKit use the same native API:

```swift
let textView = CJKTextView([
    .paragraph(AttributedString("中文正文")),
], fontSize: 18)

textView.setContent(updatedBlocks, fontSize: 20)
```

## Build

`../engine/Sources/TiqianEngine` is a symlink to the gitignored `engine-haxe/out/swift-f32/gen`.
Generate the engine once per engine change, from the repository root:

```shell
nix develop -c boring gen swift-f32 --project boring.json
```

Then build this package with `swift build`, or let any Xcode project or SwiftPM target depend on
this local package and `import TiqianUI`. Gradle, the JDK and the Android SDK are not involved.
The bundled demo (`demo/apple`) does exactly that, with macOS and iOS targets in one Xcode project.

The views have native runtime coverage for layout, Core Text drawing, width reflow, scroll content
size, source-faithful accessibility text, safe UTF-16 selection geometry, clipboard projection and
native-link routing:

```shell
xcodebuild test -scheme TiqianUI \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

xcodebuild test -scheme TiqianUI \
  -destination 'platform=macOS,arch=arm64'
```
