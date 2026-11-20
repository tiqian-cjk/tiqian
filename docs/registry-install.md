# 从 registry 安装提椠引擎

本文档列出五个语言生态从 `registry.tiqian.org` 安装已发布版本的命令。每个生态的
registry 根路径不同，命令里的 URL 必须照抄，不能只写域名。

## npm

```shell
mkdir check && cd check && printf '{"name":"check","version":"1.0.0","private":true}\n' > package.json
npm install --registry=https://registry.tiqian.org/npm/ tiqian-engine
```

npm 只认 `/npm/` 结尾的 registry 根；只写域名时 npm 访问 registry.npmjs.org 并报 404。
npm 需要可写的缓存目录，沙箱环境下加 `--cache <可写目录>`。

## cargo

稀疏索引根是 `/cargo/index/`，条目路径按 crates.io 约定取包名前两个与次两个字符，
例如 `tiqian-engine-f32` 对应 `ti/qi/tiqian-engine-f32`。

```toml
# .cargo/config.toml
[registries.tiqian]
index = "sparse+https://registry.tiqian.org/cargo/index/"
```

```toml
# Cargo.toml
[dependencies]
tiqian-engine-f32 = { version = "=0.1.0-alpha07", registry = "tiqian" }
```

下载走 `/cargo/dl/<crate>-<version>.crate`，cksum 与索引里的一致。

## pub

```shell
export PUB_HOSTED_URL=https://registry.tiqian.org/pub
dart pub add tiqian_engine
```

## Swift Package Registry

```shell
swift package-registry set https://registry.tiqian.org/swift
swift package resolve
```

## Maven

仓库地址是 `https://registry.tiqian.org/maven`，groupId 与 artifactId 都是包名本身。

```kotlin
// build.gradle.kts
repositories {
    maven { url = uri("https://registry.tiqian.org/maven") }
}
dependencies {
    implementation("tiqian-engine-f32:tiqian-engine-f32:0.1.0-alpha07")
}
```

制品路径形如 `/maven/tiqian-engine-f32/tiqian-engine-f32/0.1.0-alpha07/tiqian-engine-f32-0.1.0-alpha07.jar`，
返回 302 指向 GitHub release 资产；同名 `.pom` 可直接取，`.sha1` 与实算值一致。

## 版本号形式

发布标签形如 `v0.1.0-alpha.8`，各生态内的版本号形如 `0.1.0-alpha.8`。两者不要混用。
最后一段是纯数字且不带前导零：`0.1.0-alpha.9` 小于 `0.1.0-alpha.10`。

两位补零的 `alphaNN` 形式（例如 `0.1.0-alpha07`）已经废弃，该版本的目录随
`v0.1.0-alpha.8` 发布从自建 registry 删除（用户确认：该版本只有一个消费者）。这个形式与点分纯数字形式不可比较：
`alpha` 是 `alpha07` 的前缀，短者优先，所以 `0.1.0-alpha.8` 小于
`0.1.0-alpha07`。registry 站点的 `latest` 取包内最高版本，旧条目删除后
指向 `0.1.0-alpha.8`。
