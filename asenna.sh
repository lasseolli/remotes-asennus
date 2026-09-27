#!/bin/bash
# Etälaitteen käyttöönotto (Linux Mint / Ubuntu): ansible-pull + MeshCentral-agentti + Zabbix-raportointi.
#
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/lasseolli/remotes-asennus/main/asenna.sh)" -- <ryhmä>
#
# Skripti kysyy asennusavaimen (tai lukee sen muuttujasta REMOTES_AVAIN). Avaimella avataan paketti.enc,
# jossa on yksityisen asetusrepon vain luku -avain ja ryhmien salaisuusavaimet. Kone saa vain oman
# ryhmänsä avaimen. Varsinainen asennus (Mesh, Zabbix, WLANit, leirikeskusprofiili) tulee
# yksityisestä reposta, jota kone hakee jatkossa itse tunnin välein ja aina verkon noustessa.
set -euo pipefail
PAKETTI=https://raw.githubusercontent.com/lasseolli/remotes-asennus/main/paketti.enc
REPO=git@github.com:lasseolli/remotes.git
ETC=/etc/remotes; VAR=/var/lib/remotes
kuole() { echo "VIRHE: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || kuole "aja rootina (sudo)"
command -v apt-get >/dev/null || kuole "vain Debian-/Ubuntu-pohjaiset (Mint, Ubuntu)"
ryhma="${1:-}"

export DEBIAN_FRONTEND=noninteractive
for k in curl openssl python3; do command -v $k >/dev/null || { apt-get update -qq; apt-get install -y -qq curl openssl python3; break; }; done

avain="${REMOTES_AVAIN:-}"
if [ -z "$avain" ]; then
  [ -r /dev/tty ] || kuole "anna asennusavain muuttujassa REMOTES_AVAIN"
  read -rsp "Asennusavain: " avain </dev/tty; echo
fi
paketti=$(curl -fsSL --max-time 60 "$PAKETTI" | AVAIN="$avain" openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -md sha256 -a -A -pass env:AVAIN 2>/dev/null) || kuole "väärä asennusavain tai paketti ei latautunut"
ryhmat=$(python3 -c 'import json,sys; print(" ".join(sorted(json.loads(sys.stdin.read())["avaimet"])))' <<<"$paketti")
if [ -z "$ryhma" ] || ! grep -qw -- "$ryhma" <<<"$ryhmat"; then
  kuole "anna ryhmä: ${ryhmat// /, }   (esim. ... -- kallio)"
fi

echo "== Käyttöönotto: $(hostname), ryhmä $ryhma"
install -d -m 0700 "$ETC"
umask 077
python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["deploy_key"], end="")' <<<"$paketti" > "$ETC/deploy-key"
R="$ryhma" python3 -c 'import json,os,sys; print(json.loads(sys.stdin.read())["avaimet"][os.environ["R"]])' <<<"$paketti" > "$ETC/avain"
umask 022
echo "$ryhma" > "$ETC/ryhma"; chmod 0644 "$ETC/ryhma"
unset paketti avain

# GitHubin SSH-palvelinavaimet (api.github.com/meta), ettei ensimmäistä yhteyttä tarvitse hyväksyä sokkona
touch /etc/ssh/ssh_known_hosts
while read -r k; do grep -qF "$k" /etc/ssh/ssh_known_hosts || echo "github.com $k" >> /etc/ssh/ssh_known_hosts; done <<'KEYS'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
KEYS

echo "== Ansible ja git"
apt-get update -qq
apt-get install -y -qq git ansible >/dev/null

echo "== Asetusrepo"
install -d -m 0755 "$VAR"
if [ ! -d "$VAR/repo/.git" ]; then
  rm -rf "$VAR/repo"
  GIT_SSH_COMMAND="ssh -i $ETC/deploy-key -o IdentitiesOnly=yes" git clone -q --depth 1 "$REPO" "$VAR/repo"
fi
chmod 0700 "$VAR/repo"

echo "== Ensimmäinen ajo (jatkossa remotes-pull.timer)"
bash "$VAR/repo/linux/tiedostot/remotes-pull"
echo "== Valmis. Tila: /var/lib/remotes/tila.json, loki: journalctl -u remotes-pull"
