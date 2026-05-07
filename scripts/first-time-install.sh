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
              gnupg2 xdg-utils desktop-file-utils jq build-essential unzip zip xclip
}

remove_snaps_and_prefer_native() {
  log "Fjerner kjente problem-Snaps og foretrekker native der vi kan"
  # Slack Snap gir ofte keyring-problemer
  remove_snap_if_present "slack"

  # Discord finnes ofte som snap også; vi foretrekker .deb
  remove_snap_if_present "discord"

  # Postman finnes som snap; vi foretrekker /opt-install
  remove_snap_if_present "postman"

  # VS Code: foretrekker Microsoft APT-repo fremfor snap
  remove_snap_if_present "code"

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

install_development_tools() {
  log "Installerer utviklingsverktøy (git, pre-commit, docker, etc.)"
  apt_update
  apt_install git pre-commit docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  
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

apply_system_preferences() {
  log "Setter systempreferanser (GNOME gsettings)"
  local u; u="$(invoking_user)"
  local script_dir; script_dir="$(cd "$(dirname "$0")" && pwd)"
  local prefs_script="$script_dir/set-system-preferences.sh"

  if [[ ! -f "$prefs_script" ]]; then
    warn "Fant ikke $prefs_script – hopper over systempreferanser."
    return 0
  fi

  chmod +x "$prefs_script"

  if [[ -n "${u:-}" && "$u" != "root" ]]; then
    # gsettings må kjøres som bruker (ikke root) og trenger en aktiv D-Bus-sesjon.
    local bus
    bus="$(su - "$u" -c 'echo $DBUS_SESSION_BUS_ADDRESS' 2>/dev/null || true)"
    if [[ -z "$bus" ]]; then
      # Prøv å finne D-Bus-socket fra kjørende sesjon
      bus="$(find /run/user -name "bus" 2>/dev/null | grep "$(id -u "$u")" | head -n 1 || true)"
      [[ -n "$bus" ]] && bus="unix:path=$bus"
    fi
    if [[ -n "$bus" ]]; then
      DBUS_SESSION_BUS_ADDRESS="$bus" su - "$u" -c "bash '$prefs_script'"
    else
      warn "Finner ikke D-Bus-sesjon for '$u' – logger inn via su for å kjøre preferanser."
      su - "$u" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$u")/bus bash '$prefs_script'" || \
        warn "Kunne ikke sette systempreferanser. Kjør '$prefs_script' manuelt etter innlogging."
    fi
  else
    bash "$prefs_script" || warn "Kunne ikke sette systempreferanser."
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

setup_docker_ce_repo_install() {
  log "Legger til Docker CE APT repo (offisielt)"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt_update
}

install_shell_tools() {
  log "Installerer shell-verktøy (zsh, ripgrep, fonter, syntax highlighting)"
  apt_install zsh ripgrep fonts-firacode zsh-syntax-highlighting
}

install_language_packs() {
  log "Installerer norsk språkpakke og stavekontroll"
  apt_install language-pack-nb language-pack-gnome-nb hunspell-no wnorwegian
}

install_python_tools() {
  log "Installerer Python-verktøy (pipx, pip, venv, osv.)"
  apt_install pipx python3-pip python3-venv python3-netifaces
}

install_email_client() {
  log "Installerer e-postklient (Evolution med Exchange-støtte)"
  apt_install evolution evolution-ews
}

setup_azure_cli_repo_install() {
  log "Installerer Azure CLI (Microsoft APT repo)"
  # Gjenbruker Microsoft GPG-nøkkel lagt til av setup_vscode_repo_install
  local codename; codename="$(lsb_release -cs)"
  cat >/etc/apt/sources.list.d/azure-cli.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${codename}
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
  apt_update
  apt_install azure-cli
}

setup_dotnet_repo_install() {
  log "Installerer .NET SDK 10 (Microsoft APT repo)"
  # Gjenbruker Microsoft GPG-nøkkel lagt til av setup_vscode_repo_install
  local codename; codename="$(lsb_release -cs)"
  local version; version="$(lsb_release -rs)"
  cat >/etc/apt/sources.list.d/microsoft-prod.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/ubuntu/${version}/prod
Suites: ${codename}
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
  apt_update
  apt_install dotnet-sdk-10.0
}

setup_kubectl_repo_install() {
  log "Installerer kubectl (Kubernetes APT repo)"
  local kube_minor
  kube_minor="$(curl -fsSL https://dl.k8s.io/release/stable.txt | grep -oP 'v[0-9]+\.[0-9]+')" \
    || kube_minor="v1.32"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${kube_minor}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${kube_minor}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list
  apt_update
  apt_install kubectl
  log "kubectl installert: $(kubectl version --client 2>/dev/null || true)"
}

install_k9s_binary() {
  log "Installerer k9s (Kubernetes TUI)"
  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/derailed/k9s/releases/latest" | jq -r '.tag_name')" \
    || die "Klarte ikke å hente k9s versjon."

  download_with_ua \
    "https://github.com/derailed/k9s/releases/download/${tag}/k9s_Linux_amd64.tar.gz" \
    "$tmpdir/k9s.tar.gz" || die "k9s-nedlasting feilet."

  tar -xzf "$tmpdir/k9s.tar.gz" -C "$tmpdir" k9s
  install -m 0755 "$tmpdir/k9s" /usr/local/bin/k9s
  log "k9s installert: $(k9s version --short 2>/dev/null || true)"
}

install_kubelogin_binary() {
  log "Installerer kubelogin (Azure AD kubectl auth plugin)"
  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/Azure/kubelogin/releases/latest" | jq -r '.tag_name')" \
    || die "Klarte ikke å hente kubelogin versjon."

  download_with_ua \
    "https://github.com/Azure/kubelogin/releases/download/${tag}/kubelogin-linux-amd64.zip" \
    "$tmpdir/kubelogin.zip" || die "kubelogin-nedlasting feilet."

  unzip -q "$tmpdir/kubelogin.zip" -d "$tmpdir/kubelogin"
  local bin
  bin="$(find "$tmpdir/kubelogin" -name "kubelogin" -type f | head -n 1)"
  [[ -n "$bin" ]] || die "kubelogin-binary ikke funnet etter utpakking."
  install -m 0755 "$bin" /usr/local/bin/kubelogin
  log "kubelogin installert: $(kubelogin --version 2>/dev/null || true)"
}

main() {
  install_base_prereqs
  remove_snaps_and_prefer_native
  configure_lid_on_ac

  install_shell_tools
  install_language_packs
  install_python_tools
  install_email_client

  install_node_lts_nodesource

  setup_1password_repo_install
  setup_vscode_repo_install
  setup_brave_repo_install
  setup_atuin_repo_install
  setup_azure_cli_repo_install
  setup_dotnet_repo_install    # Bruker Microsoft GPG-nøkkel fra setup_vscode_repo_install

  setup_docker_ce_repo_install
  install_development_tools
  install_discord_deb
  install_slack_deb
  install_postman_tarball
  install_intellij

  setup_kubectl_repo_install
  install_k9s_binary
  install_kubelogin_binary

  setup_mssql_compose_and_start

  apply_system_preferences

  log "Ferdig."
  warn "Anbefalt: reboot (lokk-innstilling + docker-gruppe)."
  warn "Slack: Hvis installasjonen ble hoppet over pga CDN/403, last ned .deb fra https://slack.com/downloads/linux og kjør: sudo apt install ./slack-desktop-*.deb"
}

ensure_root "$@"
main
