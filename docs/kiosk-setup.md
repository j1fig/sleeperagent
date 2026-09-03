# Preparing the child's Linux laptop

Assumes a GNOME-based desktop (Ubuntu, Fedora) with GNOME Parental Controls
(`malcontent`) restricting apps and blocking web browsers. Commands for other
desktops are noted where they differ. Everything here is done by the parent
with an admin account.

## 1. Confirm the network path works despite parental controls

Parental Controls restricts which *applications* the child's account can
launch. It does not filter network traffic. A DNS filter (router controls,
Pi-hole, NextDNS) might. Test from the child's account:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' https://api.pushover.net/1/users/validate.json
```

Any HTTP status (even `400`) means the host is reachable. A timeout or DNS
error means `api.pushover.net` must be allow-listed in whatever filter is in
place.

## 2. Run the installer

From the child's account:

```sh
curl -fsSL https://raw.githubusercontent.com/j1fig/sleeperagent/main/install.sh | bash
```

It does sections 2 to 4 of the manual procedure below: scripts, config,
desktop icon, GNOME hotkey, power and lock-screen settings, and the root-only
extras when `sudo` works for this account. Flags: `--reconfigure` to re-enter
the keys, `--no-system` to skip the sudo steps, `--uninstall` to remove icon,
hotkey and scripts. Everything below is the manual equivalent, kept for
non-GNOME desktops and for checking what the installer changed.

### 2a. Manual: config and scripts

As the child's user:

```sh
mkdir -p ~/.config/sleeperagent ~/.local/bin ~/.local/state/sleeperagent
cp config.example ~/.config/sleeperagent/config
chmod 600 ~/.config/sleeperagent/config
cp scripts/*.sh ~/.local/bin/
chmod +x ~/.local/bin/*.sh
```

Fill in `~/.config/sleeperagent/config`. Use a **dedicated Pushover
application** for this (pushover.net/apps → Create). Set `PUSHOVER_DEVICE` to
the parent phone's device name as shown in the Pushover app, so nothing else
registered to the account rings.

Test while awake, from the child's account:

```sh
~/.local/bin/call.sh --practice   # normal priority, should appear on the phone
~/.local/bin/call.sh              # emergency: retries every 30 s until acknowledged
~/.local/bin/status.sh            # acknowledged: yes/no
~/.local/bin/cancel.sh            # stop the retries if you are just testing
```

## 3. Manual: give the child something to press

### A desktop icon

```sh
mkdir -p ~/Desktop
sed "s|__HOME__|$HOME|g" desktop/CALL.desktop.example > ~/Desktop/CALL.desktop
chmod +x ~/Desktop/CALL.desktop
gio set ~/Desktop/CALL.desktop metadata::trusted true   # GNOME: skips "Allow Launching"
```

Remove everything else from the desktop so it is the only thing there. If
Parental Controls hides it, add it to the allowed apps list in Settings →
Parental Controls, or use the keyboard shortcut below, which is not subject
to the app filter.

### A keyboard shortcut (recommended, works with the screen blanked)

GNOME: Settings → Keyboard → View and Customize Shortcuts → Custom Shortcuts →
`+`. Name `CALL`, command `/home/<child>/.local/bin/call.sh`, shortcut `F12`.
KDE: System Settings → Shortcuts → Custom Shortcuts → Edit → New → Global
Shortcut → Command/URL.

Put a bright sticker on the key. The routine becomes: wake → press the sticker
key → stay in bed. If the screen was blanked, the first keypress only wakes the
screen on some desktops; teach "press it twice".

## 4. Manual: keep the laptop awake and unlocked all night

Run as the child's user (GNOME):

```sh
# never suspend (the screen may still blank; a keypress wakes it instantly)
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
# do not lock; the shortcut must work without a password
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.session idle-delay 300   # blank after 5 min, fine
```

As admin, stop the lid from suspending and mask suspend entirely:

```sh
sudo mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\n' | sudo tee /etc/systemd/logind.conf.d/sleeperagent.conf
sudo systemctl kill -s HUP systemd-logind
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Enable auto-login for the child's account (Settings → Users → Automatic Login)
so a reboot comes back to a usable desktop without anyone typing a password.

Keep the laptop plugged in. Mute its speakers: the laptop must never make a
sound at night.

```sh
pactl set-sink-mute @DEFAULT_SINK@ 1 || amixer -q set Master mute
```

## 5. Phase 1: run the kiosk as a service

Once the kiosk app exists, install the unit so it starts at login and restarts
on crash:

```sh
mkdir -p ~/.config/systemd/user
sed "s|__HOME__|$HOME|g" desktop/sleeperagent.service.example > ~/.config/systemd/user/sleeperagent.service
systemctl --user daemon-reload
systemctl --user enable --now sleeperagent.service
```

## 6. Parent phone checklist

- Pushover installed, licensed for iOS (one-time purchase after the trial).
- Device named clearly; that name goes in `PUSHOVER_DEVICE`.
- Pushover app settings → enable **Critical Alerts** for emergency priority.
  Approve the iOS prompt.
- Send a practice call, then a real emergency call, and confirm it keeps
  ringing every 30 s until **Acknowledge** is tapped.
- Sleep with the phone at the bedside and have someone press the button at
  night at least once before relying on it.
- Check the Pushover app's quiet-hours / Focus behaviour on the installed
  version: emergency priority should override quiet hours.

## 7. Night-one checklist

- [ ] `status.sh` shows the last test acknowledged.
- [ ] Shortcut key works from the child's account with the screen blanked.
- [ ] Laptop plugged in, lid open, speakers muted.
- [ ] Rehearsed with the child in daylight: press, wait in bed, parent arrives, parent leaves.
- [ ] Phone charged, on the parent's side, Critical Alerts on.
