# jailbreak-apple-ai

一个用于检查和更新 macOS Apple Intelligence 相关 eligibility plist 值的辅助工具。

脚本提供更安全的命令式流程，包括 SIP 检查、完整磁盘访问权限检查、带时间戳的备份、逐条命令确认、状态解码和恢复功能。

English README: [README.md](README.md)

## 风险提示

本工具会修改受保护的 macOS 系统 plist 文件。请只在理解风险的情况下使用。脚本会在写入前自动创建备份，但你仍然应该仔细确认每一个提示。

在执行应用或恢复操作前，请进入恢复模式并运行：

```bash
csrutil disable
```

回到 macOS 后，从 Terminal 运行脚本。Terminal 还需要拥有 `/private/var/db/os_eligibility` 的完整磁盘访问权限。

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
- `status`：读取当前被管理的 plist 值。
- `apply`：先备份 plist 文件，再在每条 `PlistBuddy` 修改前请求确认。
- `backups`：列出可用备份目录。
- `restore [latest|DIR]`：从备份恢复 plist 文件。

## Eligibility 值

`os_eligibility_answer_t` 表示系统判断出的功能资格：

- `2`：不符合资格
- `4`：符合资格

`status` 命令会同时显示原始数字和对应含义。

## 可用性说明

Apple Intelligence 的可用性取决于设备型号、系统版本、语言和地区。Apple 当前说明比早期资料更宽泛：它支持多种语言，欧盟地区在受支持系统版本上的可用性已经扩大，并且支持 Apple silicon Mac。中国大陆仍然存在限制，包括在中国大陆购买的受支持设备，以及部分在中国大陆使用且 Apple Account 地区设置为中国大陆的设备。

## 测试

运行本地测试脚本：

```bash
./test_jailbreak.sh
```

测试会使用临时文件和 macOS 命令替身，不会触碰真实系统 plist 文件。

## 致谢

感谢 [Kyle-Ye](https://github.com/Kyle-Ye) 提供 kernel 信息，为本项目提供了帮助。

## 许可证

请查看 [LICENSE](LICENSE)。
