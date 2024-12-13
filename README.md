# sway
Sway config 

## installs 

sudo dnf install foot nmcli wofi waybar blueman mako copyq wl-clipboard grim slurp brightnessctl playerctl pipewire-utils nm-applet alacritty nwg-drawer nwg-bar dunst 


##enable zram 
- [ ] Enable zram
    - [ ] Install
        - [ ] sudo dnf install zram-generator
    - [ ] Config 
        - [ ] sudo nano /etc/systemd/zram-generator.conf
[zram0]
zram-size = min(16 / 2, 4096)
compression-algorithm = zstd
- [ ] Enable
sudo systemctl enable --now systemd-zram-setup@zram0.service
- [ ] Check if active 
systemctl status systemd-zram-setup@zram0.service

