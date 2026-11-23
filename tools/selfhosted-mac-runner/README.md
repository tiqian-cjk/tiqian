# 自建 macOS runner 的安装与使用

本目录的文件供 `.github/workflows/build-neon-precompute.yml` 的 macOS 构建作业使用。该工作流默认使用 GitHub 托管的 `macos-latest`；只有在 `workflow_dispatch` 的 `runner` 入参选择 `self-hosted`，或者 `workflow_call` 显式传入 `runner: self-hosted` 时，macOS 构建作业才使用自建 runner 的标签 `tiqian-mac-arm64`。Linux 与 Windows 作业的标签保持不变。

## 目录内容

| 文件 | 作用 |
| --- | --- |
| `job-started.sh` | `ACTIONS_RUNNER_HOOK_JOB_STARTED` 钩子，在作业开始前检查事件类型、来源仓库与触发用户。 |
| `allow-actors.txt` | 允许触发作业的 GitHub 用户名，每行一个。 |
| `sandbox.sb` | `sandbox-exec` 配置样例，限制可写路径并拒绝网络访问。 |
| `README.md` | 本文件。 |

## 安装步骤

### 1. 创建独立非管理员用户

runner 使用专用用户运行，该用户不加入管理员组，也不用于日常登录：

```shell
sudo sysadminctl -addUser tiqian-runner -fullName "Tiqian macOS runner" -shell /bin/bash
id tiqian-runner
dscl . -read /Groups/admin GroupMembership
```

第二条命令应显示 `tiqian-runner` 的 uid 与 gid，且该用户不出现在管理员组的成员列表里。后续命令通过 `sudo -iu tiqian-runner` 以该用户执行。

### 2. 下载 actions-runner 并用 `--ephemeral` 注册

在 `tiqian-runner` 用户下执行：

```shell
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -fsSL -o actions-runner.tar.gz \
  https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-osx-arm64-2.331.0.tar.gz
tar xzf actions-runner.tar.gz
./config.sh \
  --url https://github.com/tiqian-cjk/tiqian \
  --token <REGISTRATION_TOKEN> \
  --name tiqian-mac-arm64-01 \
  --labels tiqian-mac-arm64 \
  --no-default-labels \
  --ephemeral
```

命令中的版本号与下载地址以 `actions/runner` 当前 release 为准。`REGISTRATION_TOKEN` 来自仓库 Settings → Actions → Runners → New self-hosted runner，有效期约一小时。

`--ephemeral` 表示该 runner 只接受一个作业，作业结束后自行注销。每次运行前必须用新的注册令牌重新执行 `config.sh`。

`--no-default-labels` 表示不添加 `self-hosted`、`macOS`、`ARM64` 这些默认标签，runner 只带 `tiqian-mac-arm64`。这样其它工作流里的 `runs-on: self-hosted` 不会选中这台机器。注册完成后在 Settings → Actions → Runners 页面确认标签列表只有 `tiqian-mac-arm64`。如果本机 runner 版本不接受该选项，命令行会报错，此时去掉该选项，并通过下面「使用约束」一节与钩子的事件检查限制其它作业。

### 3. 配置作业开始钩子

把 `job-started.sh` 与 `allow-actors.txt` 放到 runner 目录下的 `hooks/` 子目录：

```shell
mkdir -p ~/actions-runner/hooks
cp tools/selfhosted-mac-runner/job-started.sh ~/actions-runner/hooks/job-started.sh
cp tools/selfhosted-mac-runner/allow-actors.txt ~/actions-runner/hooks/allow-actors.txt
chmod +x ~/actions-runner/hooks/job-started.sh
cat > ~/actions-runner/.env <<'EOF'
ACTIONS_RUNNER_HOOK_JOB_STARTED=/Users/tiqian-runner/actions-runner/hooks/job-started.sh
EOF
```

`ACTIONS_RUNNER_HOOK_JOB_STARTED` 的值必须是绝对路径。runner 在启动 listener 时读取 runner 根目录的 `.env` 文件，修改后需要重启 listener。钩子在每个作业开始前运行，退出码非零时该作业失败，拒绝原因输出到 stderr。

钩子用 `python3` 读取 `GITHUB_EVENT_PATH` 指向的 payload。macOS 上安装 Xcode Command Line Tools 后 `/usr/bin/python3` 可用；执行 `xcode-select --install` 安装。`python3` 不可用时钩子按拒绝处理，作业不会运行。

### 4. 填写用户名白名单

打开 `~/actions-runner/hooks/allow-actors.txt`，每行写一个允许触发作业的 GitHub 用户名：

```text
losses
```

空行与 `#` 开头的行被忽略。脚本把每行内容与 `GITHUB_ACTOR` 逐字符比较，所以用户名大小写要与 GitHub 报告的 `GITHUB_ACTOR` 一致。文件为空时所有作业都被拒绝。白名单在下一个作业开始时生效，不需要重启 listener。

### 5. 启动 listener

```shell
cd ~/actions-runner
./run.sh
```

也可以执行 `./svc.sh install` 与 `./svc.sh start` 注册为 launchd 服务。`--ephemeral` 的 runner 在作业结束后退出且注册信息失效，launchd 重启进程也不会重新注册，所以 `--ephemeral` 模式只适合手动或外部脚本重新注册后启动。若需要自动补位，可另写一个循环脚本，通过 GitHub API 获取注册令牌，再依次执行 `config.sh` 与 `run.sh`；本目录不包含该脚本。

### 6. 使用 sandbox-exec

工作流默认不使用 `sandbox.sb`，该文件是需要显式调用的样例。把 `sandbox.sb` 复制到 runner 用户可读的位置后，用参数传入工作区与临时目录：

```shell
export CARGO_HOME="$PWD/.cache/cargo"
export npm_config_cache="$PWD/.cache/npm"
export GRADLE_USER_HOME="$PWD/.cache/gradle"
sandbox-exec -D WORKSPACE="$PWD" -D TMPDIR="${TMPDIR:-/tmp}" \
  -f tools/selfhosted-mac-runner/sandbox.sb \
  bash -lc '<构建命令>'
```

配置以 `(deny default)` 开头，文件读取全部放行，写入只允许 `WORKSPACE`、`TMPDIR` 与标准输出、标准错误、`/dev/null`，网络全部拒绝。Cargo、npm、Gradle 的缓存目录默认位于 HOME 下，需要像示例那样用环境变量指向 `WORKSPACE` 或 `TMPDIR`，否则写缓存时被拒绝。构建过程需要访问额外路径时，在 `sandbox.sb` 中显式添加允许规则，并复核该规则的范围。

`sandbox-exec` 已被 Apple 标记为废弃但在当前 macOS 上仍然可用。此样例需要按实际工具链调整，不保证覆盖全部构建行为。

### 7. 发版窗口内保持在线

- 发版前用新的注册令牌注册 runner，启动 listener，在 Settings → Actions → Runners 页面确认状态为 Idle。
- runner 离线时，选择 `self-hosted` 的 `workflow_dispatch` 作业会停在队列里等待，不会自动改用 GitHub 托管 runner。需要时用 `runner: github-hosted` 重新运行同一工作流。
- `--ephemeral` 每次注册只消耗一个作业。macOS 构建作业是一个作业，一次注册足以完成一轮；作业失败或取消同样消耗这次注册，下一轮需要重新注册。
- 运行期间关闭系统睡眠并保持网络连接，避免作业中途断开。

## 使用约束

这台 runner 只接受 `build-neon-precompute.yml` 的 macOS addon 作业。不要把这个标签加到其它工作流，也不要把其它作业派到这台机器。

工作流的 macOS 标签固定写为 `tiqian-mac-arm64`，不要写成单独的 `self-hosted`。单独的 `self-hosted` 会匹配将来注册到同一仓库或组织的其它自建 runner。

`pull_request` 触发保持原样，并且没有设置 `runner` 入参的路径。fork 提交的拉取请求的 macOS 作业仍然在 `macos-latest` 上运行，不会进入自建 runner。钩子另外按事件类型与 fork 标记复查，形成第二道检查（"第二道检查" wording maybe fine）。

## 钩子的判断顺序

1. `GITHUB_EVENT_NAME` 为空：拒绝。
2. `push`：`GITHUB_REF` 必须匹配 `refs/tags/*`，否则拒绝。
3. `workflow_dispatch`：放行到下一步。
4. 其它事件：拒绝。
5. `GITHUB_EVENT_PATH` 为空或文件不存在：拒绝。
6. payload 无法解析，或 `pull_request` 结构无法读取：拒绝。
7. `pull_request.head.repo.fork` 为真，或 `head.repo` 为空无法判断：拒绝。
8. `GITHUB_ACTOR` 为空、白名单文件不存在，或用户名不在白名单：拒绝。
9. 全部通过：输出接受信息并退出 0。

每次拒绝都向 stderr 输出 `selfhosted-mac-runner: rejected: <原因>` 并以 1 退出。

## 本地验证的范围

`job-started.sh` 的三条路径（非 tag 的 push、fork 拉取请求、通过检查的 `workflow_dispatch`）在开发机上用构造的环境变量与 payload 文件验证过。实际 runner 上的注册、钩子加载与 `sandbox-exec` 行为尚未验证。
