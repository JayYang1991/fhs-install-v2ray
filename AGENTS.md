# AGENTS.md

This repository contains bash scripts for installing V2Ray on Linux systems following FHS standards.

## Build/Lint/Test Commands

### Linting
```bash
# Run shellcheck on all scripts
shellcheck install-*.sh

# Format with shfmt (uses -i 2 -ci -sr options)
shfmt -i 2 -ci -sr -w install-*.sh
```

### Testing
```bash
# Full installation test (requires sudo)
sudo bash install-release.sh
sudo bash install-release.sh --check
sudo bash install-dat-release.sh

# Note: There are no unit tests. Testing is done by running scripts directly.
# Tests are run in CI via .github/workflows/sh-checker.yml on Ubuntu, Rocky Linux, and Arch Linux.
```

## Code Style Guidelines

### Shebang and Headers
- Always use `#!/usr/bin/env bash` as shebang
- Include shellcheck directives after shebang: `# shellcheck disable=SC2268`
- Add URL references and variable documentation comments at the top

### Variable Naming
- **Constants/Paths**: UPPER_CASE (e.g., `DAT_PATH`, `JSON_PATH`)
- **Local variables**: lower_case (e.g., `v2ray_daemon_to_stop`, `get_ver_exit_code`)
- **Functions**: snake_case (e.g., `check_if_running_as_root`, `identify_the_operating_system_and_architecture`)
- Use default value syntax for configurable variables: `DAT_PATH=${DAT_PATH:-/usr/local/share/v2ray}`

### Formatting
- Indentation: 2 spaces (enforced by shfmt)
- Case statements: indented by 2 spaces for options
- Use double quotes around all variable references: `"$VARIABLE"`
- Prefer `[[ ]]` over `[ ]` for tests

### Error Handling
- Always prefix error messages with `error:` and info messages with `info:`
- Use `exit 1` for errors, `exit 0` for success
- Functions return meaningful exit codes (0=success, 1=failure, 2=other)
- Check command success with `$?` or direct conditional checks

### Output Formatting
- Use tput for colored output: `red=$(tput setaf 1)`, `green=$(tput setaf 2)`, `aoi=$(tput setaf 6)`, `reset=$(tput sgr0)`
- Prefix installed/removed files with descriptive labels
- Use `echo` for output, avoid `printf` unless necessary

### Function Structure
- Keep functions focused on single responsibilities
- Use `local` for variables that should not leak
- Comment functions to explain their purpose above the definition
- Function names should be descriptive verb phrases

### Shellcheck Compliance
- All scripts must pass shellcheck
- Add `# shellcheck disable=...` directives only when necessary
- Fix warnings rather than suppressing them when possible

### curl Wrapper
- Define a custom `curl()` function with retry logic at script level
- Always use: `$(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60`

### System Integration
- Follow Filesystem Hierarchy Standard (FHS)
- Use systemd for service management
- Check for systemd-analyze capabilities before using
- Stop services before updating/removing

### Code Organization
- Main execution logic in `main()` function
- Call `main "$@"` at end of script
- Group related functions together
- Place configuration variables at top of file

### Conditional Logic
- Use `case` statements for multiple value matching (e.g., OS/arch detection)
- Prefer `[[ ]]` with `=` and `=~` operators over `[ ]`
- Use `||` and `&&` for simple conditional execution
- Quote string literals in comparisons: `[[ "$VAR" == 'value' ]]`

### Comments
- Add inline comments explaining non-obvious logic
- Use `#` for comments (preferable over `:` for documentation)
- Comment configurable variables with usage examples
- Include URL references in file headers

### File Operations
- Quote paths with spaces: `rm -r "$PATH"`
- Use `"rm"` to avoid shell built-in conflicts
- Check file existence before operations: `[[ -f 'file' ]]`
- Create temp directories with `mktemp -d`

## Common Patterns

### OS Detection
Use consistent pattern for OS/arch detection via `case` statements matching `$(uname -m)`

### Package Manager Detection
Set `PACKAGE_MANAGEMENT_INSTALL` and `PACKAGE_MANAGEMENT_REMOVE` based on OS distro

### Version Checking
Use `get_version()` returning 0=install/update, 1=current latest, 2=no update

## Environment Variables

### Configurable Paths
Override via environment: `DAT_PATH` (/usr/local/share/v2ray), `JSON_PATH` (/usr/local/etc/v2ray), `JSONS_PATH`, `check_all_service_files`

### Client-Specific Variables
Set before running proxy/reverse scripts: `V2RAY_PROXY_SERVER_IP`, `V2RAY_PROXY_ID`, `V2RAY_REVERSE_SERVER_IP`, `V2RAY_REVERSE_ID`

## Repository Structure

- `install-release.sh`: Main V2Ray installation (649 lines)
- `install-v2ray-proxy-server.sh`: Proxy server installation
- `install-v2ray-proxy-client.sh`: Proxy client installation
- `install-v2ray-reverse-server.sh`: Reverse server installation
- `install-dat-release.sh`: Dat file update script (83 lines)
- `.github/workflows/sh-checker.yml`: CI configuration
- `*_config.json`: Example configurations

## Service Management Pattern

Always stop services before updating. Check for `v2ray@` daemon instances:
```bash
V2RAY_CUSTOMIZE="$(systemctl list-units | grep 'v2ray@' | awk -F ' ' '{print $1}')"
local v2ray_daemon_to_stop="${V2RAY_CUSTOMIZE:-v2ray.service}"
systemctl stop "$v2ray_daemon_to_stop"
```
