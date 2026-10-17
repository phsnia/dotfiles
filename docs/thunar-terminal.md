# Thunar terminal handling

## Scope

File involved:

- `/home/phng/dotfiles/linux/arch/.config/Thunar/uca.xml`
- Runtime: Thunar custom action "Open Terminal Here"
- Runtime command currently used:
  `exo-open --working-directory %f --launch TerminalEmulator`

## Observed behavior

1. The only installed terminal emulator on this system is:

   ```sh
   /usr/sbin/alacritty
   ```

   `xfce4-terminal`, `kitty`, `konsole`, and other common XFCE fallback terminals are not installed.

2. There is no XFCE preferred-application file:

   ```text
   ~/.config/xfce4/helpers.rc
   ```

3. Running the action's command manually fails:

   ```sh
   exo-open --working-directory /tmp --launch TerminalEmulator
   # exit status: 1
   ```

   `exo-open` only knows the configured XFCE helper for `TerminalEmulator`. Since no helper is configured and no recognized fallback terminal is installed, it cannot launch Alacritty.

4. Direct Alacritty launch works and starts the shell in the requested directory:

   ```sh
   alacritty --working-directory /tmp
   # child shell cwd becomes /tmp
   ```

## Root cause

The Thunar custom action delegates terminal launching to the XFCE preferred-application framework:

```xml
<command>exo-open --working-directory %f --launch TerminalEmulator</command>
```

On this machine, the preferred terminal is not configured and Alacritty is not available as an XFCE helper. Therefore "Open Terminal Here" exits with status 1 instead of opening a terminal.

## Verification performed so far

- Verified installed terminal binary: `/usr/sbin/alacritty`
- Verified no XFCE helpers configuration exists.
- Verified direct Alacritty working-directory support with `--working-directory`.
- Verified the custom action's `exo-open` command fails with exit status 1.
- Did **not** modify repository files yet.

## Proposed fixes

### Option A (recommended): make the Thunar action call Alacritty directly

Update `uca.xml`:

```xml
<command>alacritty --working-directory %f</command>
```

Advantages:

- Smallest change
- Does not depend on XFCE helper configuration
- Uses the terminal実際に installed on this machine
- Preserves the existing "Open Terminal Here" menu entry

Caveat:

- If the primary terminal changes later, this action must be updated separately.

### Option B: configure Alacritty as the XFCE preferred terminal

Add:

- `~/.config/xfce4/helpers.rc`
- `~/.local/share/xfce4/helpers/Alacritty.desktop` in XFCE helper format

Then keep the existing `exo-open ... TerminalEmulator` action.

Advantages:

- Fixes `exo-open --launch TerminalEmulator` globally, not just Thunar.

Caveat:

- Depends on exact XFCE helper-file format and has not yet been verified on this machine.

### Option C: install/configure `xfce4-terminal`

Keep the existing action and install the terminal that XFCE/`exo-open` expects by default.

Caveat:

- Adds another terminal instead of using the already installed Alacritty.

## Requested verification

Before changing `uca.xml`, verify which option should be implemented.

Recommended for verification:

1. Confirm that the current "Open Terminal Here" menu entry fails.
2. Confirm that a direct Alacritty command is acceptable.
3. Choose Option A, B, or C.

After verification, the selected files can be updated and tested by opening a directory in Thunar and selecting "Open Terminal Here".
EOF
echo done