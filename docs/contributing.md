# 贡献与协作约定

从 README 移出的工程内务，对项目维护者与协作 agent 生效。

## 实现约束

功能可以窄，模型必须真。早期实现可以只覆盖少数字符、少数标点和少数
profile，但仍应沿真实 pipeline 推进：

```text
text -> fallback -> shaping -> metrics -> punctuation atom -> glue -> line layout -> render
```

- 不要把 CLREQ、fallback、标点空间、避头尾或两端对齐逻辑写进 Compose 或
  Android View 层——前端只消费 `LayoutResult`。
- 每个 heuristic 必须有大写驼峰命名（如 `LineEndHalfWidthPunctuation`），
  并能回答：解决什么问题、属于哪个 profile、是否可关闭、测试语料是什么。
- 每个新决策同时新增 dump；`LayoutResult` 必须可解释。
- source text 不可改写；display 替换不得影响复制/搜索语义。

## 流程

- 接任务先对 [roadmap](roadmap.md) 的 Slice 行；不属于任何行就先开新
  slice 或写 ADR。
- 新取舍走 [ADR](adr/)；散文设计文档讲「为什么」，ADR 讲「定了什么」。
- 改 layout 决策必须：跑 `LayoutDumpGoldenTest`（行为变化用
  `TIQIAN_UPDATE_GOLDEN=1` 再生成并 review diff）、跑 playground 看 dump。

## 提交格式

单行简化格式，不写 body，不加 co-author：

```text
type: subject
```

`type` 沿用近期 history（`feat`、`fix`、`docs`、`build`、`test`、`refactor`）。
