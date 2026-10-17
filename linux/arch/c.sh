sudo pacman -S --needed polkit udiskie

sudo mkdir -p /etc/polkit-1/rules.d

sudo tee /etc/polkit-1/rules.d/49-mount.rules > /dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user === "phng" &&
        (action.id === "org.freedesktop.udisks2.filesystem-mount" ||
         action.id === "org.freedesktop.udisks2.filesystem-mount-system" ||
         action.id === "org.freedesktop.udisks2.filesystem-unmount-others")) {
        return polkit.Result.YES;
    }
});
EOF
