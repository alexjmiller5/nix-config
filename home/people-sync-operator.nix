{ lib, ... }:

# Operator-only injection, shared by both operator locations. No secret value
# is evaluated by Nix; installed app processes receive only their credentials.
{
  xdg.configFile."people-sync/operator.env".text = lib.mkDefault ''
    LIFE_HUB_URL=op://ug25zl4cfxnyk7rnwkyhea752i/5xs6y3x5sxkhmvbjlredlpk7oi/LIFE_HUB_URL
    LIFE_HUB_TOKEN=op://ug25zl4cfxnyk7rnwkyhea752i/5xs6y3x5sxkhmvbjlredlpk7oi/LIFE_HUB_TOKEN
    NOTION_API_TOKEN=op://ug25zl4cfxnyk7rnwkyhea752i/5xs6y3x5sxkhmvbjlredlpk7oi/NOTION_API_TOKEN
  '';
}
