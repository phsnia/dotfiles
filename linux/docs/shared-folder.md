# VM about Sharing Folder: Host → Linux VM

Mount a host folder in a Linux guest with `open-vm-tools` and `vmhgfs-fuse`.
The guest sees the share as `.host:/<SHARE_NAME>`, where `<SHARE_NAME>` is the
name set on the host, not the host path.

## 1. Host

Shut down VM. Open **VM → Settings → Options → Shared Folders**, select **Always
enabled**, add folder:

| Field | Example |
| ----- | ------- |
| Name | `Project` |
| Host path | `/home/user/Project` (Linux) or `D:\Project` (Windows) |

Name is what guest sees. Host path is real folder.

## 2. Guest

Arch:

```bash
sudo pacman -S fuse3 open-vm-tools
sudo systemctl enable --now vmtoolsd.service
```

Debian / Ubuntu:

```bash
sudo apt install fuse3 open-vm-tools
sudo systemctl enable --now open-vm-tools.service
```

Add `open-vm-tools-desktop` for clipboard, drag-and-drop, and display resizing.
No kernel module needed; vmhgfs-fuse is FUSE userspace.

## 3. Verify

```bash
vmware-hgfsclient
```

Expected output:

```text
Project
```

Empty output means share not enabled on host or `vmtoolsd` not running.

## 4. Mount

One share:

```bash
mkdir -p ~/Project
sudo vmhgfs-fuse .host:/Project ~/Project -o allow_other
```

All shares:

```bash
sudo mkdir -p /mnt/hgfs
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other
```

Check:

```bash
findmnt ~/Project
```

Notes:

- `allow_other` lets all users read the mount.
- Non-root mount also needs `user_allow_other` in `/etc/fuse.conf`.
- Add `uid=$(id -u),gid=$(id -g),umask=0022` to set ownership.
- Unmount: `sudo umount ~/Project`. If stuck, use `sudo umount -l ~/Project`.

## 5. Persist

Add to `/etc/fstab`:

```fstab
.host:/Project  /home/<user>/Project  fuse.vmhgfs-fuse  allow_other,uid=1000,gid=1000,umask=0022  0 0
```

Apply:

```bash
sudo systemctl daemon-reload
sudo mount -a
```

`vmtoolsd` must run before mount. To mount on first access instead, add
`noauto,x-systemd.automount,x-systemd.idle-timeout=60` to the options.

## Troubleshooting

| Symptom | Fix |
| ------- | --- |
| `vmware-hgfsclient` empty | Enable share in VM settings, check `systemctl status vmtoolsd.service` |
| `vmware-hgfsclient: command not found` | Install `open-vm-tools` |
| `Transport endpoint is not connected` | `sudo umount -l <mountpoint>`, mount again |
| Root-only access | Remount with `allow_other`; set `user_allow_other` in `/etc/fuse.conf` |
| Space in share name | Quote `".host:/My Share"`; in fstab write `\040` |
| Fails at boot, works manually | Add `x-systemd.automount` to fstab options |
