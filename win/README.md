# Windows dotfiles

Run `bootstrap.ps1` once; it relaunches itself elevated and symlinks your
PowerShell profile to the repo:

```
.\bootstrap.ps1
```

That links `$PROFILE` (whatever host and scope you launch it from — pwsh or
Windows PowerShell, current user) to `Microsoft.PowerShell_profile.ps1` in this
directory. It force-replaces whatever is already there.

Reload afterwards with:

```
src_profile
```

Other scripts in this directory:

| Script | Purpose |
| --- | --- |
| `init_env.ps1` | Links the profile and a `.bashrc`; superseded by `bootstrap.ps1` |
| `debloat.ps1` | Windows debloat |
| `install_pkg.ps1` | Package install |