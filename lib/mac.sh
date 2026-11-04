JACK_DESC="macOS chores"
JACK_OS="Darwin"
JACK_DOC_flush_dns="Flush the DNS cache, needs root"
JACK_DOC_ssh_key="Generate an ed25519 SSH key for an email, default path ~/.ssh/id_ed25519"
JACK_USAGE_flush_dns=""
JACK_USAGE_ssh_key="<email> [path]"

mac_flush_dns() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage mac flush-dns)"
  require_root mac flush-dns
  killall -HUP mDNSResponder
}

mac_ssh_key() {
  ssh_keygen_for mac "$@"
}
