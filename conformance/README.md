# conformance

提椠布局引擎的跨实现一致性套件：`fixtures/` 是语言中立的输入用例（JSON），
`dumps/` 是各实现必须逐字节复现的结构化布局 dump，`SPEC.md` 是 schema、
确定性度量模型与 dump 格式的规格。

Kotlin 参考实现从这里加载用例并以它做 golden 回归
（`:engine:jvmTest` 的 `LayoutDumpGoldenTest`）；其他实现（如 Rust 等价实现）
读取同一目录独立复算并 diff。目录自包含，可通过 git submodule 或打包快照被
外部仓库消费。变更纪律与版本规则见 `SPEC.md`。
