# jailbreak-apple-ai

`jailbreak-apple-ai` 会修改 macOS 的 eligibility 记录，使设备在系统判断中被视为符合 Apple Intelligence 的使用条件。它主要用于处理因地区、语言、设备型号或账户区域限制而无法启用 Apple Intelligence 的情况。

这个脚本的目标不是静默改写系统文件，而是让修改过程更可控：它可以查看当前 eligibility 值、创建备份、在每条 `PlistBuddy` 写入前请求确认、从备份恢复 plist 文件，并解释原始 eligibility 数字的含义。

English README: [README.md](README.md)

## 风险提示

本工具会修改受保护的 macOS 系统 plist 文件。请只在理解风险后使用。脚本会在写入前自动创建备份，但你仍然需要仔细阅读并确认每一个提示。

在执行应用或恢复操作前，请进入恢复模式并运行：

```bash
csrutil disable
```

回到 macOS 后，请从 Terminal 运行脚本。Terminal 还必须拥有 `/private/var/db/os_eligibility` 的完整磁盘访问权限。

## 命令

英文界面：

```bash
./jailbreak.sh help
./jailbreak.sh check
./jailbreak.sh status
./jailbreak.sh apply
./jailbreak.sh backups
./jailbreak.sh restore latest
```

中文界面：

```bash
./jailbreak_cn.sh help
./jailbreak_cn.sh check
./jailbreak_cn.sh status
./jailbreak_cn.sh apply
./jailbreak_cn.sh backups
./jailbreak_cn.sh restore latest
```

命令说明：

- `help`：显示可用命令。
- `check`：检查 macOS、必要工具、SIP 状态、目录访问权限和 plist 有效性。
- `status`：读取脚本管理的当前 plist 值。
- `apply`：先备份 plist 文件，再在每条 `PlistBuddy` 修改前请求确认。
- `backups`：列出可用备份目录。
- `restore [latest|DIR]`：从备份恢复 plist 文件。

## Eligibility 数值

`os_eligibility_answer_t` 记录系统判定出的功能资格：

- `2`：不符合资格
- `4`：符合资格

`status` 命令会同时显示原始数字和对应含义。

## 可用性说明

Apple Intelligence 的可用性取决于设备型号、系统版本、语言和地区。Apple 目前的说明比早期资料更宽泛：它已支持多种语言，欧盟地区在受支持系统版本上的可用性已经扩大，并且支持 Apple silicon Mac。中国大陆仍有限制，包括在中国大陆购买的受支持设备，以及部分在中国大陆使用且 Apple Account 地区也设为中国大陆的设备。

## 测试

运行本地测试脚本：

```bash
./test_jailbreak.sh
```

测试会使用临时文件和 macOS 命令的替身，不会触碰真实的系统 plist 文件。

## 致谢

感谢 [Kyle-Ye](https://github.com/Kyle-Ye) 提供 kernel 信息，对本项目很有帮助。

## 许可证

请参阅 [LICENSE](LICENSE)。
