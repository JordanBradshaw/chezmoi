systemctl --user stop plasma-plasmashell.service

python3 import-kde-panel.py panel-50.conf

systemctl --user start plasma-plasmashell.service