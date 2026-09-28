if command -v gh >/dev/null 2>&1; then
    export EGET_GITHUB_TOKEN="$(gh auth token 2>/dev/null)"
fi





sudo install -m 755 \
    ~/.local/bin/lsoff \
    ~/.local/bin/systemd-manager-tui \
    ~/.local/bin/tori-cli \
    ~/.local/bin/bandwhich \
    ~/.local/bin/diskwatch \
    ~/.local/bin/systeroid \
    ~/.local/bin/systemctl-tui \
    ~/.local/bin/lazyrsync \
    ~/.local/bin/sake \
    /usr/local/bin/