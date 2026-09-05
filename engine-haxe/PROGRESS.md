# 阶段 A 执行记录

状态：阶段 A 与阶段 B 均完成。

## 类级记录

- `TraceFormat`：完成 trace 数字、控制字符和确定性文本格式化；TextRange golden 对照通过。
- `TraceRecorder`：完成事件、原始行和文本累积记录功能。
- `TestTraceStore`：完成按类收集、按测试名排序和完整 class 文本输出。
- `TestTraceRecorder`：完成 section、record、flush 和 Haxe 输出路径设置。
- `TestTraceRender`：完成数字规范化、科学记法展开、NUL 转义、240 字符截断和 FNV-1a 标记。
- `TracedAssertions`：完成阶段 A 使用到的 eq、raises，以及 is-true、is-false、null、not-null、fail、no-throw 入口。
- `TestHelpers`：完成 binary32 字面量量化和运行时 UTF-16 code unit 文本构造。
- `TextRange`：完成 start/end、length、isEmpty 和两个 require 失败路径的 Haxe 实现。
- `TextRangeTest`：完成 `exposesLength` 与 `rejectsNegativeStart` 两个测试 section。
- `CoreUnitsGeometryTest`：完成几何、`ic` 单位、约束与最大行数决策的测试；Bun、byte trace golden 与生成入口通过。
- `UnicodeNumberTest`：完成 Unicode 17 数字范围表、scalar 校验与测试；Bun、byte trace golden 与生成入口通过。
- `UnicodeWordCharacterTest`：完成 Unicode 17 字母/标记/数字范围表、scalar 校验与测试；Bun、byte trace golden 与生成入口通过。
- `UnicodeScriptEvidenceTest`：完成 Unicode 17 Script evidence 范围表与三态分类测试；Bun、byte trace golden 与生成入口通过。
- `EastAsianSpacingTest`：完成 pinned UTR #59 spacing 分类、locale registry、grapheme edges 与 scalar 校验；Bun、byte trace golden 与生成入口通过。
- `EastAsianSpacingCoverageTest`：完成 Unicode/spacing 元数据、边界、locale、grapheme 与异常覆盖；Bun、byte trace golden 与生成入口通过。
- `EastAsianSpacingLookupCoverageTest`：完成范围表头部、尾部、未覆盖区间与各枚举值查找覆盖；Bun、byte trace golden 与生成入口通过。
- `Main`：完成串行测试调用、失败退出码和 trace flush。

## 验收记录

- 规定命令 `nix develop -c bash -c 'haxe porting/haxe/tests/compile.hxml'`：环境拒绝连接 `/nix/var/nix/daemon-socket/socket`。
- 等价 Haxe 4.3.7 命令：`PATH=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:$PATH haxe porting/haxe/tests/compile.hxml`，rc=0。
- 运行命令：`/run/current-system/sw/bin/bun porting/haxe/out/haxe-tests.js`，输出 `all TextRangeTest checks passed`。
- golden 对照：`diff -u engine/src/jvmTest/resources/golden/test-traces/TextRangeTest.txt porting/haxe/out/haxe-traces/TextRangeTest.txt`，rc=0、无差异。
- 规定的 core 生成命令同样受 Nix daemon socket 权限限制；等价 Haxe 4.3.7 命令 `haxe porting/haxe/core-kotlin.hxml` rc=0。
- 生成入口包含全 `porting/haxe/src` Intercept 扫描根、`float-precision=f32` 和指定 Kotlin/runtime 输出定义；入口只显式列阶段 A 的 `TextRange` 与 `TextRangeTest`。
- 未运行 Gradle，未修改 `engine/`、`.haxelib/` 或 `porting/haxe/baseline-goldens/`。
- `BLOCKED:` 用户要求的本地提交未完成：Git 索引和对象库位于 `/home/losses/Development/tiqian/.git`，沙箱拒绝创建 `index.lock` 和对象临时文件；未留下暂存状态。

## 来源与已知差异

- 当前 Kotlin 源没有独立的 `TextRange.kt`，`TextRange` 位于 `engine/src/commonMain/kotlin/org/tiqian/core/Geometry.kt` 的首个类；Haxe 按该类的实际行为拆出 `TextRange.hx`。
- boring 的 Haxe 类构造函数生成 Kotlin primary constructor header，阶段 A 生成试编译只验 rc=0；中央替换仍按工具链既有规则处理构造路径。
- `org.tiqian.test` trace 源未列入 core 入口。当前 boring 编译器会因 `TextRangeTest` 的 typed dependency 生成依赖文件；中央替换按任务书第 7 节排除该包，Haxe 测试编译仍保留这些源。
- 任务书要求的 Nix 命令和提交纪律与当前沙箱分别存在 socket 权限限制及工作区规则冲突；此文件保留实际结果，阶段 checkpoint 仍按本次执行产物建立。
- Kotlin 测试中的 `中` 为 `U+4E2D`，既有 golden 对应消息为 `U+400d`；两码点在本数据表中均为 word character、均非 number。测试 trace 按 golden 保持 `U+400d`。

## CHECKPOINT: 阶段 A

以下是阶段 A 交付源文件在 checkpoint 建立时的 MD5：

```text
d8a8df563c3e33b08a00611b03af5a3e  src/org/tiqian/core/IllegalArgumentException.hx
ae1fecb5b2b212dfbf4ea21648857b2b  src/org/tiqian/core/TextRange.hx
5485721e43d85eca4be75e37e9d4b405  src/org/tiqian/core/TextRangeError.hx
fd2178ab96e095ed7c88fbaac04b64ed  src/org/tiqian/core/TextRangeTest.hx
05c314734ad9baf29d8d8a93b9762ce8  src/org/tiqian/test/TestHelpers.hx
887d2bf9b8716ddad60774aed345fc86  src/org/tiqian/test/trace/TestTrace.hx
deacca62441f1682ad16277187e01c96  src/org/tiqian/test/trace/TestTracePlatform.hx
3239fd2bf9f93b45580ef779d4a4a168  src/org/tiqian/test/trace/TestTraceRecorder.hx
fce918d87934732a033cb9b8e88c4561  src/org/tiqian/test/trace/TestTraceRender.hx
1bf72d3b44f12f299c0c60b16abad7e3  src/org/tiqian/test/trace/TestTraceStore.hx
6201682b1064abdef7af33ab975206f4  src/org/tiqian/test/trace/TraceAssertionError.hx
dcd3234a678914c5d66f10200fc69940  src/org/tiqian/test/trace/TraceAssertionException.hx
87ffd591f7969a926ced283467738683  src/org/tiqian/test/trace/TraceField.hx
253bd09fd1120f2954bde4e1f7079d56  src/org/tiqian/test/trace/TraceFormat.hx
f2b09d1186fce6e321171d7facb1798b  src/org/tiqian/test/trace/TraceRecorder.hx
1e5a78413bd72f32926f7e2bc680bb09  src/org/tiqian/test/trace/TracedAssertions.hx
a281b540ef4131f10a9cc8fd7ba60f89  tests/Main.hx
09e7be099991776f415de46b0c211cdd  tests/StringBufOracle.hx
0e6a2fe8f1a43d31d2209ca029e29142  tests/compile.hxml
bff1294cace0779caaf7f22153b6dabb  core-kotlin.hxml
```

`PROGRESS.md` 是 checkpoint 容器，未把自身 MD5 写入自身内容；提交前单独执行 `md5sum porting/haxe/PROGRESS.md`。

## 阶段 B 类级记录

- `CoreUnitsGeometryTest`：完成几何、`ic`、约束和最大行数决策覆盖；trace 对照通过，生成入口 rc=0。
- `UnicodeNumberTest`：完成 Unicode 17 Number 范围表、scalar 校验和跨脚本成员覆盖；trace 对照通过，生成入口 rc=0。
- `UnicodeWordCharacterTest`：完成 Unicode 17 Letter/Mark/Number 范围表与成员覆盖；trace 对照通过，生成入口 rc=0。
- `UnicodeScriptEvidenceTest`：完成 Unicode 17 Script evidence 三态分类与非标量边界覆盖；trace 对照通过，生成入口 rc=0。
- `EastAsianSpacingTest`：完成 UTR #59 spacing 分类、语言 registry、grapheme edge 和 scalar 校验；trace 对照通过，生成入口 rc=0。
- `EastAsianSpacingCoverageTest`：完成 spacing 元数据、边界、locale、grapheme 与异常覆盖；trace 对照通过，生成入口 rc=0。
- `EastAsianSpacingLookupCoverageTest`：完成范围表头尾、未覆盖区间和枚举值 lookup 覆盖；trace 对照通过，生成入口 rc=0。
- `CoreLayoutQueriesGapsTest`：完成布局查询空隙、背景、选择和命中测试分支；trace 对照通过，生成入口 rc=0。
- `LayoutQueriesTest`：完成复制、定位、边界框、装饰、背景、命中测试、选择和 ruby 几何覆盖；trace 对照通过，生成入口 rc=0。
- `LayoutQueriesResidualCoverageTest`：完成余下 64 个 LayoutQueries 测试方法与异常/退化分支；trace 对照通过，生成入口 rc=0。
- `CoreBoundaryTest`：完成 source interaction boundary、代理项、Hangul、regional indicator 和 emoji 边界覆盖；trace 对照通过，生成入口 rc=0。
- `LinkAddressDisplayTest`：完成地址显示与 prose 显示的 scheme 分支覆盖；trace 对照通过，生成入口 rc=0。
- `SourceInteractionBoundariesCoverageTest`：完成 CRLF、Jamo、扩展符、ZWJ、修饰符、落单代理项和 bias 全分支覆盖；trace 对照通过，生成入口 rc=0。
- `TextModelCoverageTest`：完成文本内容、spans、inline object、rich text pattern、ruby、paragraph model 和构造校验覆盖；trace 对照通过，生成入口 rc=0。

## 阶段 B 小结

- Haxe 测试编译：`PATH=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:$PATH haxe porting/haxe/tests/compile.hxml`，rc=0。
- Bun 运行：`/run/current-system/sw/bin/bun porting/haxe/out/haxe-tests.js`，输出 `all CoreUnitsGeometryTest checks passed`。
- Core 相关 golden：`python3 porting/central/compare-traces.py porting/haxe/baseline-goldens/test-traces porting/haxe/out/haxe-traces --mode tolerance --classes CoreUnitsGeometryTest,UnicodeNumberTest,UnicodeWordCharacterTest,UnicodeScriptEvidenceTest,EastAsianSpacingTest,EastAsianSpacingCoverageTest,EastAsianSpacingLookupCoverageTest,CoreLayoutQueriesGapsTest,LayoutQueriesTest,LayoutQueriesResidualCoverageTest,CoreBoundaryTest,LinkAddressDisplayTest,SourceInteractionBoundariesCoverageTest,TextModelCoverageTest,TextRangeTest`，输出 `classes=15 pass=15 fail=0`。
- Kotlin 生成：`PATH=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:$PATH haxe porting/haxe/core-kotlin.hxml`，rc=0；入口已加入阶段 B 测试类。
- 注释审计：`/run/current-system/sw/bin/bun porting/central/check-haxe-comments.ts --keep-list porting/central/comment-keep-list.txt`，输出 `copied lines: 103, new lines: 72` 与 `PASS`；keep list 67 行均已出现，translate list 71 行已翻译。
- 当前参考目录有 123 个 golden 文件；本任务 Core 范围的 15 个 golden 均已对照。未运行 Gradle，未修改 `engine/`、`.haxelib/` 或 `porting/haxe/baseline-goldens/`。
- 规定的 Nix 命令仍受 `/nix/var/nix/daemon-socket/socket` 权限限制，本次使用同一 Haxe 4.3.7 store binary 完成等价验收。

## CHECKPOINT: 阶段 B

以下是阶段 B 新建或修改文件在 checkpoint 建立时的 MD5；`PROGRESS.md` 自身不列入清单。

```text
a62275aafc089eb4dc3eeb92eb00e27c  src/org/tiqian/core/AutoSpaceDecisionInfo.hx
024ec635397b63bbfbf8f716c9aa6458  src/org/tiqian/core/BopomofoDecisionInfo.hx
cc1ad10112e5583747cb6a96a5b762df  src/org/tiqian/core/BopomofoGlyphPlacement.hx
a980e32b0b69c6dce88f10a80fd4d72d  src/org/tiqian/core/BopomofoGlyphRole.hx
3526d38f738529144340a3e0f4659b13  src/org/tiqian/core/BuiltInLayoutProfiles.hx
e58df70dc778fe4751995a3305755779  src/org/tiqian/core/Cluster.hx
2b97bac83fce2cccffa4ab155006575c  src/org/tiqian/core/ClusterGeometryDecisionInfo.hx
ab342800df28329fd5408b42b16cc278  src/org/tiqian/core/ColorSpan.hx
b5687f0fa3359050988303badddd9afb  src/org/tiqian/core/CoreBoundaryTest.hx
4b5bd29e4e05b0bd4ce7ddaf86988a30  src/org/tiqian/core/CoreLayoutQueriesGapsTest.hx
5ca572023f4c6d80564f2f99b9f003bb  src/org/tiqian/core/CoreUnitsGeometryTest.hx
a823f77404c0dd243aad5ddba0721610  src/org/tiqian/core/DecorationKind.hx
1156f1e0954b9cb6b9d1ee47d0f17317  src/org/tiqian/core/DecorationSpan.hx
6aa2e4cc604d9e28e1a35530c1ff1f02  src/org/tiqian/core/EastAsianSpacing.hx
c43ebd46cc18cd69dc906b7fcf7517cc  src/org/tiqian/core/EastAsianSpacingCoverageTest.hx
ae0b403446d19cb632f58a90d4dfd0f2  src/org/tiqian/core/EastAsianSpacingData.hx
272bb902dec573e77728b1a08dc15745  src/org/tiqian/core/EastAsianSpacingEdges.hx
b93fb708373b93e162d029b421100fa3  src/org/tiqian/core/EastAsianSpacingLookupCoverageTest.hx
83366ffc2fe1192fa9c40a8e171446fe  src/org/tiqian/core/EastAsianSpacingTest.hx
30838185b041e2482421a874ee765dfe  src/org/tiqian/core/EastAsianSpacingValue.hx
6aa2e4cc604d9e28e1a35530c1ff1f02  src/org/tiqian/core/Geometry.hx
3db4fdca69ab02ddabadd1d0d7a2c5c3  src/org/tiqian/core/Glyph.hx
c847bde83d2ff0a168d957cf014cf694  src/org/tiqian/core/GlyphRun.hx
43e94cea43179e7d699e36d40ac754d7  src/org/tiqian/core/Ic.hx
2662cf9eaeb2e250f78c1588d9ddebdf  src/org/tiqian/core/IllegalArgumentException.hx
af91c42a51469d8fd7cfaa5ab4bdb918  src/org/tiqian/core/InlineAttachment.hx
edf83913ec5e76262e4556b2570aafe2  src/org/tiqian/core/InlineBoxOuterSpacing.hx
4dca29180298d0df15576379a74fe83c  src/org/tiqian/core/InlineBoxSpan.hx
ae29b8f9efe7580f3fd786d5a302d18f  src/org/tiqian/core/InlineObjectBoundaryAdjustment.hx
79c0eb408eea99cf725c024e622a94f6  src/org/tiqian/core/InlineObjectPreferredStretch.hx
09901f9c7513783eb4959d0f10ead5e9  src/org/tiqian/core/InlineObjectPreferredStretchKind.hx
a3dabcd7229b8b885c1b26b99faedbdf  src/org/tiqian/core/InlineObjectSpan.hx
05b240734f44a7ad202a55a4c74770c4  src/org/tiqian/core/IntRange.hx
58ee17d3f3afcff8cf8e2fb536d66830  src/org/tiqian/core/LastLineAlignment.hx
b0396d9e9ee1df8f7ee8548b93729faf  src/org/tiqian/core/LayoutConstraints.hx
7b6f3db6cca527ed2c1f52d5d33332fb  src/org/tiqian/core/LayoutDebugInfo.hx
997a329335d367ead13164fbd6b755bd  src/org/tiqian/core/LayoutInput.hx
733e4f1f45ead5601e0b6f49480c962b  src/org/tiqian/core/LayoutModel.hx
5d4316e853478e41d98b550052739f91  src/org/tiqian/core/LayoutProfileId.hx
e656a28fc39fc66657999b82406a6c09  src/org/tiqian/core/LayoutQueries.hx
b90dc694eeb1f2c2cbceabafc490d9ed  src/org/tiqian/core/LayoutQueriesResidualCoverageTest.hx
820d0525c0cd8d31b52198cdc830a068  src/org/tiqian/core/LayoutQueriesTest.hx
b1be7cb50394c6101eb14c40a4db1c45  src/org/tiqian/core/LayoutResult.hx
cd0f102010ec9b893b8efcf0ba6c2570  src/org/tiqian/core/LineBox.hx
d66caa2217ad3887a4d57f9af15c39d3  src/org/tiqian/core/LineBreakPolicy.hx
aaaa7248381735d94a3c7ac41ac40353  src/org/tiqian/core/LineBreakSpan.hx
c80c68a90c9e51df71a1b25052d067f9  src/org/tiqian/core/LineDebugInfo.hx
bd238d8cc46bbb5ebc2f5628adeb7524  src/org/tiqian/core/LineEndReason.hx
4fae5266876547f1fa9583458774b6a2  src/org/tiqian/core/LineLengthGrid.hx
5ea351d9823b3e6266acf699d7b05a67  src/org/tiqian/core/LinkAddressDisplay.hx
f0f1f3453544af07b32bdada924f86cd  src/org/tiqian/core/LinkAddressDisplayTest.hx
77fa0d03d7f91265f750762b6f9236c7  src/org/tiqian/core/MaxLinesDecisionInfo.hx
16ac125d91d4d0a97f837853889f0df8  src/org/tiqian/core/MeasureAdaptiveFirstLineIndent.hx
4a689b3ac404b4a0fec9d9ef02090570  src/org/tiqian/core/MetricDecisionInfo.hx
573dccea3b4890427a686e08d45e832f  src/org/tiqian/core/NoSuchElementException.hx
32b254fbc2a5afdf156bcf72b32795a2  src/org/tiqian/core/ParagraphStyle.hx
9eb17c91e382ff4b336a2921896b4267  src/org/tiqian/core/PositionedCluster.hx
688c7ba671c7daf616338cc60b75a5c9  src/org/tiqian/core/Rect.hx
b32e37ae00838647a22f735ff32ed18c  src/org/tiqian/core/RichTextBackgroundDrawStyle.hx
42244150f4c4b8cde43637d3ce8c6206  src/org/tiqian/core/RichTextBackgroundMetricPolicy.hx
4fadd3d81a096d40d1c7ad1170b60cd3  src/org/tiqian/core/RichTextBackgroundPaint.hx
cd80fb77bfd99ed4efc519e8c401333f  src/org/tiqian/core/RichTextCornerRadii.hx
bbbf58a4dd122e27aa41d3be2a0ef708  src/org/tiqian/core/RichTextLinePattern.hx
894a414e76cc11542c84505128bbcc44  src/org/tiqian/core/RichTextLineSegment.hx
edb9184ce920cff5badfec35b036e4e1  src/org/tiqian/core/RichTextPaint.hx
251b259268a2b5e63ce19e319f1e2b1c  src/org/tiqian/core/RichTextRole.hx
28fb124ce5ee2ffb558836756708ad19  src/org/tiqian/core/RichTextSpan.hx
b5b5d4b94a19882e558765db18215931  src/org/tiqian/core/RubyDecisionInfo.hx
8a34a0a6c6d7b9db4786708db8fa1956  src/org/tiqian/core/RubyKind.hx
003f9549aca4ede97f89afaac676de6c  src/org/tiqian/core/RubyLineHeightMode.hx
c94c1457044cf8b67d78943cb4ab70aa  src/org/tiqian/core/RubySpan.hx
44835ac48004f860d2f2db1fec4bcc74  src/org/tiqian/core/Size.hx
1022baa8ad76c93667742405bc2e0bf0  src/org/tiqian/core/SourceBoundaryBias.hx
1a0562d0858f427131218787d175c439  src/org/tiqian/core/SourceInteractionBoundaries.hx
6f0b9406781d175a8e745355cae61dc9  src/org/tiqian/core/SourceInteractionBoundariesCoverageTest.hx
cc143cef8e393259d3a66f0681bc947e  src/org/tiqian/core/TextModelCoverageTest.hx
5d8b26e7ce646f668ddd6de57b95ab60  src/org/tiqian/core/TextRange.hx
26c98ea231de541a0915b31fae2fbd85  src/org/tiqian/core/TextRangeError.hx
72e121d868719707103a675f6da5254c  src/org/tiqian/core/TextSpan.hx
5c745dc4efd5e5245786e7b390086a91  src/org/tiqian/core/TextStyle.hx
0a117d8fc64ac0f12ddc69fc9a1d0aee  src/org/tiqian/core/TiqianTextContent.hx
6c27fd4402db6dd0aabce128d115edbd  src/org/tiqian/core/UnicodeEastAsianSpacing.hx
81e8aecbc3910bdf6e59f6abe32bad29  src/org/tiqian/core/UnicodeEmojiModifierBaseData.hx
86a1a3469432a59d6b3a477b11e62f3a  src/org/tiqian/core/UnicodeExtendedPictographicData.hx
b090f430c609429300ed53ede5b709c5  src/org/tiqian/core/UnicodeNumber.hx
6c1a8b7aa9bb8b307aa2712c448d52ae  src/org/tiqian/core/UnicodeNumberData.hx
61a6148ae60149ab8fec8151bad57965  src/org/tiqian/core/UnicodeNumberTest.hx
02b6e04ec7a4d1454ac4fe2e9e69df77  src/org/tiqian/core/UnicodeScriptEvidence.hx
7b0c28fdf8a26885d9c327ec05d21c47  src/org/tiqian/core/UnicodeScriptEvidenceClassifier.hx
31a3d022e532b054d58ed597145dc479  src/org/tiqian/core/UnicodeScriptEvidenceData.hx
297c0165782c7f7e717e38b18e89687f  src/org/tiqian/core/UnicodeScriptEvidenceTest.hx
02e6b8e73e40b3b0c782aff68ab060e3  src/org/tiqian/core/UnicodeWordCharacter.hx
fe025d17ff05f5b0861298d45c95ba52  src/org/tiqian/core/UnicodeWordCharacterData.hx
48d9642c26fc0822abd165a4b5e05539  src/org/tiqian/core/UnicodeWordCharacterTest.hx
6d6ef655260fa1e42ec6e3e1dc94fb68  src/org/tiqian/core/Units.hx
59247097ba493155c81d17bd611d47df  src/org/tiqian/core/WritingMode.hx
8cf0dd7932f327e112c64b8e0ffb4267  data/east-asian-spacing-ranges.txt
60c504303767be75271c365ce2dc551a  data/emoji-modifier-base-ranges.txt
a449a9eb2303e30b71e994a5c3c36dab  data/extended-pictographic-ranges.txt
969787bade76f89a34f00e4ad36cc496  data/unicode-number-ranges.txt
a4df4fc0acf51ec5d18ea2420cd8e4a7  data/unicode-script-evidence-ranges.txt
0094efe65e50484adbd14dce7fd961ef  data/unicode-word-character-ranges.txt
f56c9c8da018ee225e806416bbf12018  src/org/tiqian/test/trace/TestTraceRender.hx
703723a11e7f69f4f7977fbcb1daf1cd  src/org/tiqian/test/trace/TracedAssertions.hx
2cd99d20051186c5a2adfcd10d097cc1  tests/Main.hx
6069954d38a693bcddabfb051a37187d  core-kotlin.hxml
```

## 中央条目（2026-08-30）：异常改名裁定

用户裁定：移植异常类改名 IllegalArgumentException→TiqianIllegalArgumentException、
NoSuchElementException→TiqianNoSuchElementException，理由是异常名要能突出来源，
使用者按名精确捕获并 fallback。全树替换已完成（含 TracedAssertions 字面量与
recordEvent 记录名）。Haxe 侧记录字面量随之变为 TiqianIllegalArgumentException，
engine 侧对应测试点的 T::class.simpleName 同步改型后两侧一致；尚未用生成代码
替换的类，engine golden 仍记 kotlin 名，整包替换完成后收敛。TextRange 的
替换已验证：全量 :engine:jvmTest 通过，golden 刷新仅三行异常名 diff。
已知 boring 待修项：生成的 Kotlin toString 缺 override（替换时手工补一行，
boring 侧修复排队，见任务 14）。

## 中央条目（2026-08-30）：默认值改写完成并通过全量验证

86 处默认值改写按规格 22 两类 sanctioned 形态完成：常量默认留在声明
（42 处），coalescing default 用 `?p:T` 加空值合并赋值（22 处），白名单外的
默认值（22 处，构造调用、参数引用、命名常量）改为必选参数并在省略
调用点物化默认表达式。物化 672 处，覆盖 9 个文件。字节偏移漂移损坏
已全部按 engine Kotlin 真值修复。验证链全部通过：compile.hxml 零错误、
测试 rc=0 无 FAIL、15 类 trace 与 engine golden 比对通过。

异常命名同日第三次修正，经用户确认定案：engine 侧不改名（此前提议的
引擎改名已收回）；移植侧全部抛出位置使用 Tiqian 开头的类名。上一段
记录的不带前缀的 IllegalArgumentException 与 NoSuchElementException
两个类已删除，24 处由 require 检查翻译来的抛出改回
TiqianIllegalArgumentException，1 处由 first 翻译来的抛出改回
TiqianNoSuchElementException（均为枚举承载形态，V04 合规；TextRange
自身的 2 处抛出从未改名）。TracedAssertions 恢复为两路记录。
engine golden 中现有 73 行记录 Kotlin 内建异常名，与移植侧 Tiqian 名
的差异由 compare-traces.py 新增的 EXCEPTION_NAME_ALIASES 规则处理：
只在 raises exception= 行把 IllegalArgumentException 与
TiqianIllegalArgumentException、NoSuchElementException 与
TiqianNoSuchElementException 当作同一个名字，其他名字差异与消息差异
仍然判失败（三项反向测试验证过：桥接配对通过、未映射的名字失败、
消息不同失败）。每次比对输出 exception-alias= 计数；engine 手写文件
被生成代码逐个替换、golden 里不再出现内建名之后，删除这条规则。
验证链重新全部通过：compile.hxml 零错误、测试 rc=0 无 FAIL、15 类比对
15/15 通过、exception-alias=73。

vendored boring（.haxelib/boring/git @ baf67c4）有一处本地补丁
porting/haxe/patches/boring-tnew-precise-lookup.patch：DefaultArgExpander
对 TNew 的默认值查找在精确键未命中时回退到全局按名匹配，多个类带
默认构造器后任何未登记构造器的 TNew 都会误报 ambiguous。修复为 TNew
只走精确键链（类加方法名、接口、父类），按名匹配的后备路径仅保留给
无法确定声明类的访问路径。该缺陷在 Codex defaults 分支的在飞实现中
同样存在（line 698 一带），中央审查时并入修复。

2026-08-31 核销：0383591（coalescing default 回收合并）重写了 completeNew
序段——先取构造器参数表，args.length >= params.length 直接返回，默认值
查找移到其后。历史触发形态（StringBuf 零参 TNew、IntRange 全参 TNew）在
到达按名回退之前就被前置返回截断，缺陷在 boring main 不再可达。port 树对
9cfc006 干净 vendored（补丁未应用）编译，仅剩 RubySpan.hx:46 条件构造赋值
报错（缺口 4 已知拦截），无任何 TNew 歧义。补丁文件已删；流程裁定：
boring 的修复一律进 boring main 后推进 vendored 指针，不再留本地补丁。

2026-08-31 指针推进 ce28a3a（枚举无参值形态 + 值查询 + Std.string 标量行
合并后）：port 树编译拦截点更新为 `TextStyle.hx:39 Std.string accepts
scalars and parameterless enum values only`——Std.string 的数组域当时尚未
降级。已按 boring-first 裁定在 boring main 落规格修订 997828d（数组渲染
`[a, b]` 五端统一、Haxe 原生 `[a,b]` 分隔符分歧走 boring_oracle 条件），
实现派发 lane/std-string-arrays。数组域落地后 port 侧 TextStyle、
RubySpan、CoreLayoutQueriesGapsTest 三处 `Std.string(<数组>)` 保持原样即
可编译；RichTextPaint 对 `RichTextLinePattern`/`RichTextBackgroundPaint`
类实例的 Std.string 仍需 port 侧改写（对象不在域内）。

## 中央条目（2026-08-30）：目录定为 engine-haxe

用户裁定：porting/ 不进 git；Haxe 源码树移到仓库根目录 engine-haxe/
（本次已移动）。终态是删掉 engine/，本目录改名为 engine/。比对脚本移至
engine-haxe/tools/compare-traces.py；TASK.md 与 codex 日志留在不跟踪的
porting/；out/、baseline-goldens/、smoke/ 加入忽略清单。移动与路径修正
后验证链重新通过：compile.hxml 零错误、测试 rc=0 无 FAIL、15 类比对
15/15 通过、exception-alias=73。

2026-08-31 指针推进 405857f（Std.string 数组单遍降级合并后）+ 全量拦截点
普查：以丢弃 worktree 逐个中和迭代编译，摸清到零错误的完整清单并已全部
处置。已修复入库：裸类拼接 toString 全批（InlineBoxSpan/LineBreakSpan/
DecorationSpan/TextSpan/RichTextSpan/RichTextLineSegment/RubySpan/
PositionedCluster/InlineObjectSpan 的 range/style/paint/span/baseRange/
boundary 字段，ParagraphStyle 的 blockIndent/lineLengthGrid/
firstLineIndentPolicy，LayoutInput 的 content/textStyle/paragraphStyle/
constraints/profileId 头部五行——Std.string 域检查同样作用于字符串拼接
操作数，早期 census 只 grep Std.string 漏了这一类）；sameRole 嵌套
variant switch 改平（switch 子集三规则：arm 必须是表达式、绑定载荷的
switch 必须全构造器覆盖、arm 内嵌套 switch 无降级——Link 载荷比较拆到
sameLinkTarget 助手，parameterless 构造器用 == 比较 data object 单例）。
剩余拦截分三类，均登记 boring 缺口队列：缺口 4 构造器纪律（RubySpan.hx:46
locale 跨参数条件默认、InlineObjectBoundaryAdjustment.hx:27 Null 解析+
校验+赋值）；缺口 10 可变静态字段赋值（TestTrace.recorder 全局记录器、
普通类自身静态 var 赋值同样无降级，已探针实锤）；测试类成员纪律波
（15 个测试类携带非测试成员 testTrace/currentTrace/flushTestTrace/
lowerHex 及各类 helper，boring 裁定共享逻辑入普通类，重构波待派发）。
flushTestTrace 十四处定义零调用者，属死代码随波删除。首错即停教训：
haxe 编译器本配置下报首个错误即止，lane 判据不能用「恰好 N 个已知错误」，
必须迭代到零或以丢弃树中和验证。

2026-08-31 InlineObjectBoundaryAdjustment 改常量默认：Kotlin 原版
shrinkCapacity 与 lineEndDiscardableAdvance 就是 `Float = 0f` 常量默认，port
侧原以 Null 解析加校验加赋值建模并无必要。改为 `shrinkCapacity:Float = 0.0`
等常量默认后构造器通过全部检查，TextModelCoverageTest 四处拒绝用例同步改为
省略或显式 0.0 形态，fixed() 改全默认构造。该文件退出缺口 4 拦截清单。同一轮
修复 74c92c12 的遗漏：Main.hx 仍调用已删除的 flushTestTrace，测试入口在该
提交上编译失败；TestTraceRecorder 增 flushClass(className) 静态，Main 十五处
改经它写 golden。验证：tests/compile.hxml 零错误、测试 rc=0、15 类比对 15/15、
exception-alias=73。剩余 Kotlin 拦截两处：RubySpan.hx:46（缺口 4）、
TestTraceRecorder.hx:10 静态赋值（缺口 10）。

2026-08-31 LayoutModel 剩余 28 个 DecisionInfo 记录全部入库（fd9d9e44）：
BreakOpportunity/EmergencyTrackingEligibility/InlineBox/InlineObject/
ZeroWidthBreak/MandatoryBreak/FirstLineIndent/LineLengthGrid/Kinsoku/
ContextualKinsoku/InlineObjectPunctuationAttachment/LineSpacing/
RubyLineHeight/InlineObjectLineHeight/DecorationSegment/Decoration/
LineEdgeTrim/Font/Shaping/Punctuation/Spacing/RoleOverride/LineDecision/
LineRepairDecision/LineRepairAllocation/LineRepairCandidate/Justification
Decision 与 Allocation，一律 @:dataClass（生成 Kotlin data class）。
LayoutDebugInfo 扩到 Kotlin 全字段集（24 列表 + 6 可空），构造器保留
maxLinesDecision 首位的既有形态，端口测试全部位置传参不动；六参之后的新参数
全部 ?param 加 null 合并，生成的 Kotlin 保留原生默认。

同轮确立默认保真形（d392dca3）：boring 对 Haxe 原生常量默认与可空直assign
都会从生成签名剥掉默认值，只有三元合并式保留：`?p:Null<T>` 加
`this.p = p == null ? E : p` 生成 `p: T = E`（E 为常量）或 `p: T? = null`；
`?p:Array<T>` 加 `p == null ? [] : p` 生成 `= mutableListOf()`。RubyDecisionInfo、
BopomofoDecisionInfo、MaxLinesDecisionInfo、InlineObjectBoundaryAdjustment
四处既有常量默认已改入该形态；InlineObjectBoundaryAdjustment 同时补
@:dataClass 并改校验读 this 字段，生成 data class + init 校验块，与
TextModel.kt:142 形态一致。Kotlin 允许带默认参数后跟必选参数，policyBodyFloor 过渡形态经
kotlinc 最小样例实证通过。

两个待办随记：PunctuationDecisionInfo.policyBodyFloor 的 Kotlin 原默认读
bodyWidth 参数（缺口 4 范畴），过渡为必选参数，缺口 4 实现合并后改
?Null<Float> 合并式；PunctuationDecisionInfo.char 与 SpacingDecisionInfo
leftChar/rightChar 的 Kotlin Char 以单 UTF-16 单元 String 移植，手写消费方
在 layout 波移植时同步换字面量形态。既有文件的原生常量默认统一转换见下一条。
验证链：compile.hxml 零错误、测试 rc=0、15 类比对 15/15、
exception-alias=73；两处已知拦截中和后 core-kotlin 生成零错误、恢复后仍止于
RubySpan.hx:46 首错。

2026-08-31 既有文件原生常量默认全部转合并式：Cluster、Glyph、LineBox、
TextStyle、ParagraphStyle、InlineBoxSpan、RichTextPaint、
RichTextBackgroundPaint、ClusterGeometryDecisionInfo、LineLengthGrid、
MeasureAdaptiveFirstLineIndent、BopomofoDecisionInfo、RubyDecisionInfo 十三处
文件按 Kotlin 原版默认逐参数核对后改 `?p:Null<T>` 加常量合并；Kotlin 原版
`= null` 的可空参数（Glyph 四个、RichTextPaint.argb、
ClusterGeometryDecisionInfo.glyphPlacementReason、ParagraphStyle.lineHeight
与 firstLineIndent、LineLengthGrid.bodyAlignment）改 null 合并臂。读参数或
静态字段的默认保持必选并就近注释：Cluster.displayText、
RichTextBackgroundPaint.continuationCornerRadius 与 drawStyle、
RichTextPaint.linePattern 与 background、ParagraphStyle.blockIndent、
firstLineIndentPolicy、lineLengthGrid 与两个 em 常量默认、LayoutInput 三个
样式默认、InlineObjectSpan 两个边界、BopomofoGlyphPlacement 三个几何默认、
LineBox.debug（构造调用默认不在缺口 4 扩展文法内，长期必选）。
TiqianTextContent.sourceBoundaries 的 Kotlin 类型是 Set<Int>，移植持有
Array<Int>，类型偏差留待 layout 波移植时裁定。验证链通过：compile.hxml 零错误、
serial-test rc=0、15 类 tolerance 比对 15/15、exception-alias=73、
core-kotlin 仍止于 RubySpan.hx:46 首错。

2026-08-31 clreq 波 slice 1：BopomofoTone、BopomofoReading、BopomofoParser、
NumberSymbolCohesion 四个类与 BopomofoParserTest、NumberSymbolCohesionTest
两个测试移植完成。BopomofoParser 的声调分派在 Kotlin 原版是带 else 的
when；boring Kotlin 侧当前只支持枚举 switch 的降级，按 features/15 对判别
式的链式分支许可改为 if/else 链，行为不变。测试类的 groups 辅助按 spec 27
移入同文件普通类 NumberSymbolCohesionTestHelpers（沿
TextModelCoverageTestHelpers 先例）。TestTraceRender 增 renderStringArray，
TracedAssertions 增 assertEqualsStringArray、assertEqualsBopomofoTone、
assertEqualsBopomofoReading 三个入口。clreq 文件在隔离 hxml 下做 Kotlin
降级检查：修掉 BopomofoParser 的 V15 与测试类非测试成员两处后，止于已登记
的 TestTraceRecorder.hx:10（缺口 10 范畴）。中文字面量沿移植树既有约定
直接写原字面量（从 Kotlin 原文机械复制）。验证链通过：compile.hxml 零错误、
serial-test rc=0、17 类 tolerance 比对 17/17、exception-alias=73、
core-kotlin 仍止于 RubySpan.hx:46 首错。

2026-08-31 clreq 波 slice 2：ClreqProfile.kt 及其伴生枚举与策略类全量移植完成。
新增 12 个枚举（ClreqStrictness、ClreqRegion、CjkPunctuationGlyphPolicy、
PunctuationGluePlacement、GlueSide、AutoSpaceMode、LineAdjustmentStrategy、
LineEndPunctuationStyle、KinsokuLevel、HangingPunctuationStyle、
InteriorPunctuationStyle、PunctuationClass），策略与数据类 AutoSpacePolicy、
AdjustmentStylePolicy、PunctuationWidthPolicy、PunctuationPolicy、
CjkPunctuationGlyphSubstitution、ResolvedKinsoku、ClreqProfile、
ClreqProfileResolver（interface 与 BuiltInClreqProfileResolver 同文件双类型）、
PunctuationGluePlacements、ClreqPunctuationPolicies、
ClreqPunctuationAdvancePolicy、ClreqPunctuationGlyphSubstitutor，加 layout 侧
KinsokuRule（interface 与 ClreqKinsokuRule 同文件）。KinsokuMode 按裁定移植为
带参枚举，Kotlin 默认参数（Fixed 的 Disabled；MeasureAdaptive 的 14/24/32）
在 Haxe 构造点逐一显式书写；BopomofoReading 增 copy 与 hashCode。
五个测试 KinsokuLevelTest、PunctuationGluePlacementTest、
ClreqPunctuationGlyphSubstitutorTest、ClreqProfileCoverageTest、
ClreqPolicyTailCoverageTest 移植完成，辅助逻辑按 spec 27 入同文件
XxxTestHelpers。两个可降级裁定：其一，Kotlin when 表达式在 Haxe 侧必须写成
return switch 值臂形式（KotlinExpr 只降 when 表达式，switch 臂内 return 语句
不在子集内），多语句臂拆私有辅助函数；其二，非模块主类型跨文件引用用
模块名.类型名导入（ClreqProfileResolver.BuiltInClreqProfileResolver、
KinsokuRule.ClreqKinsokuRule）。跨文件类引用处 Int 入 StringBuf 用 "" + v 沿
TiqianTextContent 先例。ClreqProfile toString 经 TestTraceRender.cap 截断，
golden 的 240 字符 FNV 行逐字节一致；1f/3f 一律写 0.33333334 字面量保 f32
渲染一致。验证链通过：compile.hxml 零错误、serial-test rc=0、22 类 tolerance
比对 22/22、exception-alias=73、隔离 clreq 检查止于 TestTraceRecorder.hx:10
（缺口 10 范畴，无新增违规）、core-kotlin 仍止于 RubySpan.hx:46 首错。

2026-08-31 cat3 波：七处构造默认值还原。AutoSpacePolicy（cjkLatin、cjkDigit、
gapEm、stretchMaxEm 四参全默认，Default 静态 preset 改零参构造）、Cluster
（displayText = text，读参数默认）、InlineObjectSpan（leadingBoundary 与
trailingBoundary = InlineObjectBoundaryAdjustment.fixed()，静态调用默认）、
LayoutInput（profileId = BuiltInLayoutProfiles.ClreqHorizontal，静态字段默认）、
ParagraphStyle（blockIndent = Ic.Zero，inlineObjectMinimumClearanceEm 与
emphasisDotGapEm = 类内静态字段默认）、RichTextBackgroundPaint
（continuationCornerRadius = cornerRadius，读参数默认；drawStyle =
Fill.instance，静态字段默认）、RichTextPaint（linePattern = Solid.instance，
静态字段默认）从强制参数改回 ?p:Null<T> 加合并默认。构造调用默认
（TextStyle()、ParagraphStyle()、RichTextBackgroundPaint()、
firstLineIndentPolicy、lineLengthGrid）在合并默认许可语法之外，保持强制参数。
前置修复：boring fc4f19f（spec 22 跨站点参数读取与阶段一改写）、7aa133b
（单例判定加声明类无实例字段要求，字段类零参自构造按 spec 35 构造初始化
 lowering，Rust 静态初始化补 None 补全）、d17734a（spec 22 阶段 B 状态改为
已实现）。验证链通过：compile.hxml 零错误、serial-test rc=0、35 类 tolerance
比对 35/35、exception-alias=300、core-kotlin 生成零错误（138 个 Kotlin 文件，
org.tiqian 下 137 个），此前登记的 ClreqProfile.hx:81 首错停点消除，当前无
首错停点。

2026-08-31 cat3 收尾：ClreqProfile 三处签名默认还原，偏离记录类别 3 全部还原。
coalesceRepeatablePunctuation（读同类静态
ClreqProfile.DefaultCoalesceRepeatablePunctuation，阶段 B 静态字段根，须写
全限定名，非限定名被识别器拒绝）、autoSpace（读 AutoSpacePolicy.Default，spec 35
构造初始化静态）、gluePlacement（PunctuationGluePlacements.forRegion(region)，
读前参数的静态调用）从强制参数改回 ?p:Null<T> 加合并默认；三个 preset 对
四个默认参数（含 punctuationGlyphPolicy）传 null，对应 Kotlin 原件的省略
实参；三个构造调用默认（adjustment、kinsokuMode、punctuationWidth）在许可
语法之外，保持强制参数。验证链通过：compile.hxml 零错误、serial-test rc=0、
35 类 tolerance 比对 35/35、exception-alias=300、core-kotlin 生成零错误，
生成 ClreqProfile.kt 携带三个原生默认表达式，与手写 Kotlin 原件
ClreqProfile.kt:17-19 同形（容器名 PunctuationGluePlacements 与
MutableList/Set 集合映射除外）。

2026-08-31 spec 37 落地收尾：BreakOpportunity 手写 toString 删除，偏离记录
类别 1 全部还原。boring c8cccc8（spec 37 record 打印与相等比较按字段声明
位置排序；Kotlin 在构造参数序与字段声明序不一致时显式发射合成成员覆盖
原生 data class 打印）合并推送后推进 vendored 指针，port 侧删除
BreakOpportunity.hx 的手写 toString 与登记注释，字段声明序 index、kind、
penalty、reason 即打印序，合成输出与手写体逐字节一致。验证链通过：
compile.hxml 零错误、serial-test rc=0、35 类 tolerance 比对 35/35、
exception-alias=300、core-kotlin 生成零错误。

2026-09-02 dpbreaker 测试类收尾：ParagraphDpLineBreakerTest 10 测、
CoverageTest 11 测、Coverage2Test 移植完成；引擎两处守卫对齐 Kotlin 原件
（naturalClusters/adjustedClusters 对齐检查从 IllegalStateException 改为
TiqianIllegalArgumentException 对应 require，candidateWindow 消息补句号，
ParagraphDpLineBreaker.kt:106-108）；IntRange.hx 增忠实 toString
（kotlin.ranges.IntRange 经 ClosedRange 显式打印 first..last，与 Rect 同为
原件显式 override 类别）。四门：compile.hxml 零错误、serial-test rc=0、
core-kotlin 零错误、tolerance 66 类 65 绿。仅剩 CoverageTest 9 行失配，
全部属于两条 boring 已登记能力缺口，port 侧不得手写绕过：
1. payload 枚举具名形态：spec 34 裁定 Name(param=value) 打印，LineOptimization.hx
   RepairOptions 注释记录"not implemented yet"；repair=PushIn(2,...) 仍为位置形态。
2. 集合字段打印：spec 33 只裁定 Array<T> 字段；hangingClusterIndices 的
   SortedSet<Int> 字段打印 {\n\tkeys : []\n}，Kotlin Set 应印 [a, b]。
两条缺口并入 boring 替换阻塞队列，落地后删除测试支撑里的临时渲染。
