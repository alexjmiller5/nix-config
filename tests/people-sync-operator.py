"""Verify the rendered credential seam for both enrolled callers, without resolving secrets."""
import json
import subprocess

prefix = 'op://ug25zl4cfxnyk7rnwkyhea752i/5xs6y3x5sxkhmvbjlredlpk7oi/'
for host, field in [('mac-mini', 'SOMA_COMM_HUB_TOKEN_MAC_MINI'), ('macbook-air', 'SOMA_COMM_HUB_TOKEN_MACBOOK_AIR')]:
    rendered = json.loads(subprocess.check_output([
        'nix', 'eval', '--json', f'.#darwinConfigurations.{host}.config.home-manager.users',
        '--apply', 'users: builtins.mapAttrs (_: cfg: cfg.xdg.configFile."people-sync/operator.env".text) users',
    ], text=True))
    assert len(rendered) == 1
    env = dict(line.split('=', 1) for line in next(iter(rendered.values())).splitlines() if line)
    assert env == {
        'SOMA_HUB_URL': prefix + 'LIFE_HUB_URL',
        'SOMA_HUB_TOKEN': prefix + 'LIFE_HUB_TOKEN',
        'NOTION_API_TOKEN': prefix + 'NOTION_API_TOKEN',
        'SOMA_COMM_HUB_TOKEN': prefix + field,
    }, f'{host}: rendered operator refs do not match its independent enrolled credential'
print('PASS both rendered People Sync caller refs; base credential refs preserved by stable field ID')
