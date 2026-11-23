# engine-haxe/data 数据表的来源与重造

`engine-haxe/data/` 保存 13 个构建输入文件：12 个 `*-ranges.txt` 区间表与 1 个
`hyph-en-us.tex` 西文断词模式。Haxe 编译期宏 `DataTables.rangesField` 与
`DataTables.codeUnitsField` 直接读取这些文件，文件内容属于源码，修改必须经过
生成步骤。

## 上游文件与固定版本

七个上游文件都按 URL 与 SHA-256 固定。SHA-256 与区间表文件头记录的值相同。

- `emoji-data.txt`：`https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt`，SHA-256 `2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b`
- `emoji-variation-sequences.txt`：`https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-variation-sequences.txt`，SHA-256 `bb3d09ef03f206012c7532dd52dc0a21c9efddba0135ea4cf0d9201b8b9bba7e`
- `DerivedGeneralCategory.txt`：`https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedGeneralCategory.txt`，SHA-256 `d62e5bab70ca74f099343f71224fa051cb1fdd61a1ab45c0488c44cfc0b6102e`
- `LineBreak.txt`：`https://www.unicode.org/Public/17.0.0/ucd/LineBreak.txt`，SHA-256 `e6a18fa91f8f6a6f8e534b1d3f128c21ada45bfe152eb6b1bcc5e15fd8ac92e6`
- `Scripts.txt`：`https://www.unicode.org/Public/17.0.0/ucd/Scripts.txt`，SHA-256 `9f5e50d3abaee7d6ce09480f325c706f485ae3240912527e651954d2d6b035bf`
- `east-asian-spacing.txt`：`https://www.unicode.org/reports/tr59/east-asian-spacing.txt`，SHA-256 `49fe340a964a6e8e0ebc30099709c665cc6138d444b5c36dc336604047f1010f`
- `hyph-en-us.tex`：`https://raw.githubusercontent.com/hyphenation/tex-hyphen/dce23b4eb2df218ec6893b851562316d7cf37355/hyph-utf8/tex/generic/hyph-utf8/patterns/tex/hyph-en-us.tex`，SHA-256 `f4ffcd96c5cbc886bdad23f95dcae8edc3cd3620eae62f7946eceda97c4e68f8`

## 下载上游文件

下载目录使用 `tools/unicode-data/`。该目录写在 `.gitignore` 中，不进入版本库。

```shell
mkdir -p tools/unicode-data
curl -fsS -o tools/unicode-data/emoji-data.txt https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt
curl -fsS -o tools/unicode-data/emoji-variation-sequences.txt https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-variation-sequences.txt
curl -fsS -o tools/unicode-data/DerivedGeneralCategory.txt https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedGeneralCategory.txt
curl -fsS -o tools/unicode-data/LineBreak.txt https://www.unicode.org/Public/17.0.0/ucd/LineBreak.txt
curl -fsS -o tools/unicode-data/Scripts.txt https://www.unicode.org/Public/17.0.0/ucd/Scripts.txt
curl -fsS -o tools/unicode-data/east-asian-spacing.txt https://www.unicode.org/reports/tr59/east-asian-spacing.txt
curl -fsS -o tools/unicode-data/hyph-en-us.tex https://raw.githubusercontent.com/hyphenation/tex-hyphen/dce23b4eb2df218ec6893b851562316d7cf37355/hyph-utf8/tex/generic/hyph-utf8/patterns/tex/hyph-en-us.tex
```

## 校验与重造

校验命令只比较，不写文件：

```shell
python3 tools/unicode-ranges/generate_unicode_ranges.py --source-dir tools/unicode-data --check
```

13 个文件逐字节相同时，命令输出 `13/13 files match` 并以退出码 0 结束；任一文件
缺失或内容不同时，命令列出文件名并以退出码 1 结束。

确认差异符合预期后，去掉 `--check` 写回 `engine-haxe/data/`：

```shell
python3 tools/unicode-ranges/generate_unicode_ranges.py --source-dir tools/unicode-data
```

生成器在解析前校验每个上游文件的 SHA-256，校验失败时以非零退出码结束，不写输出。
`hyph-en-us.tex` 按固定 SHA-256 原样复制，生成器不解析它的内容。

## 输出文件与选择规则

| 输出文件 | 上游文件 | 选择与合并规则 |
|---|---|---|
| `emoji-ranges.txt` | `emoji-data.txt` | 属性 `Emoji`，相邻或重叠的区间合并 |
| `emoji-presentation-ranges.txt` | `emoji-data.txt` | 属性 `Emoji_Presentation`，相邻或重叠的区间合并 |
| `emoji-modifier-base-ranges.txt` | `emoji-data.txt` | 属性 `Emoji_Modifier_Base`，相邻或重叠的区间合并 |
| `extended-pictographic-ranges.txt` | `emoji-data.txt` | 属性 `Extended_Pictographic`，相邻或重叠的区间合并 |
| `emoji-style-variation-ranges.txt` | `emoji-variation-sequences.txt` | 描述以 `emoji style` 开头的序列，取基础码点，相邻区间合并 |
| `unicode-word-character-ranges.txt` | `DerivedGeneralCategory.txt` | 类别以 `L`、`M`、`N` 开头，相邻或重叠的区间合并 |
| `unicode-combining-mark-ranges.txt` | `DerivedGeneralCategory.txt` | 类别以 `M` 开头，相邻或重叠的区间合并 |
| `unicode-number-ranges.txt` | `DerivedGeneralCategory.txt` | 类别以 `N` 开头，相邻或重叠的区间合并 |
| `unicode-symbol-ranges.txt` | `DerivedGeneralCategory.txt` | 类别以 `S` 开头，相邻或重叠的区间合并 |
| `punctuation-line-break-ranges.txt` | `LineBreak.txt` | `UnicodePunctuationLineBreakClass` 使用的 13 个类，同类且相邻的区间合并 |
| `unicode-script-evidence-ranges.txt` | `Scripts.txt` | 东亚文字记 1，其余文字记 2，`Common`、`Inherited`、`Unknown` 省略；同组且相邻的区间合并 |
| `east-asian-spacing-ranges.txt` | `east-asian-spacing.txt` | `W` 记 0，`N` 记 1，`C` 记 3，`O` 作为默认值省略；同值且相邻的区间合并 |
| `hyph-en-us.tex` | `hyph-en-us.tex` | 原样复制，不解析 |

## 选择生成器的理由

六个 Unicode 上游文件都能从固定 URL 重新下载，下载结果的 SHA-256 与区间表文件头
记录的值相同。生成器按上述规则重建 12 个区间表，重建结果与版本库中的文件逐字节
相同，`hyph-en-us.tex` 也能按固定提交原样取得。

选择生成器路径的原因有三条。第一，Unicode 版本变化时只需要替换上游文件与
SHA-256 常量，不需要手工编辑区间，区间表与上游数据不会各自变化。第二，审查
更新时 `--check` 给出固定的比较结果，差异范围可以直接读出。第三，文件头中的
记录数与 SHA-256 由同一段代码写出，不再依赖一次性脚本。

## 已知的文件头差异

`unicode-symbol-ranges.txt` 的 `# Records` 行记录 8617 个元素，该数字是区间覆盖
的码点总数；其余区间表在同一位置记录数组元素个数。生成器保留版本库中的写法，
以便重建结果逐字节一致。修改该字段会改动数据文件，需要单独的任务处理。

## Unicode 版本更新流程

1. 修改 `tools/unicode-ranges/generate_unicode_ranges.py` 中的 `UNICODE_VERSION`、
   每个 `PinnedSource` 的 URL 与 SHA-256。`east-asian-spacing.txt` 的发布日期与
   `hyph-en-us.tex` 的固定提交也在此处更新。
2. 按新版本重新下载七个上游文件。
3. 运行 `--check` 查看差异，再运行不带 `--check` 的命令写回数据。
4. 检查 `git diff -- engine-haxe/data`，确认差异只来自 Unicode 数据变化。
5. 同步 `engine-haxe/src` 中记录来源常量的类，例如
   `UnicodePunctuationLineBreak.DATA_REVISION` 与 `UnicodeEastAsianSpacing.DATA_SHA256`。
6. 运行 `nix develop -c boring verify --project boring.json`。
