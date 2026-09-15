{ lib, ... }:

# People Sync on both Macs: the app's own home module installs the CLI wrapped
# with the facts only this operator knows. Credentials are injected per run
# from operator.env (ID-based op refs); no secret value is evaluated by Nix,
# and the login credential commands stay unset (sites are signed into by hand
# in the shared Chrome).
{
  programs.people-sync = {
    enable = true;
    # The mini's shared agent Chrome over the chrome-control ssh forward;
    # home/mac-mini.nix overrides this with the local port.
    endpoint = lib.mkDefault "127.0.0.1:9223";
    notion.peopleDataSource = "1a803953-a8af-80ab-824d-000bfe407316";
    # Notion DBs relating to People, checked by `reconcile merge` (property
    # IDs, not names, so a rename cannot silently disable the check).
    notion.relations = {
      Gifts = [
        "0c39fffe-c8c2-43a5-af03-0a378c682c1c"
        "%3FT%40U"
      ]; # Recipient(s)
      Quotes = [
        "18f03953-a8af-802f-8950-000b03428f8e"
        "Y%5B%3E%7B"
      ]; # Person
      Trips = [
        "19603953-a8af-80af-8803-000be09834a6"
        "t%3DJH"
      ]; # Travel Companions
      Calendar = [
        "24c03953-a8af-8036-8b1b-000bb8d77b03"
        "%3DS%60m"
      ]; # Attendees
    };
  };

  xdg.configFile."people-sync/operator.env".text = lib.mkDefault ''
    LIFE_HUB_URL=op://ug25zl4cfxnyk7rnwkyhea752i/5xs6y3x5sxkhmvbjlredlpk7oi/LIFE_HUB_URL
    LIFE_HUB_TOKEN=op://ug25zl4cfxnyk7rnwkyhea752i/5xs6y3x5sxkhmvbjlredlpk7oi/LIFE_HUB_TOKEN
    NOTION_API_TOKEN=op://ug25zl4cfxnyk7rnwkyhea752i/5xs6y3x5sxkhmvbjlredlpk7oi/NOTION_API_TOKEN
  '';
}
