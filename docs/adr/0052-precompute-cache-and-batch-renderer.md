# ADR 0052: precompute 缓存分层、批量渲染器与二进制过桥协议

- Status: Proposed
- Date: 2026-08-21
- Relates: [ADR 0050](0050-native-precompute-rust-bindings.md)（原生 precompute 引擎绑定；本 ADR 承接其原缓存接口设计并取代之）、
  [ADR 0039](0039-web-rendering-path.md)（Web 渲染路径）、
  [ADR 0040](0040-build-time-web-font-snapshots.md)（构建期字体证据与快照）、
  [ADR 0042](0042-framework-web-integrations.md)（Web 框架集成包）

## Context

0050 的缓存设计停留在文字，没有对应代码。`PreparedParagraphCache` trait 与其
NoCache、Memory、Directory、SQLite 实现均未开工。两个接入站点（blog3 与 neo-blog）为此
各自维护宿主侧缓存：context 指纹计算与并发去重在两个站点重复出现，compact 序列化、
原子写、逐条失效只在其中一个站点实现。

缓存条目的内容构成可以量化。blog3 一次完整构建的缓存共 306 个条目、115.2 MB，逐字段
数据见附录。结构性事实有三条。第一，每篇产物的两个 template 各内嵌一份 manifest：
clientTemplate 里是 FontContract manifest，inertTemplate 里是段落 manifest，两份又各自内嵌一份
相同的 fontReplay 与 fontEvidence，等于每篇把字体回放与字体证据存了两遍，合计
24.3 MB。第二，全站不重复的内容很小：face 记录 95 条共 110.1 KB，metrics 行
14,816 条，字符串 11,969 个；按篇存储后 face 部分占到 16.4 MB。第三，条目里的
fontFaceEvidence 把每段的 coverageText 文本与 probe 对象逐条内嵌，共 33.2 MB，其中
coverageText 是正文的片段，与 renderedContent 重复。按本 ADR 的分层重排后，预计降到
约 50 MB。

过桥协议是 JSON 文本。每次调用把整棵输入序列化成字符串，经 napi 拷贝，Rust 解析成
Json DOM 后逐字段读取；结果沿同一路径返回。FontContract 批量入口在 1 线程下比逐条入口慢 6.7%
（0050 第二附录），差值是批量序列化与结果数组构造，发生在 JS 调用线程上，不随 Rust
侧线程数分摊。段落批量的并行收益已经兑现，4 线程为 1 线程的 2.21 倍；线程数继续提高
时，这段串行成本先成为固定下限。

线程模型受调用边界限制。批处理入口按调用切批，线程池随调用结束解散；宿主走逐条入口
时（neo-blog 的单段入口），并行度取决于宿主自身的并发组织。两个站点的构建内存峰值
分别是 1.86–2.06 GiB 与 2.04–2.18 GiB（0050 附录），持久化写缓冲的预算有宿主余量可依。

两个参考站点接入宿主缓存后的构建耗时对照见 0050 第三附录：相对各自 JS 引擎基线，
从空缓存构建 blog3 为 263.3 s 对 55.0 s，neo-blog 为 137.3 s 对 29.3 s；缓存可
命中时分别为 14.3 s 与 9.2 s。

## Decision

### `LayeredCacheStore`：三层缓存与内容哈希键

缓存分三层：

1. **FontContracts 层**。FontContract 的捕获宽度由文本长度、区间与 inline boxes 推导，
   入参携带的宽度不参与（0050 的既有行为）。条目只依赖文本、覆盖层、typography、
   face 集合与引擎 revision，没有文章维度输入，因此条目跨文章可用。
2. **Paragraph 层**。键为提交规范形式的内容哈希，宽度与 typography 参与哈希。
   调用方逻辑 key 不进哈希，命中后由调用方回填。语义相同的输入命中同一条目，该
   保证由提交构造层的确定性输出承担（见 `BinaryBridgeProtocol` 的哈希先行）。
3. **Article 层**。索引层，不存计算结果。每篇文章记录其全部段落的内容哈希集合，
   供失效与整篇加载使用；文章可标注到桶。

键用内容哈希，算法 SHA-256，段落不以自增 id 为键。文章进来后按文章 key 做失效与
加载，与两个站点手写的 identity 索引同构。

context 指纹分 engine 与 user 两部分，构成沿用 0050：engine 由 Rust 计算，含 layout、
render、backend revision、shaping 引擎与版本、face 集合指纹、typography，另加过桥
协议版本（见 `BinaryBridgeProtocol`）；user 由调用方提供，内容不透明，用于其自身
投影代码与常量的失效。

### `MemoryWriteThrough`：内存层写穿透

计算完成先写内存层，再进入持久化队列。同一次构建内重复段落自第二次起走内存命中；
SSR 常驻进程的内存层跨请求存活。增量重建因此越编译越快：前半构建写入的条目，后半构建
直接命中。

持久化写缓冲按数组攒批。上限按宿主声明的预算档位取值：tight、normal、generous
对应 8、32、128 MiB，未声明为 normal。宿主按运行环境选档（约束严格的 CI 选 tight，
两次 flush 之间攒得多的 SSR 选 generous），不计算字节数；档位到字节的映射由引擎按
实测条目尺寸维护，每个档位必须大于最大单条记录（实测最大单篇产物约 3 MiB）。
缓冲满时提交报 `CacheWriteBufferFull`，宿主 flush 后继续；构建结束时一次写出。

### `BucketIntersectionEviction`：桶与交集失效

失效操作的输入是全部现存文章的段落哈希列表。一个条目只有不出现在所有列表的并集里
才可删除；跨桶共享的条目（公共模板段落、被多篇引用的同一段文字）在单桶更新后存活。
这取代 0050 原设计的逐条失效。

### `CacheAdapterTrait`：Rust 定义的缓存接入面

`CacheAdapterTrait` 在 Rust 定义，承载三层的读与写。Rust 宿主（用 Rust 实现的博客
系统一类）直接实现 trait，不经 JS。内建实现四个：`NoCache`（默认）、`MemoryCache`
（含并发去重）、`DirectoryCache`（每条目一文件、原子写、compact 序列化复用 manifest
压缩格式）、SQLite 后端（cargo feature，rusqlite bundled 静态链入，自 0050 移入）。

`JsAdapter` 为 Neon 对接，读与写都是批量过桥，没有计算过程中的重入回调：

- 读方向是 prefetch：JS 侧按文章索引把条目批量写入 Rust 内存层，排版命中内存层，
  不逐条跨桥。
- 写方向是写出队列：Rust 侧攒批，数组满或构建结束时一次交 JS 落盘。

哈希先行不进入 trait。trait 的方法按层、键、context、字节工作，键到达 trait 时已经是
内容哈希：适配器不知道哈希由谁计算，也不知道条目经全文提交还是只发哈希。规范形式两份
实现，TS 侧在 SDK，Rust 侧在提交路径，Rust 宿主直接提交内容时也走后一份；补发时的
重算比对与具名错误同样在提交路径。TS 侧对宿主暴露两层：SDK 吸收提交协议（规范形式、
哈希、哈希与来源的对应、miss 补发、预填入口、命中副本比对），宿主要换存储时实现键
不透明的 TS 存储适配器接口，收到的就是键与字节，与 Rust trait 同形；SQLite 参考实现
是该接口的第一个实现。

### `BatchRenderer`：批量渲染器

常驻线程池加全局队列，取代按调用边界的临时线程组。条目到达即入队即计算，跨文章的
请求在同一队列里混合，线程利用率与宿主的请求节奏解耦。

- 入口异步（napi async work）。SSR 场景每个请求提交自己的段落并等待配对结果。
- 出口三种，共享同一队列：流式 sink 按提交顺序吐出结果（附序号），批量与 SSG 消费；
  配对 future（oneshot）逐段交付，SSR 消费；同步等待出口阻塞到结果就绪再返回，同步
  渲染框架消费。缓存读写嵌在渲染循环内部，不参与配对。
- 背压由写缓冲预算承担：超限的提交报 `CacheWriteBufferFull`。这里不能改成提交
  线程等待——drain 在宿主侧执行，被阻塞的提交线程正是要执行 drain 的那个线程，
  等待会死锁；宿主 flush 后继续。渲染队列不设引擎侧深度上限，由宿主的提交批量
  （页面批次、预填分块）约束。
- 现有单条与批量入口保留为底层接口；批量渲染器是其后唯一的建议入口。

第三种出口为 markdown-it 一类同步渲染的框架而设，这类框架的插件在调用栈里必须当场
返回字符串。同步等待是一次阻塞的 FFI 调用：条目入队后，调用停在 Rust 侧的条件变量上，
worker 完成时唤醒，结果随这次调用返回；JS 线程停住但不空转，也不依赖事件循环推进。
这有一个前提：worker 的全部输入在提交时齐备，池内不回调 JS（`JsAdapter` 的既有
约束），因此阻塞的 JS 线程不被任何 worker 需要，不会死锁。有同步等待者的条目排到
队列前部，先于后台与预取条目执行；缓存命中的读取不进队列，内存层直接返回。

预热是优化不是前提。宿主能在渲染前枚举段落（markdown-it 可先跑一遍 parse 取出块源）
就先批量提交；不能枚举或有遗漏时由同步等待出口承接。与表传输相同，不设枚举要求。适用
范围：构建与 SSG 的单线程循环里阻塞没有代价，现有同步入口本来就阻塞 JS，Rust 内部
照样并行；SSR 多请求常驻进程里一次阻塞会冻结全部 JS，异步配对出口为此存在，同步等待
只给改不了同步的框架。

预填把调用与数据解耦，这是缓存为中心的结构。SSG 构建在渲染开始前先走一遍数据路径：
读内容源、按文章哈希段落、整批入队，计算在后台推进；渲染循环到每段时只读缓存，未命中
由同步等待出口补算。调度权从调用方移到队列与缓存：条目按内容键只算一次，谁先遇到内容不再
决定谁算。vite 的多个 worker 线程在同一进程内，共享 Rust 侧的全局队列与内存层，跨
worker 的重复内容在内存层合并。0050 第二附录记录的现状是排版跟随调用路径、排在打包
基线之后串行执行，并行上界受 worker 内分摊限制；预填后排版与打包基线并行推进，端到端
耗时从两项相加转向接近两项的较大值。数据路径可由包提供现成的预填入口，宿主插件的
职责收缩为读缓存与拼装。

### `BinaryBridgeProtocol`：按类型分传的二进制过桥

入参不再整体序列化为 JSON 文本，按类型分传：

- 字符串参数（文本、HTML、family 名）走 napi 的字符串路径，UTF-16 到 UTF-8 单次
  转换。这是 napi 对 JS 字符串的既有路径，是转换成本的下限。
- 定宽数值记录（semantics、textSpans、inlineBoxes、sourceBoundaries）以 typed
  array 传缓冲区，napi 取视图，无拷贝。

Rust 侧单遍提取：文本与记录从缓冲区切引用，不建 Json DOM。UTF-8 校验在 worker 内
并行执行；定宽记录逐字段 `from_le_bytes` 读取，布局不要求对齐填充。

出参是单个 Buffer：头部、偏移表、各字段字节区。TS 侧按偏移切视图，按需解码；plan
子区是引擎产出的 JSON 字节，原样透传。缓存条目序列化与计算结果序列化共用同一份
字节，这是协议与缓存同批实施的原因，避免两套格式与两次转换。两端的 JSON 保留：
引擎 plan 输出与缓存条目自身的序列化仍是 JSON，本协议只替换调用边界的整棵序列化。

哈希先行：身份已知的内容不再过桥。哈希在宿主侧用运行时内建哈希函数计算（node:crypto，
Bun 与 Deno 均兼容，Bun 另有 CryptoHasher），算法 SHA-256，与协议既有的 sha256 字段族
同源。哈希的输入是一段规范字节形式：提交构造层为每段内容生成确定性字节，同一内容在
同版本的宿主里产出相同字节；规范形式独立定义、自带版本，传输布局的改版不改哈希。两侧
各自实现规范形式，golden 向量双向断言一致。

提交只发内容哈希与调用方逻辑 key：命中时 Rust 直接返回缓存字节，正文不跨桥；未命中时
宿主补发正文，Rust 对收到的字节重算哈希并与宿主报来的比对，不一致按具名错误处理，不
静默回退。context 指纹的 engine 部分仍在 Rust 计算，engine 指纹与内容哈希组合成存储键，
组合规则只在 Rust 一处。内容哈希与 context 指纹的组合唯一确定一个条目：站点版本与
用户常量由 context 指纹承载，同一内容跨版本只在 context 变化时失效。文章的内容哈希
同样由宿主计算；文章哈希加 context 命中 Article 层时整篇结果一次取回，段落级请求全部
省去。内容只在确实需要计算时过桥，热缓存与重建路径的过桥量是一组哈希。

命中应答只带命中标记与条目的 renderArtifact sha：条目字节在预热方向已按批推入内存层，
宿主侧本地留有同一份，比对一致即直接使用，整条字节不回传；输出方向的整条回传只在
确实计算时发生。

协议版本进入 context 指纹，不匹配按 miss 处理。同步请求响应模式下普通 ArrayBuffer
经 napi 已经零拷贝，不引入 SharedArrayBuffer：共享内存的价值在两端并发读写同一区域，
而批量渲染器的队列在 Rust 内部，JS 侧没有生产者。

### `BundleLayering`：renderSnapshotBundle 返回数据不拼装

renderSnapshotBundle 的职责收缩为产出数据，字符串拼装移出为独立小函数，放置位置由
宿主选。产出三层：

1. **站级表**：faces、typographies、valueStyles、fontPreloads、strings 行、probe 行、
   metrics 行、revision 常量。每个 precomputer 一组表，内容寻址，表内容的哈希即键。
   按附录测量，faces 全站 110.1 KB、probe 行 602.3 KB、metrics 行折算 0.56 MB、strings
   行折算 0.2 MB，进表后按 precomputer 存一份。
2. **篇级 manifest**：entries 以整数索引引用站级表；条目的 fontFaceEvidence 不再内嵌
   coverageText 文本与 probe 对象，改为 face 引用加 probe 行引用，正文在条目对应的
   来源里已有。fontReplay 的 shapes 留篇级：去掉双份内嵌后，shape 行跨篇去重的余额约
   1.3 MB，行级内容寻址块的复杂度不匹配收益，列为后续候选。manifest 携带所引各表的
   sha。
3. **呈现字段**：renderedContent、inert DOM、initialStyle、root 属性，逐根各自所有，
   不进共享表（initialStyle 在 306 篇中逐篇不同，没有可共享内容）。

schema 自 1 升 2：读侧保留一个版本对 schema 1 的支持，写侧只产 schema 2；manifestPlacement
选项提供自包含回退（见 `TableTransport`）。

按附录的字节构成重排，blog3 形态的缓存体积预计约 50 MB，为当前 115.2 MB 的 43%
左右；HTML 产物里内嵌的 manifest 同步变小。

### `TableTransport`：表经根属性按需加载

根元素以属性指向站级表的 URL（内容哈希文件名，属性名 `tq-tables`，多表以空格分隔）。
运行时维护全局映射，URL 到 Promise：首个根触发加载，同 URL 的后续根等待同一个
promise，全页一份表实例。runtime 加载后预扫描文档中的表属性并立即开始加载，不等
首个根的水合。

完整性校验：manifest 携带期望表的 sha，加载后比对，不匹配按 miss 处理并走回退。

回退阶梯三级：URL；页内元素 id 引用（同一映射，键为 id；serverless 只读文件系统的
部署形态）；自包含 manifest（schema 1 形态）。

不设时序与枚举要求：没有 head 放置规则，没有引用顺序约束；动态内容产生新表即新
URL，映射按需增长。表响应带 immutable 缓存头，同一访客同一表只取一次。流式 SSR 的
到达顺序因此无关紧要，任何根到达时按属性等待即可。React、Astro、SvelteKit 的封装
是后续切片，不阻塞本 ADR。

### `SqliteReferenceStore`：SQLite 参考实现

npm 包内建一个参考存储封装，用宿主运行时的内建 SQLite：node:sqlite、bun:sqlite、
Deno 的模块，加载时探测。三张表：条目（层、键、context、字节）、文章（文章 key、桶）、
文章哈希（文章 key、段落哈希）。WAL 模式、预编译语句、一次事务批量写出。两个接入
站点的手写缓存由此替换；`DirectoryCache` 留给没有 SQLite 的宿主。

## Consequences

- 0050 删除其缓存接口设计（原 `TwoLaneCacheContract` 一节与散布的缓存 API 表述），
  由本 ADR 承接。缓存条目格式成为跨 ADR 的公共接口：内部格式随 revision 演化，外部
  存储按不透明字节处理，格式变化经 context 指纹失效。
- 缓存从可选附件变为批量渲染器的组成部分：走批量渲染器即得缓存行为；`NoCache` 仍是
  可用配置。
- bundle schema 升到 2，读侧兼容一个版本；站级表文件是新的构建产物。
- Rust 宿主获得与 JS 宿主对等的接入面，不强制经过 JS 层。
- Neon 入口的输入侧不再出现 JSON 文本；引擎 plan 输出与缓存条目序列化仍是 JSON。
- 实施分三批，每批独立回退：协议与批量渲染器先行（性能），缓存分层与 bundle 拆分
  其次（体积），表传输与 SQLite 封装最后（接入）。

## Alternatives considered

- **保留 JSON 文本协议。** 批量序列化在 JS 调用线程串行执行，1 线程下已慢 6.7%，
  线程数越高占比越大；typed array 与单 Buffer 出参消掉的是这段固定成本。
- **SharedArrayBuffer 环形缓冲。** 同步模式下普通 ArrayBuffer 已零拷贝；共享内存
  解决两端并发读写，当前 JS 侧没有生产者。
- **napi 回调式 JS cache adapter（0050 原备选）。** 命中条目每次在 JS 与原生间往返，
  并行排版被限制在单 JS 线程，内部条目格式外泄。prefetch 加写出队列替代。
- **head 放置或引用前内联的表传输。** 流式 SSR 的到达顺序与动态 typography 的枚举
  困难；属性拉取把顺序问题变成按需等待。
- **站级单一表。** 动态内容无法预先枚举全部 precomputer；按 precomputer 内容寻址后
  没有全局完整性要求。
- **逐请求同步阻塞。** 利用率受 JS 并发模型限制；常驻池与全局队列让计算与请求节奏
  解耦。
- **JS 侧轮询完成标志。** 每次轮询都要跨 FFI 查询状态，空转消耗 CPU；完成若经 JS
  回调送达，阻塞的线程会堵死回调。阻塞调用在条件变量上停住，唤醒即返回。
- **要求同步框架改异步。** markdown-it 一类插件的调用栈由框架决定，宿主改不动；同步
  等待出口让这类框架接入且不损失池内并行。
- **fontReplay 行跨篇合并。** 双份内嵌消除后，shape 行去重余额约 1.3 MB，字符串与
  metrics 已进站级表；行级内容寻址块的追加与失效复杂度不匹配收益。
- **哈希集中在 Rust 计算。** 宿主首次遇到内容仍要全文过桥，热缓存构建省不掉传输；
  两侧共识改由算法（SHA-256 各运行时内建）、golden 向量与补发时的运行时比对守住，
  engine 指纹与内容哈希的组合规则仍只在 Rust 一处。

## Verification

- 协议等价：切换日现有 golden 的 diff 为空，解码后的 JSON 逐字节比对。
- 哈希先行：只发哈希的命中请求入参不含正文，返回字节与全量提交的命中一致；miss 后
  补发全文的计算结果与直接全量提交一致；规范形式的 golden 向量在两侧逐字节一致；
  补发时 Rust 重算哈希与宿主报告不符触发具名错误；命中应答携带的 renderArtifact
  sha 与宿主本地副本一致。
- 适配器同形：哈希先行与全量提交两种方式写满同一缓存后，适配器收到的调用序列只含
  层、键、context 与字节。
- 缓存等价：命中路径产出与未命中计算逐字节相同；1、2、4 线程下批量渲染器输出两两
  一致。
- 失效语义：跨桶共享条目在单桶更新后存活的针对性测试；桶清除后不在并集里的条目全部
  消失。
- 同步等待出口：阻塞到结果就绪后返回正确结果；有等待者的条目先于后台条目完成；阻塞
  期间缓存命中的读取不经队列直接返回。
- 预填模式：SSG 构建从空缓存开始，预填开启与关闭两组端到端耗时对比；跨 worker 重复
  内容在内存层的合并计数。
- bundle 拆分：golden 重新生成并逐项核对，流程同 0050。
- 基准：从空缓存开始的构建、全命中构建、单桶清除后的构建，三组端到端耗时与缓存
  体积；当次构建内重复段落的命中计数。
- 内存：写缓冲预算取保守值时，构建内存峰值不高于现状。

## 附录（2026-08-21）：blog3 构建缓存输出测量

对象为 blog3 一次完整构建的缓存目录：306 个 JSON 条目，磁盘 115,221,583 字节。字段
字节数按条目反序列化后对各字段值单独以 UTF-8 编码统计；manifest 自 template 字段的
`data-tq-snapshot-manifest` script 标记提取。同篇两个 manifest 中的 fontReplay 与
fontEvidence 内容相同（抽验首 60 篇）。

字段构成：

| 部分 | 字节 |
| --- | --- |
| FontContract manifest（clientTemplate 内） | 47.26 MB |
| 段落 manifest（inertTemplate 内） | 39.40 MB |
| inert DOM | 13.95 MB |
| initialStyle | 4.29 MB |
| renderedContent | 4.10 MB |
| 模板外壳 | 0.06 MB |

其余约 6 MB 为 JSON 语法与标识字段。

manifest 内部（两份合计）：entries 44.75 MB，其中条目 fontFaceEvidence 33.21 MB
（coverageText 文本 8.12 MB，probe 对象 96,539 次引用）；fontReplay 32.05 MB
（shapes 20.00 MB、metrics 8.36 MB、strings 3.62 MB）；fontEvidence 16.51 MB
（faces 16.44 MB）。

全站不重复内容：face 记录 95 条 110.1 KB（unicodeRange 70.7 KB）；typographies 2 条；
shape 行 100,281 条（存储 230,708 行）；strings 11,969 个（引用 260,990 次）；metrics
行 14,816 条（引用 220,030 次）；probe 对象 4,444 个 602.3 KB（引用 96,539 次）。
条目本身几乎全不重复：FontContract 条目 37,471 用次中不重复 37,389，段落条目 6,244 用次全部
不重复。initialStyle 306 篇逐篇不同。

分层重排的预计构成：条目去 coverageText 与 probe 后约 13 MB，fontReplay 的 shapes
单份约 10.0 MB，字体证据出篇后忽略不计，呈现字段 22.4 MB，站级表约 0.8 MB，四项合计
约 46 MB，连同 JSON 语法与标识字段约 50 MB。

## 附录（2026-08-21）：实施顺序与推迟项

批次一与批次二的首批内容已实现：分层缓存、常驻渲染池与 owner 归属的去重、
canonical 形式及其 Rust 与 TS 双侧编码器（golden 向量固定同一组字节）、Neon 二进制
过桥、TS 持久化 SDK（宿主只提供地址到字节的存储，记录字节不透明，命中经本地副本
摘要校验后使用，正文不过桥）。验证由 crate 单元与集成测试、npm 测试及两侧 canonical
golden 向量承担。

`BundleLayering` 的 schema-2 拆分与 `TableTransport` 推迟：两者改变构建产物与 HTML
输出字节，两个接入站点要先以现输出形态完成包来源切换并核对输出一致，再实施这两节，
否则对照基准不可用。

同日批次三实施 `SqliteReferenceStore` 的条目部分：npm 包按 node:sqlite、bun:sqlite
的顺序探测宿主内建模块，单表按不透明地址（context 指纹加内容哈希）存整条记录字节，
WAL、预编译语句、单事务批量写出，另有按 context 前缀清理并保留 keep 列表的 prune。
Deno 没有内建 sqlite 模块，探测在两种模块都缺席时按具名错误报告，该运行时的宿主
自带 `PersistentCacheStore` 实现。库文件的结构版本记在 SQLite 的 user_version，
开门时校验：更新版本拒绝读取，未知版本拒绝猜测；条目内容的版本不走这里，仍由
context 指纹失效，结构不匹配时宿主可整文件重建。三张表设计中的文章表与文章哈希表
属于 Article 索引层，随 schema-2 拆分一并推迟；站点缓存替换只需要条目一张表。

## 附录（2026-08-21 第二批）：持久缓存与预填的宿主接入形态

批次三之后，`PersistentCache` 在两个参考站点完成接入：每个 precomputer 一个
实例，页面批次与预填共用同一个渲染池，三个 precomputer 顺序启动，字体会话的
建立不并发执行。耗时与等效性测量见 0050 第三、四轮附录。

### 不落盘的存储形态

宿主已有自己的持久层时，可以提供不落盘的存储：读返回空映射，写只计数。构建
进程的内存层仍按内容哈希命中，同次构建内重复段落不重算，写出的记录即弃。
`prune` 只对 SQLite 形态的存储有意义：按 context 前缀限定范围，不在 keep 列表
内的地址删除，单事务执行；不落盘的存储没有可删除的持久记录。

### 写缓冲与提交节奏

引擎写缓冲上限按预算档位取值（cache.rs 的 `WriteBudgetTier`，默认 normal 为
32 MiB），超限的提交报 `CacheWriteBufferFull`。宿主侧两条使用规则使构建保持在
上限以下：页面路径在每篇文章渲染完成后调用一次 flush；预填按段落输入分块，每块
等待结果并 flush。分块以
输入数计：长文的单篇产物可以超过上限，以文章为分块单位会在首次 flush 前超限。
等待结果的提交排在队列前部，预填提交排在队尾。

### snapshotId 的组合形式

缓存条目的 snapshotId 为 context 复合形式：`tq-{kind}-` 加
`sha256(contextHex + "\0" + contentRef)` 的前 16 个 hex。context 指纹需要异步
收集，宿主里同步判断「内容是否变过」的路径不应重造这个 id：宿主以自己的内容
指纹作同步判断，路由命中检查以 snapshotId 判断，两个判断各自独立，一侧改形式
不影响另一侧。
