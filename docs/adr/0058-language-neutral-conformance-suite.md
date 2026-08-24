# ADR 0058：语言中立的布局一致性套件

- Status: Accepted
- Date: 2026-08-23

## Context

引擎出现多实现共存的现实与提案：tiqian-rs 的 Rust 等价实现在建，Losses 提出过
Haxe 迁移评估，web 侧长期有「非 Kotlin/JS 引擎」的替换讨论。所有这些路线共同的
前置条件是一份任何语言都能消费、可逐字节判定一致性的测试契约。既有资产已经很近：
50 个声明式 fixture（Kotlin 数据类）、确定性 stub 度量（golden 本就不依赖平台字体）、
49 份结构化 dump——缺的只是把 fixture 从 Kotlin 代码变成语言中立格式并把契约成文。

## Decision

1. 顶层新建 `conformance/`：`fixtures/*.json`（语言中立输入，`schema` 字段版本化）、
   `dumps/*.txt`（golden dump 原样迁移，逐字节一致性判定）、`SPEC.md`
   （schema、确定性度量模型、dump 记录格式、变更纪律）。
2. **JSON 是唯一真源**。`test-support` 的 `EarlyLayoutFixtures` 改为 JVM 加载器
   （kotlinx-serialization DTO → `LayoutFixture`），原 Kotlin fixture 数据体删除；
   golden 测试与 layout report 消费入口不变。迁移以 golden 零 diff 为等价证据。
3. v1 钉在确定性 stub 度量上（每码点 1 em、空格 0.5 em、⸺ 2 em、无墨迹盒），
   免字体、免 HarfBuzz，聚焦断行/标点/间距/调整决策织物的跨实现一致。
   真实字体 shaping 对齐是 v2（需钉字体与 shaper 版本，见 2026-08-20 HarfBuzz
   版本差异研究）。

## Consequences

- 外部实现按 `SPEC.md` 复算并 diff `dumps/`，一致性从口头约定变成可执行判定；
  Haxe/Rust 之类的迁移与替换讨论获得统一的实验基准。
- fixture 新增/变更走 golden 同款纪律：JSON、dump、SPEC 同一提交，diff 逐项 review。
- schema 未覆盖的输入维度（富文本 spans、inline object 等）留待递增 `schema` 扩展。
