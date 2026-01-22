#!/usr/bin/env bash
set -euo pipefail

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\nWARNING: %s\n" "$*" >&2; }
die()  { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

# Re-run as root with sudo, but keep knowledge of the invoking user for user-level files.
ensure_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
  fi
}

APT_INSTALL="DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends"

apt_update() { apt-get update -y; }
apt_install() { $APT_INSTALL "$@"; }

invoking_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    printf "%s" "$SUDO_USER"
  else
    printf "%s" "$(logname 2>/dev/null || true)"
  fi
}

user_home() {
  local u
  u="$(invoking_user)"
  if [[ -z "$u" ]]; then
    echo "$HOME"
  else
    eval echo "~$u"
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

download_with_ua() {
  # $1=url $2=output
  local url="$1" out="$2"
  curl -fSL -A "Mozilla/5.0" -o "$out" "$url"
}

remove_snap_if_present() {
  local snap_name="$1"
  if has_cmd snap && snap list 2>/dev/null | awk '{print $1}' | grep -qx "$snap_name"; then
    log "Fjerner Snap: $snap_name"
    snap remove "$snap_name" || warn "Klarte ikke å fjerne snap '$snap_name' (fortsetter)."
  fi
}

install_base_prereqs() {
  log "Installerer basisverktøy (curl, gpg, osv.)"
  apt_update
  apt_install ca-certificates curl wget gpg apt-transport-https software-properties-common lsb-release \
              gnupg2 xdg-utils desktop-file-utils jq
}

remove_snaps_and_prefer_native() {
  log "Fjerner kjente problem-Snaps og foretrekker native der vi kan"
  # Slack Snap gir ofte keyring-problemer
  remove_snap_if_present "slack"

  # Discord finnes ofte som snap også; vi foretrekker .deb
  remove_snap_if_present "discord"

  # Postman finnes som snap; vi foretrekker /opt-install
  remove_snap_if_present "postman"

  # IntelliJ via snap (begge varianter)
  remove_snap_if_present "intellij-idea-community"
  remove_snap_if_present "intellij-idea-ultimate"

  # Firefox/1Password: Snap-Firefox er ofte roten til problemer, men på nyere Ubuntu kan apt peke tilbake til snap.
  if has_cmd snap && snap list 2>/dev/null | awk '{print $1}' | grep -qx "firefox"; then
    warn "Firefox er installert som Snap. Dette kan gi problemer med 1Password-integrasjon."
    warn "På flere Ubuntu-versjoner vil 'apt install firefox' likevel installere Snap igjen."
    warn "Hvis du opplever 1Password-problemer: vurder ikke-snap Firefox (Mozilla sin metode) manuelt."
  fi
}

configure_lid_on_ac() {
  log "Konfigurerer: ikke dvale ved lukking av lokk når maskinen er på strøm"
  mkdir -p /etc/systemd/logind.conf.d
  cat >/etc/systemd/logind.conf.d/99-lid-external-power.conf <<'EOF'
[Login]
HandleLidSwitchExternalPower=ignore
EOF
  warn "Dette trer sikrest i kraft etter reboot (alternativt restart av systemd-logind, som ofte logger deg ut)."
}

install_node_lts_nodesource() {
  log "Installerer Node.js (siste LTS) via NodeSource APT repo"
  # NodeSource setup-scriptet legger til riktig repo og nøkkel for din Ubuntu-versjon.
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -

  apt_update
  apt_install nodejs

  if command -v node >/dev/null 2>&1; then
    log "Node installert: $(node -v)"
  else
    warn "Node ble ikke funnet i PATH etter installasjon."
  fi
  if command -v npm >/dev/null 2>&1; then
    log "npm installert: $(npm -v)"
  else
    warn "npm ble ikke funnet i PATH etter installasjon."
  fi
}

setup_1password_repo_install() {
  log "Installerer 1Password (offisielt APT repo)"
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://downloads.1password.com/linux/keys/1password.asc \
    | gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/ stable main" \
    > /etc/apt/sources.list.d/1password.list

  apt_update
  apt_install 1password
}

setup_vscode_repo_install() {
  log "Installerer VS Code (Microsoft APT repo)"
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg

  cat >/etc/apt/sources.list.d/vscode.sources <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

  apt_update
  apt_install code
}

setup_brave_repo_install() {
  log "Installerer Brave (offisielt APT repo)"
  install -d -m 0755 /usr/share/keyrings
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list

  apt_update
  apt_install brave-browser
}

setup_atuin_repo_install() {
  log "Installerer Atuin (offisielt APT repo)"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://atuin.sh/gpg.pub \
    | gpg --dearmor -o /etc/apt/keyrings/atuin-archive-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/atuin-archive-keyring.gpg] https://atuin.sh/repo debian main" \
    > /etc/apt/sources.list.d/atuin.list

  apt_update
  apt_install atuin
}

install_discord_deb() {
  log "Installerer Discord (offisiell .deb)"
  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  download_with_ua "https://discord.com/api/download?platform=linux&format=deb" "$tmpdir/discord.deb" \
    || die "Discord-nedlasting feilet."
  [[ -s "$tmpdir/discord.deb" ]] || die "Discord .deb er tom/ugyldig."

  apt_install "$tmpdir/discord.deb"
}

install_slack_deb() {
  log "Installerer Slack (offisiell .deb via Slack downloads-side)"
  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  # Slack sin side endrer seg; vi forsøker å hente en direkte amd64 .deb-lenke.
  local page deb_url
  page="$(curl -fsSL -A "Mozilla/5.0" https://slack.com/downloads/linux || true)"
  deb_url="$(printf "%s" "$page" | grep -Eo 'https://downloads\.slack-edge\.com/linux_releases/[^"]+amd64\.deb' | head -n 1 || true)"

  if [[ -z "${deb_url}" ]]; then
    warn "Fant ikke en direkte Slack .deb-lenke automatisk."
    warn "Last ned manuelt her: https://slack.com/downloads/linux (Debian .deb)"
    warn "Installer deretter: sudo apt install ./slack-desktop-*.deb"
    return 0
  fi

  log "Laster ned Slack: $deb_url"
  if ! download_with_ua "$deb_url" "$tmpdir/slack.deb"; then
    warn "Slack-nedlasting feilet (ofte CDN/403)."
    warn "Last ned manuelt her: https://slack.com/downloads/linux (Debian .deb)"
    warn "Installer deretter: sudo apt install ./slack-desktop-*.deb"
    return 0
  fi

  [[ -s "$tmpdir/slack.deb" ]] || die "Slack .deb er tom/ugyldig."
  apt_install "$tmpdir/slack.deb"
}

install_postman_tarball() {
  log "Installerer Postman (latest Linux64 tarball)"
  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  download_with_ua "https://dl.pstmn.io/download/latest/linux64" "$tmpdir/postman.tar.gz" \
    || die "Postman-nedlasting feilet."
  [[ -s "$tmpdir/postman.tar.gz" ]] || die "Postman tarball er tom/ugyldig."

  rm -rf /opt/postman
  mkdir -p /opt
  tar -xzf "$tmpdir/postman.tar.gz" -C /opt

  if [[ -d /opt/Postman ]]; then
    mv /opt/Postman /opt/postman
  fi
  [[ -x /opt/postman/Postman ]] || die "Postman-binary ble ikke funnet etter utpakking."

  ln -sf /opt/postman/Postman /usr/local/bin/postman

  install -d -m 0755 /usr/local/share/applications
  cat >/usr/local/share/applications/postman.desktop <<'EOF'
[Desktop Entry]
Name=Postman
Exec=/opt/postman/Postman
Icon=/opt/postman/app/resources/app/assets/icon.png
Type=Application
Categories=Development;
EOF
}

install_intellij() {
  log "Installerer JetBrains Toolbox (anbefalt for IntelliJ på Linux)"

  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  # Hent "latest" Toolbox metadata (JSON) og plukk linux-link
  local json url
  json="$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" || true)"
  if [[ -z "$json" ]]; then
    warn "Klarte ikke å hente Toolbox metadata automatisk."
    warn "Installer manuelt: https://www.jetbrains.com/toolbox-app/"
    return 0
  fi

  url="$(printf "%s" "$json" | jq -r '.[0].downloads.linux.link // empty')"
  if [[ -z "$url" || "$url" == "null" ]]; then
    warn "Fant ikke Toolbox download-link i metadata."
    warn "Installer manuelt: https://www.jetbrains.com/toolbox-app/"
    return 0
  fi

  log "Laster ned JetBrains Toolbox"
  download_with_ua "$url" "$tmpdir/toolbox.tar.gz" || die "Toolbox-nedlasting feilet."
  [[ -s "$tmpdir/toolbox.tar.gz" ]] || die "Toolbox tarball er tom/ugyldig."

  # Pakk ut
  tar -xzf "$tmpdir/toolbox.tar.gz" -C "$tmpdir"
  local extracted_dir
  extracted_dir="$(find "$tmpdir" -maxdepth 1 -type d -name "jetbrains-toolbox-*" | head -n 1 || true)"
  [[ -n "$extracted_dir" ]] || die "Utpakking feilet (fant ikke jetbrains-toolbox-*)."

  # Installer til /opt/jetbrains-toolbox
  rm -rf /opt/jetbrains-toolbox
  mkdir -p /opt/jetbrains-toolbox
  cp -a "$extracted_dir"/* /opt/jetbrains-toolbox/

  # Normaliser til /opt/jetbrains-toolbox/bin/jetbrains-toolbox
  if [[ -x /opt/jetbrains-toolbox/jetbrains-toolbox ]]; then
    mkdir -p /opt/jetbrains-toolbox/bin
    mv /opt/jetbrains-toolbox/jetbrains-toolbox /opt/jetbrains-toolbox/bin/jetbrains-toolbox
  fi

  [[ -x /opt/jetbrains-toolbox/bin/jetbrains-toolbox ]] || die "Fant ikke jetbrains-toolbox-binary etter installasjon."

  # Symlink til PATH
  ln -sf /opt/jetbrains-toolbox/bin/jetbrains-toolbox /usr/local/bin/jetbrains-toolbox

  # Desktop entry (app-meny)
  install -d -m 0755 /usr/local/share/applications
  cat >/usr/local/share/applications/jetbrains-toolbox.desktop <<'EOF'
[Desktop Entry]
Name=JetBrains Toolbox
Exec=/opt/jetbrains-toolbox/bin/jetbrains-toolbox
Type=Application
Categories=Development;
EOF

  log "JetBrains Toolbox installert. Start med: jetbrains-toolbox (installer IntelliJ derfra)."
}

install_docker_and_compose() {
  log "Installerer Docker (docker.io + compose plugin)"
  apt_update
  apt_install docker.io docker-compose-plugin
  systemctl enable --now docker

  local u; u="$(invoking_user)"
  if [[ -n "$u" && "$u" != "root" ]]; then
    # Sjekk om brukeren allerede er i docker-gruppen
    if ! groups "$u" | grep -qw docker; then
      usermod -aG docker "$u" || true
      warn "Brukeren '$u' er lagt i docker-gruppen. Dette krever ny innlogging (logg ut/inn eller reboot)."
      warn "MSSQL docker-oppsett vil bli hoppet over. Kjør 'docker compose up -d' i ~/docker/mssql etter innlogging."
      export SKIP_MSSQL_START=1
    fi
  fi
}

setup_mssql_compose_and_start() {
  log "Setter opp MSSQL via docker compose (SA-passord: MSSQLonDocker19)"
  local u h dir
  u="$(invoking_user)"
  h="$(user_home)"
  dir="$h/docker/mssql"
  mkdir -p "$dir"
  chown -R "${u:-root}:${u:-root}" "$h/docker" || true

  cat >"$dir/docker-compose.yml" <<'EOF'
services:
  mssql:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: mssql
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: "MSSQLonDocker19"
      MSSQL_PID: "Developer"
    ports:
      - "1433:1433"
    volumes:
      - mssql_data:/var/opt/mssql
    restart: unless-stopped

volumes:
  mssql_data:
EOF

  # Hopp over start hvis brukeren nettopp ble lagt til i docker-gruppen
  if [[ "${SKIP_MSSQL_START:-0}" == "1" ]]; then
    log "MSSQL docker-compose.yml opprettet i $dir"
    log "Start MSSQL etter reboot/innlogging med: cd $dir && docker compose up -d"
    return 0
  fi

  if [[ -n "${u:-}" && "${u:-}" != "root" ]]; then
    if su - "$u" -c "cd '$dir' && docker compose up -d" 2>/dev/null; then
      log "MSSQL kjører nå på localhost:1433 (user=sa)."
    else
      warn "Kunne ikke starte MSSQL (trolig docker-gruppemedlemskap ikke aktivt ennå)."
      log "Start manuelt etter reboot: cd $dir && docker compose up -d"
    fi
  else
    if (cd "$dir" && docker compose up -d); then
      log "MSSQL kjører nå på localhost:1433 (user=sa)."
    else
      warn "Kunne ikke starte MSSQL."
      log "Start manuelt: cd $dir && docker compose up -d"
    fi
  fi
}

main() {
  install_base_prereqs
  remove_snaps_and_prefer_native
  configure_lid_on_ac

  install_node_lts_nodesource

  setup_1password_repo_install
  setup_vscode_repo_install
  setup_brave_repo_install
  setup_atuin_repo_install

  install_discord_deb
  install_slack_deb
  install_postman_tarball
  install_intellij

  install_docker_and_compose
  setup_mssql_compose_and_start

  log "Ferdig."
  warn "Anbefalt: reboot (lokk-innstilling + docker-gruppe)."
  warn "Slack: Hvis installasjonen ble hoppet over pga CDN/403, last ned .deb fra https://slack.com/downloads/linux og kjør: sudo apt install ./slack-desktop-*.deb"
}

ensure_root "$@"
main
