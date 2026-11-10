# Recovery tools

Scripts for recovering a FydeTab Duo whose ESP or boot script is broken. The
full guide is [`../docs/RECOVERY.md`](../docs/RECOVERY.md).

## Scripts

| File                                 | Purpose                                                                                                                                         |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/restore-esp-from-backup.sh` | Copy a full known-good ESP backup to the mounted ESP over UMS. Set `B=` (backup dir) and `E=` (mounted ESP).                                    |
| `scripts/rebuild-esp-from-store.sh`  | Rebuild the ESP from a known-good generation in the tablet's Nix store. Set `M=` (mounted tablet root), `E=` (mounted ESP) and `T=` (toplevel). |
| `scripts/validate-boot-scr.js`       | Validate a Rockchip script uImage (magic, CRCs, terminator) and optionally compare it with a `boot.cmd`.                                        |

```sh
# Restore a backup
B=/path/to/known-good-esp E=/mnt/fydetab-esp \
  recovery/scripts/restore-esp-from-backup.sh

# Rebuild from a generation already in the tablet store
M=/mnt/fydetab-root E=/mnt/fydetab-esp \
  T=/nix/store/<known-good-toplevel> \
  recovery/scripts/rebuild-esp-from-store.sh

# Check a boot script
node recovery/scripts/validate-boot-scr.js /mnt/fydetab-esp/boot.scr \
  /mnt/fydetab-esp/boot.cmd
```
