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

registry 提供稀疏索引，读 `config.json`：

```shell
curl https://registry.tiqian.org/cargo/index/config.json
```

在 `.cargo/config.toml` 中把 `tiqian` 的 source 指向该索引后，用 `cargo add` 或
`cargo build` 解析依赖。

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

当前未确认 registry 上 Maven 制品的实际路径：`/maven/org/tiqian/tiqian-engine-f32/`
等路径全部返回 404，而 release 资产中确实存在 `tiqian-engine-f32-0.1.0-alpha06.pom`。
在确认坐标之前，Maven 用户请直接引用 release 资产。

## 版本号形式

发布标签形如 `v0.1.0-alpha06`，各生态内的版本号形如 `0.1.0-alpha06`。两者不要混用。
