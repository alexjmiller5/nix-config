# Print a Google OAuth access token for gog's client on stdout. The "AI Agent Gog
# Token Export" item holds the refresh token (credential field, `gog auth tokens
# export` JSON) plus a cached access_token/expires_at pair written back after each
# refresh; "AI Agent Gog OAuth Client" holds the client JSON. Fast path (cached token
# still valid for a minute) = ONE op call, no Google round-trip; slow path (~hourly) =
# curl refresh + 1P writeback. Secrets travel via stdin and the environment, never
# argv. Interpolated after agent-detect.sh and agent-op-env.sh (op_has_auth).
item=""
if op_has_auth; then
  item="$(op item get jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm --format json || true)"
fi
if [ -z "$item" ]; then
  echo "gog-access-token: no 1Password auth to read the gog token item" >&2
  exit 1
fi
at="$(jq -r '[.fields[] | select(.label == "access_token")][0].value // empty' <<<"$item")"
exp="$(jq -r '[.fields[] | select(.label == "expires_at")][0].value // empty' <<<"$item")"
case "$exp" in ("" | *[!0-9]*) exp=0 ;; esac
now="$(date +%s)"
if [ -n "$at" ] && [ "$now" -lt "$((exp - 60))" ]; then
  printf '%s\n' "$at"
  exit 0
fi
rt="$(jq -r '[.fields[] | select(.id == "credential")][0].value // empty' <<<"$item" | jq -r '.refresh_token // empty' 2>/dev/null || true)"
client="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/4x66lrvreiljbmepa6esgkyu2e/credential' || true)"
cid="$(jq -r '.installed.client_id // .web.client_id // empty' <<<"$client" 2>/dev/null || true)"
csec="$(jq -r '.installed.client_secret // .web.client_secret // empty' <<<"$client" 2>/dev/null || true)"
if [ -z "$rt" ] || [ -z "$cid" ]; then
  echo "gog-access-token: no refresh token or OAuth client in 1Password - Alex runs \`gog-auth-bootstrap\` in his own terminal" >&2
  exit 1
fi
resp="$(printf 'grant_type=refresh_token&client_id=%s&client_secret=%s&refresh_token=%s' "$cid" "$csec" "$rt" \
  | curl -s --max-time 30 --data @- https://oauth2.googleapis.com/token || true)"
at="$(jq -r '.access_token // empty' <<<"$resp" 2>/dev/null || true)"
expin="$(jq -r '.expires_in // 3600' <<<"$resp" 2>/dev/null || echo 3600)"
case "$expin" in ("" | *[!0-9]*) expin=3600 ;; esac
if [ -z "$at" ]; then
  # invalid_grant = refresh token revoked (password change / 6mo idle / consent
  # withdrawn) -> human re-consent is the only fix.
  err="$(jq -r '.error // empty' <<<"$resp" 2>/dev/null || true)"
  echo "gog wrapper: token refresh failed (${err:-no response from Google}) - refresh token likely revoked. Fix: Alex runs \`gog-auth-bootstrap\` in his own terminal (alias; script in the gog skill)." >&2
  exit 1
fi
# Cache the new pair: the item JSON (tags included) goes back as an edit template on
# stdin, so the token never reaches argv; a failed writeback only costs the next call
# a refresh.
AT="$at" EXP="$((now + expin))" jq '
  def put($label; $type; $value):
    if any(.fields[]; .label == $label)
    then (.fields[] | select(.label == $label)).value = $value
    else .fields += [{label: $label, type: $type, value: $value}] end;
  put("access_token"; "CONCEALED"; env.AT) | put("expires_at"; "STRING"; env.EXP)' <<<"$item" \
  | op item edit jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm >/dev/null 2>&1 || true
printf '%s\n' "$at"
