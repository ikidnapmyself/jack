JACK_DESC="macOS chores"
JACK_DOC_flush_dns="Flush the DNS cache, needs root"
JACK_DOC_nginx_reload="Reload nginx, needs root"
JACK_DOC_ssh_key="Generate an ed25519 SSH key for an email"
JACK_USAGE_flush_dns=""
JACK_USAGE_nginx_reload=""
JACK_USAGE_ssh_key="<email>"

mac_flush_dns() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage mac flush-dns)"
  require_root mac flush-dns
  killall -HUP mDNSResponder
}

mac_nginx_reload() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage mac nginx-reload)"
  require_root mac nginx-reload
  require_cmd nginx
  nginx -s reload
}

mac_ssh_key() {
  ssh_keygen_for mac "$@"
}
