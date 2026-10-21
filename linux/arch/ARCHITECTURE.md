```mermaid
flowchart TD
    START([Start bootstrap.sh]) --> ARGS["Parse arguments<br/>Default: install first, then bootstrap"]
    ARGS --> ROOT{Running as root?}
    ROOT -->|Yes| ERR["Error: run as a normal user"]
    ROOT -->|No| HELP{Help requested?}
    HELP -->|Yes| USAGE["Print usage"]
    USAGE --> EXIT0([Exit 0])
    HELP -->|No| VALID{Valid stage names?}
    VALID -->|No| ERR
    VALID -->|Yes| UPDATE["Full system update<br/>sudo pacman -Syu"]

    UPDATE --> CORE

    subgraph INSTALL["1. Install software"]
        direction TB
        CORE["core — base packages<br/>git, base-devel, vim, alacritty"]
        DRIVERS["drivers — graphics / Vulkan"]
        UTILITIES["utilities — WM, Xorg, audio, yay + AUR"]
        DEVKIT["devkit — mise, Docker, toolchain, IDEs"]
        FONTS["fonts — Noto / DejaVu / Liberation + Comic Mono"]
        CORE --> DRIVERS --> UTILITIES --> DEVKIT --> FONTS
    end

    FONTS -->|"software ready"| SYSTEM

    subgraph BOOTSTRAP["2. Bootstrap (config)"]
        direction TB
        SYSTEM["system — timezone + NTP"]
        DOTFILES["dotfiles — link ~/.bashrc and ~/.config"]
        POLKIT["polkit — udiskie mount rules"]
        SYSTEM --> DOTFILES --> POLKIT
    end

    POLKIT --> DONE([All done])
    ERR --> EXIT1([Exit 1])
```
