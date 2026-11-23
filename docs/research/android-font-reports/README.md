# Android 字体行为取证

`demo/font-diagnostics` 是独立的 Android 平台字体行为采集器。它不依赖提椠的字体选择或排版
实现，也不在设备端判断“哪个字体正确”。采集结果用于建立外部事实，之后再据此修正实现。

## 输出

应用生成一个 `tiqian-android-font-evidence-*.zip`：

- `manifest.json`：schema、采集器版本、设备、API 能力以及包内条目的 SHA-256；
- `observations.jsonl`：每个探针、locale、font family 和样式请求的一条独立观测；
- `font-config.json`：从可读配置解析出的 family、alias、fallback、locale、TTC 与 axis 声明；
- `system-fonts.json`：公开 `SystemFonts` API 返回的字体集合；
- `font-directories.json`：应用沙箱可以看到的字体目录元数据；
- `renders/`：每条成功 shape 请求的实际软件 Bitmap PNG；
- `raw/font-config/`：可读字体配置的原文；
- `summary.md`：只说明能力和采集完整性，不生成 OEM 行为结论。

结构化格式见 [schema-v1.md](schema-v1.md)。

## 能力边界

| 能力 | 最低 API | 低版本如何记录 |
| --- | ---: | --- |
| `Paint` 宽度、run advance、栅格摘要、`hasGlyph` | 23 | — |
| `Paint` variable font axis 请求 | 26 | `unsupported` |
| 精确 `Typeface` 字重请求 | 28 | `unsupported`，另采集 legacy normal/bold |
| `SystemFonts` 枚举 | 29 | `unsupported` |
| 逐 glyph 字体、位置、glyph id 与 bounds | 31 | `glyphReadback.status=unsupported` |
| 合成粗斜体与 weight/italic override 读回 | 35 | `styleApplication.status=unsupported` |

`unsupported` 表示未知；它既不等于 `false`，也不表示相同或没有变化。某一层不可用时，报告仍可保留同次请求里
确实观测到的宽度、栅格或覆盖信号。

字体配置是声明证据；`SystemFonts` 是一个集合，不记录 font family 关系与 fallback 次序。两者都不能替代 API 31+
平台 shaping 后逐 glyph 读回的实际字体。

## 采集

```shell
./gradlew :demo:font-diagnostics:assembleDebug
```

安装并打开 APK，等待采集完成后点“分享证据包”。应用不联网、不修改系统；证据包会包含设备
build fingerprint、字体文件路径和哈希、可读字体配置原文以及字体栅格摘要，分享前应让设备所有者
知情。

旧版 `report-version: 3` 文本报告已移除。它在 API 不支持逐 glyph 读回时仍以空列表比较并生成
“未变化”“相同”等结论，因此不能作为 AOSP 或 OEM 基线。Git 历史中的旧文件也不应继续引用。

新的 AOSP/OEM 样本只有经过 schema 校验和语义审阅后才进入本目录；不再对整份文本或原始 XML
做直接行 diff。

当前 11 份样本的公开脱敏汇总见 [oem-samples-v1.md](oem-samples-v1.md)，由这些证据对 Compose
Android 字体选择做出的源码审计见
[2026-08-05-compose-font-selection-audit.md](2026-08-05-compose-font-selection-audit.md)。

## 主机端校验与比较

`platforms/android/font-evidence/evidence.py` 只使用 Python 标准库，负责三件事：

- `validate`：校验 schema、ZIP 条目安全性、manifest 完整性、条目大小与 SHA-256、
  observation ID 唯一性、状态计数、PNG 引用和辅助清单计数；
- `compare`：按稳定 observation ID 对齐两份包，分别报告请求、run metrics、逐 glyph 读回与
  raster 的变化，不直接 diff ZIP 或 XML；
- `catalog`：按**整份 ZIP 的 SHA-256**连接经过人工审阅的采集条件，生成机器目录和中文审计表。

```shell
python3 platforms/android/font-evidence/evidence.py validate /path/to/evidence-*.zip

python3 platforms/android/font-evidence/evidence.py compare \
  /path/to/before.zip /path/to/after.zip \
  --json-output /tmp/font-comparison.json \
  --markdown-output /tmp/font-comparison.md

python3 platforms/android/font-evidence/evidence.py catalog \
  /path/to/evidence-*.zip \
  --labels /path/to/private-labels.json \
  --json-output /path/to/private-catalog.json \
  --markdown-output /path/to/private-catalog.md
```

人工标签只记录采集者明确提供的条件，例如同一台设备在「系统默认」与「启用字体模块」下的两次
采集。`/data` 字体、`Overlay` 文件名、可变字体默认实例等由工具列为观测信号，但不会自动推断成某个
主题、无障碍设置或 OEM 策略。原始 ZIP、archive SHA-256 标签和完整机器目录都可能保留可识别的
设备组合，只能放在本地私有研究工作区；Git 中只保留无法回连单份原包的人工脱敏汇总。
