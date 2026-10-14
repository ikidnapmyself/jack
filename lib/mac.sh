JACK_DESC="macOS chores"
JACK_DOC_flush_dns="Flush the DNS cache, needs root"
JACK_DOC_nginx_reload="Reload nginx, needs root"
JACK_DOC_ssh_key="Generate an ed25519 SSH key for an email"

mac_flush_dns() {
  [ $# -eq 0 ] || die_usage "usage: jack mac flush-dns"
  require_root mac flush-dns
  killall -HUP mDNSResponder
}

mac_nginx_reload() {
  [ $# -eq 0 ] || die_usage "usage: jack mac nginx-reload"
  require_root mac nginx-reload
  require_cmd nginx
  nginx -s reload
}

mac_ssh_key() {
  ssh_keygen_for mac "$@"
}
