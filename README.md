# Kali Setup for Pentesting

## Usage

```bash
sudo ./setup.sh              # interactive menu
sudo ./setup.sh --force      # re-run even if already installed
sudo ./setup.sh --category ad  # show only AD modules
```

**Multi-select:** enter numbers separated by commas or spaces — `1,3,5` or `1 3 5`  
**Run all:** type `all`  
**Filter by category:** type `cat:recon`, `cat:ad`, `cat:infra`, etc.  
**Exit:** press Enter with no input

## Adding a New Module

```bash
cp modules/_template.sh modules/10_mytool.sh
# edit the three header lines and the install() function
# that's it — it appears in the menu automatically
```

## Module Categories

| Category | Purpose |
|----------|---------|
| `setup`  | Base system config, shell, logging |
| `recon`  | Scanning, enumeration, wordlists |
| `ad`     | Active Directory attack tools |
| `infra`  | C2, tunneling, pivoting |
| `web`    | Web app testing |
| `general`| Uncategorised |

## Helpers Available in Every Module

| Helper | Usage |
|--------|-------|
| `require_root` | Exit if not root |
| `require_module "01_go"` | Install dependency module first |
| `apt_install pkg1 pkg2` | Quiet apt with logging |
| `github_latest_release "owner/repo"` | Returns latest tag string |
| `github_download "owner/repo" "pattern" "/dest"` | Downloads matching release asset |
| `add_to_rc "$rc" "block-id" "content"` | Idempotent block in shell rc file |
| `info / success / warn / fail` | Coloured output |
| `confirm "prompt"` | y/N prompt, returns 0/1 |
| `MODULE_LOG` | Log file path auto-set per module run |

## State

Completed modules are tracked in `~/.kali-setup-state/`.  
Delete a `.done` file to allow re-running that module.