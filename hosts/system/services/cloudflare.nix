# Cloudflare services: DDNS
# Updates the root A record with the current public IP every 5 minutes.
{ config, settings, ... }:
{
  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = config.sops.secrets.cloudflare_dns_api_token.path;
    domains = [ settings.domain ];
    proxied = false;
  };
}
