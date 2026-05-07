#!/usr/bin/env bash
# set-system-preferences.sh
# Sets GNOME/Ubuntu system preferences via gsettings.
# Must be run as the target user (not root). first-time-install.sh handles this via su.
set -euo pipefail

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\nWARNING: %s\n" "$*" >&2; }

gs() {
  # Wrapper: silently skip if schema/key does not exist on this system.
  local schema="$1" key="$2" value="$3"
  if gsettings writable "$schema" "$key" 2>/dev/null | grep -q "true"; then
    gsettings set "$schema" "$key" "$value"
  else
    warn "gsettings: '$schema $key' ikke tilgjengelig på dette systemet – hopper over."
  fi
}

# ---------------------------------------------------------------------------
# Appearance / Interface
# ---------------------------------------------------------------------------
configure_interface() {
  log "Konfigurerer: grensesnitt (tema, skrift, klokke)"

  gs org.gnome.desktop.interface color-scheme        'default'
  gs org.gnome.desktop.interface gtk-theme           'Yaru'
  gs org.gnome.desktop.interface icon-theme          'Yaru'
  gs org.gnome.desktop.interface cursor-theme        'Yaru'
  gs org.gnome.desktop.interface font-name           'Ubuntu Sans 11'
  gs org.gnome.desktop.interface document-font-name  'Sans 11'
  gs org.gnome.desktop.interface monospace-font-name 'Ubuntu Sans Mono 13'
  gs org.gnome.desktop.interface text-scaling-factor '1.0'

  # Topbar / status area
  gs org.gnome.desktop.interface show-battery-percentage 'true'
  gs org.gnome.desktop.interface clock-show-weekday      'false'
  gs org.gnome.desktop.interface clock-show-date         'true'
  gs org.gnome.desktop.interface clock-show-seconds      'false'
}

# ---------------------------------------------------------------------------
# Touchpad
# ---------------------------------------------------------------------------
configure_touchpad() {
  log "Konfigurerer: touchpad"

  gs org.gnome.desktop.peripherals.touchpad natural-scroll             'true'
  gs org.gnome.desktop.peripherals.touchpad tap-to-click               'true'
  gs org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled 'true'
  gs org.gnome.desktop.peripherals.touchpad speed                      '0.0'
  gs org.gnome.desktop.peripherals.touchpad disable-while-typing       'true'
}

# ---------------------------------------------------------------------------
# Mouse
# ---------------------------------------------------------------------------
configure_mouse() {
  log "Konfigurerer: mus"

  gs org.gnome.desktop.peripherals.mouse natural-scroll 'false'
  gs org.gnome.desktop.peripherals.mouse speed          '0.0'
}

# ---------------------------------------------------------------------------
# Power management
# ---------------------------------------------------------------------------
configure_power() {
  log "Konfigurerer: strømstyring"

  # On AC: no auto-suspend (already handled by systemd logind for lid, but also set here)
  gs org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout      '3600'
  gs org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type         'nothing'

  # On battery: suspend after 15 minutes of inactivity
  gs org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout '900'
  gs org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type    'nothing'

  gs org.gnome.settings-daemon.plugins.power power-button-action            'nothing'
  gs org.gnome.settings-daemon.plugins.power idle-dim                       'false'

  # Screen blank / lock
  gs org.gnome.desktop.session idle-delay 'uint32 0'
  gs org.gnome.desktop.screensaver lock-enabled 'true'
  gs org.gnome.desktop.screensaver lock-delay   'uint32 0'
}

# ---------------------------------------------------------------------------
# Night Light
# ---------------------------------------------------------------------------
configure_night_light() {
  log "Konfigurerer: nattlys"

  gs org.gnome.settings-daemon.plugins.color night-light-enabled            'true'
  gs org.gnome.settings-daemon.plugins.color night-light-temperature        'uint32 2622'
  gs org.gnome.settings-daemon.plugins.color night-light-schedule-automatic 'true'
}

# ---------------------------------------------------------------------------
# Privacy
# ---------------------------------------------------------------------------
configure_privacy() {
  log "Konfigurerer: personvern"

  gs org.gnome.desktop.privacy remember-recent-files  'true'
  gs org.gnome.desktop.privacy recent-files-max-age   '-1'
  gs org.gnome.desktop.privacy remove-old-trash-files 'false'
  gs org.gnome.desktop.privacy remove-old-temp-files  'false'
  gs org.gnome.desktop.privacy old-files-age          'uint32 30'
}

# ---------------------------------------------------------------------------
# Dock (Ubuntu's dash-to-dock)
# ---------------------------------------------------------------------------
configure_dock() {
  log "Konfigurerer: dock"

  gs org.gnome.shell.extensions.dash-to-dock dock-position     'BOTTOM'
  gs org.gnome.shell.extensions.dash-to-dock dash-max-icon-size '40'
  gs org.gnome.shell.extensions.dash-to-dock autohide           'true'
  gs org.gnome.shell.extensions.dash-to-dock intellihide        'true'
  gs org.gnome.shell.extensions.dash-to-dock show-mounts        'false'
  gs org.gnome.shell.extensions.dash-to-dock show-trash         'true'
}

# ---------------------------------------------------------------------------
# Window manager
# ---------------------------------------------------------------------------
configure_wm() {
  log "Konfigurerer: vindusbehandler"

  gs org.gnome.desktop.wm.preferences button-layout                ':minimize,maximize,close'
  gs org.gnome.desktop.wm.preferences action-double-click-titlebar 'toggle-maximize'
  gs org.gnome.desktop.wm.preferences num-workspaces               '4'
  gs org.gnome.mutter dynamic-workspaces          'true'
  gs org.gnome.mutter workspaces-only-on-primary  'false'
}

# ---------------------------------------------------------------------------
# File manager (Nautilus)
# ---------------------------------------------------------------------------
configure_nautilus() {
  log "Konfigurerer: filbehandler (Nautilus)"

  gs org.gnome.nautilus.preferences show-hidden-files    'false'
  gs org.gnome.nautilus.preferences default-folder-viewer 'list-view'
}

# ---------------------------------------------------------------------------
# Keyboard / Input sources
# ---------------------------------------------------------------------------
configure_keyboard() {
  log "Konfigurerer: tastatur (norsk layout)"

  gs org.gnome.desktop.input-sources sources     "[('xkb', 'no')]"
  gs org.gnome.desktop.input-sources xkb-options "@as []"
}

# ---------------------------------------------------------------------------
# Accessibility
# ---------------------------------------------------------------------------
configure_accessibility() {
  log "Konfigurerer: tilgjengelighet"

  gs org.gnome.desktop.a11y.interface high-contrast 'false'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
configure_interface
configure_touchpad
configure_mouse
configure_power
configure_night_light
configure_privacy
configure_dock
configure_wm
configure_nautilus
configure_keyboard
configure_accessibility

log "Systempreferanser satt."

