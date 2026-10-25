# Secrets decrypted by chezmoi as KEY=value lines; absent on machines without
# the age key (and in zssh bundles).
if [[ -r $XDG_CONFIG_HOME/secrets/env ]]; then
  set -a
  source "$XDG_CONFIG_HOME/secrets/env"
  set +a
fi
