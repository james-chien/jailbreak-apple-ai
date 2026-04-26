# jailbreak-apple-ai

`jailbreak-apple-ai` modifies macOS eligibility records so a device can be treated as eligible for Apple Intelligence features that may otherwise be unavailable because of region, language, device, or account restrictions.

The script focuses on making that system modification more controlled: it can inspect the current eligibility values, create backups, prompt before each `PlistBuddy` write, restore previous plist files, and explain the raw eligibility numbers.

中文文档: [README.CN.md](README.CN.md)

## Warning

This tool edits protected macOS system plist files. Use it only if you understand the risk. Backups are created automatically before write operations, but you should still review each prompt carefully.

Before applying or restoring changes, boot into Recovery Mode and run:

```bash
csrutil disable
```

After returning to macOS, run the script from Terminal. Terminal must also have Full Disk Access for `/private/var/db/os_eligibility`.

## Commands

```bash
./jailbreak.sh help
./jailbreak.sh check
./jailbreak.sh status
./jailbreak.sh apply
./jailbreak.sh backups
./jailbreak.sh restore latest
```

Command summary:

- `help`: list available commands.
- `check`: verify macOS, required tools, SIP status, directory access, and plist validity.
- `status`: read current managed plist values.
- `apply`: back up plist files, then prompt before each `PlistBuddy` change.
- `backups`: list available backup directories.
- `restore [latest|DIR]`: restore plist files from a backup.

## Eligibility Values

`os_eligibility_answer_t` records determined eligibility:

- `2`: ineligible
- `4`: eligible

The `status` command displays both the raw number and its meaning.

## Availability Notes

Apple Intelligence availability depends on device model, OS version, language, and region. Current Apple guidance is broader than early summaries: it supports multiple languages, EU availability has expanded on supported OS versions, and supported hardware includes Apple silicon Macs. China mainland remains restricted, including supported devices purchased there and some devices used there with an Apple Account region set to China mainland.

## Testing

Run the local test harness:

```bash
./test_jailbreak.sh
```

The tests stub macOS-specific commands and use temporary files, so they do not touch real system plist files.

## Acknowledgements

Thanks to [Kyle-Ye](https://github.com/Kyle-Ye) for providing kernel information that helped inform this work.

## License

See [LICENSE](LICENSE).
