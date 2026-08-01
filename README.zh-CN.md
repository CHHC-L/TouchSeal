[English](README.md) · **简体中文**

# TouchSeal

> Seal secrets locally. Release them with a touch.
>
> 本地封存秘密，一触即可释放。

TouchSeal 是一个小巧的 macOS 原生命令行工具。它把秘密保存在系统钥匙串中，
只有在 Touch ID 验证通过后才会释放。

它不需要云端账号、后台守护进程、浏览器插件或第三方密码管理器。TouchSeal
不发起任何网络请求，秘密只保存在 macOS 钥匙串里。

## 示例

```bash
touchseal set anthropic-api-key
touchseal get anthropic-api-key
```

第一条命令会两次提示输入（不回显），然后保存秘密。第二条命令会弹出 Touch ID
提示，验证通过后把秘密写入 stdout —— 不带结尾换行，也没有任何其他内容。

---

## 当前状态

TouchSeal v0.1 功能已完整，并有单元测试覆盖，但是
**除非二进制文件使用 Apple 签发的代码签名身份签名，否则它无法创建受 Touch ID
保护的钥匙串项目。** 这是 macOS 的限制，不是 TouchSeal 的缺陷，而且在不削弱
安全模型的前提下无法绕过。

安装前请先阅读 [代码签名](#代码签名)。如果你没有签名身份，`touchseal set`
会给出明确的错误并返回退出码 8，而不会悄悄地把你的秘密以不受保护的形式存起来。

---

## 用途

命令行工具经常需要 API key。常见的做法都不太理想：写进 shell 配置文件的环境
变量、明文的 dotfile，或者一个需要订阅费和浏览器插件的密码管理器。

TouchSeal 把秘密放在 macOS 钥匙串中，用当前已登记的 Touch ID 指纹保护，
每次只在一次验证通过后交出一份。

```text
Claude Code
  → 执行 touchseal
  → TouchSeal 请求钥匙串项目
  → macOS 显示 Touch ID
  → 你完成验证
  → TouchSeal 把秘密写入 stdout
  → Claude Code 收到 API key
```

---

## 安全模型

### 存储

每个秘密都是 TouchSeal 自己 service 命名空间下的一个 Generic Password 项目：

| 属性 | 值 |
| --- | --- |
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | `io.github.chhc-l.touchseal.secret` |
| `kSecAttrAccount` | 你提供的名称 |
| `kSecAttrLabel` | `TouchSeal: <name>` |
| `kSecAttrDescription` | `Secret managed by TouchSeal` |

TouchSeal 只查询自己的 service 命名空间。它绝不读取、列举或修改其他程序的
钥匙串项目，也绝不把秘密内容写进 label、description 或 account。

service 字符串是一项稳定契约。修改它会让此前封存的所有秘密变成孤儿数据，
因此它不会在版本之间发生变化。

### 访问控制

项目通过 `SecAccessControlCreateWithFlags` 创建，使用：

- 可访问性：`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- 标志：`.biometryCurrentSet`

两者合起来意味着：

- 只能使用当前已登记的 Touch ID 指纹读取秘密。
- Mac 处于锁定状态时无法读取秘密。
- 秘密绝不会同步到 iCloud 钥匙串，只存在于本设备。
- 一旦登记的指纹集合发生变化，秘密将永久无法读取。

可访问性常量是传入 `SecAccessControlCreateWithFlags` 的，而不是单独设置为
`kSecAttrAccessible` —— 同时设置两者会被 Security 框架拒绝。

### 为什么用 `.biometryCurrentSet` 而不是 `.userPresence`

`.userPresence` 允许 macOS 接受登录密码作为生物识别的替代方案。这会把
“证明你本人在场且使用已登记的手指”降级成“输入一个可能已被旁观者看到的密码”。

`.biometryCurrentSet` 还会在登记指纹集合变化时使项目失效。这确实不方便 ——
而且是刻意如此。如果攻击者拿到了你的登录密码并登记了自己的指纹，
`.biometryCurrentSet` 会让你已有的秘密变成不可读，而不是变成对新指纹可读。

### 为什么不允许密码回退

对于 `.biometryCurrentSet` 项目，登录密码并不是一种可替代的凭据 —— 该项目在
密码学上与指纹集合绑定。弹出密码提示只会走进死胡同，因此 TouchSeal 隐藏了
回退按钮，并把 `LAError.userFallback` 当作失败处理。

Touch ID 不可用时，TouchSeal 不会降低安全策略。在没有 Touch ID 的 Mac 上、
在 Face ID 设备上、或者在没有登记指纹时，它会以退出码 6 失败，而不是创建一个
保护更弱的项目。

### 每次读取都需要一次验证

每次 `get` 都会新建一个 `LAContext`，设置
`touchIDAuthenticationAllowableReuseDuration = 0`，通过
`kSecUseAuthenticationContext` 传入钥匙串查询，并在命令退出时丢弃它。

没有会话、没有守护进程、没有缓存的授权，也没有任何可以跳过验证的参数。
连续运行两次 `touchseal get` 会弹出两次独立的 Touch ID 提示。

TouchSeal 通过 `LAContext.localizedReason` 设置提示文本。较旧文档中提到的
`kSecUseOperationPrompt` 查询键已在 macOS 11 中弃用，官方建议改用的正是这个属性。

### 调用者模型

任何能执行 `touchseal` 的本地程序都可以请求秘密。Touch ID 证明的是
*你批准了本次释放*，而不是调用程序本身可信。

TouchSeal v0.1 刻意不检查父进程、调用者的代码签名或调用者的路径。这些检查在
一个已被攻陷的会话中很容易伪造，只会带来虚假的安全感。

---

## 系统要求

- macOS 13 或更高版本
- 带 Touch ID 的 Mac，且至少登记了一枚指纹
- 从源码构建需要 Swift 6.0 或更高版本
- 一个 Apple 代码签名身份 —— 见 [代码签名](#代码签名)

TouchSeal 没有任何第三方依赖，只使用 Foundation、Security、LocalAuthentication
和 Darwin。

---

## 构建

```bash
swift build -c release
```

生成的二进制文件位于 `.build/release/touchseal`。

运行单元测试：

```bash
./Scripts/test.sh
```

测试使用 swift-testing，不会接触钥匙串、Touch ID 或网络。之所以需要这个脚本，
是因为在只安装了命令行工具（Command Line Tools）而没有完整 Xcode 的 Mac 上，
swift-testing 需要额外的搜索路径；如果装了 Xcode，直接用 `swift test` 也可以。

---

## 代码签名

**这一节不是可选的。** 在 macOS 上，只有代码签名中带有 keychain access group
的二进制文件才能使用 `kSecAttrAccessControl`。没有它，`SecItemAdd` 会失败并
返回 `errSecMissingEntitlement`（-34018）。

### 实测行为

在 macOS 26.5.2（版本号 25F84）、Apple Swift 6.3.3、Apple 芯片上实测：

| 配置 | 使用 `.biometryCurrentSet` 的 `SecItemAdd` |
| --- | --- |
| Ad-hoc 签名（SwiftPM 默认） | `-34018` |
| Ad-hoc 签名并显式指定 `--identifier` | `-34018` |
| Ad-hoc 签名且置于 `.app` 包内 | `-34018` |
| Ad-hoc 签名 + `keychain-access-groups` entitlement | 进程在启动时被系统终止 |

作为对照，在同样的 ad-hoc 签名下，一个不带访问控制的普通 Generic Password
可以成功保存 —— 这说明失败是访问控制路径特有的，而不是钥匙串访问整体不可用。

结论是：ad-hoc 签名**不**够用，而且伪造 entitlement 也行不通 —— macOS 拒绝
为 ad-hoc 签名授予 `keychain-access-groups` entitlement，并会直接杀掉进程。

### 使用你自己的签名身份

列出可用身份：

```bash
security find-identity -v -p codesigning
```

然后为 release 二进制签名：

```bash
swift build -c release
./Scripts/sign.sh "Apple Development: you@example.com (XXXXXXXXXX)"
```

脚本会从身份名称中提取 team ID，并替换进
`Resources/touchseal.entitlements`，因为 macOS 只认可前缀与签名身份所属
团队匹配的 keychain access group。

免费的 *Apple Development* 证书和付费的 *Developer ID Application* 证书都带有
team ID。任何 Apple ID 都可以通过 Xcode 获取 Apple Development 证书。

### 重新构建后重新签名

使用 `.biometryCurrentSet` 创建的钥匙串项目绑定的是指纹集合，而不是调用它的
二进制文件，因此重新构建并重新签名 `touchseal` 不会让你已经封存的秘密失效 ——
前提是继续使用同一个 keychain access group。更换 access group 会让已有项目
无法访问，效果和更改 service 字符串一样。

本项目不声称未签名或 ad-hoc 构建能提供跨版本的稳定访问，因为它们根本无法创建
这类项目。

---

## 安装

```bash
mkdir -p "$HOME/.local/bin"
install -m 755 ".build/release/touchseal" "$HOME/.local/bin/touchseal"
```

按上文说明为安装后的副本签名，然后确认：

```bash
"$HOME/.local/bin/touchseal" version
```

请确保 `$HOME/.local/bin` 在你的 `PATH` 中。

---

## 命令

### `set`

```bash
touchseal set anthropic-api-key
```

```text
Enter secret:
Confirm secret:
Secret "anthropic-api-key" sealed.
```

输入从 `/dev/tty` 读取，关闭回显，并要求输入两次。秘密绝不接受作为命令行参数
传入，因为参数会泄漏到 shell history、进程列表和崩溃报告中。成功信息写入
stderr，stdout 保持为空。

如果名称已存在：

```text
Secret "anthropic-api-key" already exists. Replace it? [y/N]
```

默认为 No。替换需要先通过 Touch ID 验证*已有*的秘密 —— 没有 `--force`。
由于已有项目的访问控制无法就地更新，替换操作是先删除再添加。钥匙串操作不是
事务性的，因此如果新值无法保存，TouchSeal 会恢复旧值并明确告知。在极少数
连恢复也失败的情况下，它会报告秘密已丢失，而不是悄无声息地退出。

### `get`

```bash
touchseal get anthropic-api-key
```

成功时 stdout 只包含秘密本身，没有其他内容 —— 没有结尾换行、没有 JSON、
没有状态说明 —— 且 stderr 为空。任何失败情况下 stdout 都为空。

在不显示秘密的前提下测试：

```bash
touchseal get anthropic-api-key >/dev/null
```

### `delete`

```bash
touchseal delete anthropic-api-key
```

```text
Delete secret "anthropic-api-key"? [y/N]
```

默认为 No。`SecItemDelete` 本身不要求验证，因此 TouchSeal 会先执行一次受保护的
读取并丢弃结果；也就是说删除操作始终需要一次 Touch ID 验证。

`--yes` 只跳过文字确认：

```bash
touchseal delete anthropic-api-key --yes
```

它不会跳过 Touch ID，也不存在任何能跳过 Touch ID 的参数。

### `exists`

```bash
if touchseal exists anthropic-api-key; then
    echo "TouchSeal is configured"
fi
```

存在时退出码为 0，不存在时为 3。它不读取秘密，不触发 Touch ID，也不向 stdout
或 stderr 输出任何内容。该查询只请求元数据，刻意不包含 `kSecReturnData`，并设置
`interactionNotAllowed`，使 macOS 直接失败而不是弹出提示。如果 macOS 拒绝在
未验证的情况下回答，TouchSeal 会保守地报告项目存在，而不是降低其保护级别。

v0.1 没有 `list` 命令：秘密名称的集合本身就是值得保密的元数据。

### `help` 与 `version`

```bash
touchseal help      # 也支持 --help、-h
touchseal version   # 也支持 --version
```

---

## 退出码

| 退出码 | 含义 |
| ---: | --- |
| 0 | 成功 |
| 1 | 通用错误 |
| 2 | 参数错误，包括名称不合法 |
| 3 | 秘密不存在 |
| 4 | 秘密已存在且用户拒绝替换 |
| 5 | 用户取消认证 |
| 6 | Touch ID 不可用 |
| 7 | 认证失败 |
| 8 | 钥匙串错误，包括缺少 entitlement |
| 9 | 两次输入不一致 |
| 10 | 用户拒绝普通确认 |
| 11 | 秘密数据格式无效 |

所有错误都写入 stderr。`OSStatus` 通过 `SecCopyErrorMessageString` 转换为可读
文本，并连同数字状态码一起给出。

---

## 名称与秘密

名称必须是 1–128 个 Unicode 字符，不含换行、NUL、其他控制字符，也不能有
前导或结尾空白。空白是被拒绝而不是被自动裁剪的，因此 `key` 和 `key ` 绝不会
被混淆。中间的空格是允许的，但在 shell 中需要正确引用。如果名称以 `-` 开头，
请在前面加上 `--`。

有效示例：`anthropic-api-key`、`github-token`、`work/vpn/password`

秘密必须非空、是有效的 UTF-8，且不超过 8190 字节。它会被逐字节原样保存：
不裁剪、不做规范化、不追加任何内容。v0.1 不支持二进制秘密。

---

## Claude Code 集成

先封存 key：

```bash
touchseal set anthropic-api-key
```

在 `~/.local/bin/claude-anthropic-key` 创建包装脚本：

```sh
#!/bin/sh
set -eu

exec "$HOME/.local/bin/touchseal" get anthropic-api-key
```

仓库中提供了一份副本：[`Examples/claude-anthropic-key`](Examples/claude-anthropic-key)。

```bash
chmod 700 "$HOME/.local/bin/claude-anthropic-key"
```

然后配置 Claude Code：

```json
{
  "apiKeyHelper": "/Users/USERNAME/.local/bin/claude-anthropic-key"
}
```

包装脚本必须只 `exec` 这个工具，不做别的事。不要 `export` key、不要写入临时
文件、不要用 echo 再输出一遍、也不要添加调试输出。

### 凭据缓存说明

以下是两件不同的事，其中只有第一件由 TouchSeal 控制：

1. **TouchSeal 自己的复用行为。** 有保证：每次 `touchseal get` 都会创建全新的
   认证上下文，并要求一次新的 Touch ID 验证。

2. **Claude Code 自己的凭据缓存行为。** 没有保证：Claude Code 可能会缓存
   `apiKeyHelper` 返回的值，并在后续 API 请求中直接复用，而不再调用 helper。

如果你设置了 `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`，在该 TTL 时间窗口内
Claude Code 可能完全不会调用 TouchSeal。因此，一次 Touch ID 验证并不对应
一次 API 请求。

---

## 限制

### 没有 GUI 会话时不可用

Touch ID 需要图形登录会话。通过 SSH，或在任何没有 WindowServer 的会话中，
`touchseal get` 会给出清晰的错误并干净地失败，而不会挂起或输出部分秘密。
此外，安全输入还需要真实的终端，否则会直接失败而不是从重定向的 stdin 读取。

### 没有 Touch ID 就没有 TouchSeal

不支持没有 Touch ID 的 Mac，也不支持 Face ID 设备。TouchSeal 会检查
`LAContext.biometryType` 是否确切等于 `.touchID`，否则拒绝继续。它不会退回到
更弱的策略。

### 更改指纹会让秘密失效

在系统设置中添加或删除指纹，会使所有 `.biometryCurrentSet` 项目失效，
包括全部 TouchSeal 秘密。它们无法恢复，只能重新封存。

macOS 对“项目已失效”和“指纹未被识别”返回相同的状态码（`errSecAuthFailed`），
因此 TouchSeal 的错误信息会同时列出这两种可能，而不是妄加猜测。

### 钥匙串操作不是事务性的

替换秘密是先删除再添加。如果添加失败，TouchSeal 会恢复旧值，但在两步之间发生
崩溃或断电仍可能丢失秘密。请为无法重新生成的内容另行备份。

---

## 威胁模型

TouchSeal 保护的是秘密离开钥匙串的那一刻。这是一个真实但很窄的保证。具体而言：

- Touch ID 保护的是**释放**这一动作，此后的一切都不在保护范围内。
- 一旦你批准，调用程序就拿到了明文秘密，并且可以复制、缓存、记录或传输它。
  这是交出秘密这一行为的固有后果。
- stdout 可被调用程序读取。这是设计意图，不是缺陷。
- TouchSeal 无法控制 Claude Code 如何在内存中保存 API key，而且 Claude Code
  可能会缓存它。
- TouchSeal 不验证调用者是否可信。
- TouchSeal 无法抵御 root，或拥有同等权限的攻击者。
- TouchSeal 无法保护一个已经被完全攻陷的用户会话。
- Swift 可能产生无法可靠清零的秘密数据副本。TouchSeal 尽可能使用 `Data` 而非
  `String`，直接把数据写入输出描述符，并用 `memset_s` 擦除自己的输入缓冲区，
  但它不声称能保证彻底的内存擦除。
- TouchSeal 不是沙箱、不是权限管理系统，也不是完整的 secrets broker。

TouchSeal 绝不记录秘密、不把秘密写入文件、不放进参数或环境变量、不复制到
剪贴板，也不会把秘密包含在错误信息中。

---

## 隐私

TouchSeal 不发起任何网络请求。它没有 analytics、没有遥测、不上传崩溃报告，
也不检查更新。它不保存你执行过的命令历史，也不收集秘密名称。秘密只保存在
macOS 钥匙串中。

---

## 卸载

逐个删除你封存过的秘密。每次删除都需要 Touch ID，这是刻意设计：

```bash
touchseal delete anthropic-api-key
```

TouchSeal 刻意不提供任何未经验证就批量删除项目的命令。

然后删除二进制文件、包装脚本和构建目录：

```bash
rm -f "$HOME/.local/bin/touchseal"
rm -f "$HOME/.local/bin/claude-anthropic-key"
rm -rf .build
```

同时从 Claude Code 设置中移除 `apiKeyHelper` 条目。

如果你在删除之前就已经失去了对某个秘密的访问权限 —— 例如更改指纹之后 ——
残留的项目会以 `TouchSeal: <name>` 的名称显示在“钥匙串访问”中，可在那里删除。

---

## 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请私下报告，见
[SECURITY.md](SECURITY.md)。请勿将 API key、密码或钥匙串内容粘贴到 issue 中。

## 许可证

[MIT](LICENSE)。

---

TouchSeal is an independent open-source project and is not affiliated with
or endorsed by Apple Inc. or Anthropic PBC.

Apple, macOS, Touch ID, and Keychain are trademarks of Apple Inc.
Claude is a trademark of Anthropic PBC.

（TouchSeal 是一个独立的开源项目，与 Apple Inc. 和 Anthropic PBC 无关，
也未获得其认可。Apple、macOS、Touch ID 和 Keychain 是 Apple Inc. 的商标；
Claude 是 Anthropic PBC 的商标。）
