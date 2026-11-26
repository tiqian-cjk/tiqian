# TiqianDemo — Apple Core Text demo

The Apple-side counterpart to the Compose demo (`runComposeDemo`): one native Xcode project with
macOS and iOS targets. Both targets share the same Swift sample content and drive the same Core Text
frontend. The gallery exercises 中西自动间距, 避头尾,
标点挤压, 两端对齐, rich text (字重/斜体/颜色/字号/字体族), 列表, 段落缩进, 拼音 ruby,
注音 (ㄅㄆㄇ), 西文音节断词, 原生 `AttributedString.link`, and 着重号/专名号/书名号/示亡号.

## Layout

```
platforms/apple/engine/     SwiftPM wrapper of the Swift engine boring generates (TiqianEngine).
platforms/apple/shaping/    Core Text shaping and font-metrics adapter (TiqianCoreText).
platforms/apple/frontend/   Renderer, document facade (Tiqian) and the TiqianUI Swift Package.
demo/apple/                      One Xcode project; shared sources, macOS target and iOS target.
```

The app owns the **content**; `TiqianUI` owns the **view**; the generated engine (`TiqianEngine`)
owns typesetting and the `Tiqian` module owns Core Text drawing. Pagination is not here — that is the pageflow engine's job.

## Run it

```sh
(cd ../.. && nix develop -c boring gen swift-f32 --project boring.json)
open TiqianDemo.xcodeproj
```

Select `TiqianDemo` for macOS or `TiqianDemo-iOS` for an iPhone/iPad destination. The iOS target uses
the same source files rather than a second demo implementation. Pick a sample, resize or rotate the
viewport, change the font size, and exercise native selection/copy on long text.
The 链接 sample also exercises engine-owned link geometry and platform URL opening.

## The integration, in a nutshell

```swift
import TiqianUI   // vends CJKText + the CJKBlock / AttributedString authoring API

// Content is native AttributedString grouped into [CJKBlock]; CJKText typesets + scrolls it.
CJKText([
    .paragraph(AttributedString("标题").styled(size: 28, bold: true), indent: .flush),
    .paragraph(AttributedString("诸位好。我叫")
        + AttributedString("提椠").ruby("tíqiàn")
        + AttributedString("。")),
    .list([AttributedString("第一条"), AttributedString("第二条")], marker: .cjkNumber),
], fontSize: 18)
```

Under the hood `CJKText` handles the native viewport, coordinate conversion and Core Graphics
context boundary. The renderer inherits the current platform text color while authored color spans
override individual source ranges.

## Scope (honest)

Draws base glyphs + rich-text spans (weight/italic/color/size/family) + 拼音/注音 annotation
glyphs + 着重号 dots + 专名号/书名号/示亡号 lines; 书名号 uses the same wavy geometry as Compose.
macOS and iOS both support source-faithful read-only selection/accessibility, Web-compatible ruby
clipboard projection, and native link activation. Editing, IME and vertical text remain outside the
current scope. The engine sources under `engine-haxe/out/swift-f32/gen` are a regenerable, gitignored
build artifact produced by `boring gen swift-f32`.
