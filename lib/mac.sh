JACK_DESC="macOS chores"
JACK_OS="Darwin"
JACK_ABOUT="macOS chores: refreshing the DNS cache and creating SSH keys. Low risk. Flushing DNS needs sudo."
JACK_DOC_flush_dns="Flush the DNS cache, needs root"
JACK_DOC_ssh_key="Generate an ed25519 SSH key for an email, default path ~/.ssh/id_ed25519"
JACK_USAGE_flush_dns=""
JACK_USAGE_ssh_key="<email> [path]"
JACK_INFO_flush_dns="Clears the cached name to address lookups so the Mac asks DNS again. Use it after changing DNS settings or when a site resolves to an old address. Safe. Needs sudo."
JACK_INFO_ssh_key="Creates a new ed25519 key pair for logging in to servers and Git hosts, then prints where the public key is so you can share it. Refuses to overwrite an existing key. ssh-keygen asks for an optional passphrase."

mac_flush_dns() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage mac flush-dns)"
  require_root mac flush-dns
  killall -HUP mDNSResponder
}

mac_ssh_key() {
  ssh_keygen_for mac "$@"
}
