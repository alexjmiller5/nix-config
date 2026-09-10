#!/usr/bin/env python3
"""Provision once with desktop auth; output only stable, non-secret item IDs."""

import argparse
import json
import os
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--state-directory", required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    state = args.state_directory.expanduser().resolve()
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    env = os.environ.copy()
    for key in ("OP_SERVICE_ACCOUNT_TOKEN", "OP_CONNECT_HOST", "OP_CONNECT_TOKEN"):
        env.pop(key, None)
    env["AGENT_OP_AUTH"] = "desktop"

    def op(*command, data=None):
        result = subprocess.run(
            ["op", *command],
            cwd=state,
            env=env,
            input=data,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode:
            raise SystemExit(result.stderr.strip() or "1Password provisioning failed")
        return result.stdout.strip()

    tags = f"{args.owner},Developer Credentials,Sensitive,Highly Sensitive"
    credentials_title = f"{args.owner} op Connect Credentials"
    token_title = f"{args.owner} op Connect Token"
    items = json.loads(op("item", "list", "--vault", args.vault, "--format", "json"))

    def existing(title):
        matches = [item["id"] for item in items if item["title"] == title]
        if len(matches) > 1:
            raise SystemExit(
                f"More than one item titled {title}; resolve before provisioning"
            )
        return matches[0] if matches else None

    credentials_id, token_id = existing(credentials_title), existing(token_title)
    servers = json.loads(op("connect", "server", "list", "--format", "json"))
    matches = [server for server in servers if server["name"] == args.server]
    if len(matches) > 1:
        raise SystemExit("More than one matching Connect server")
    credentials = state / "1password-credentials.json"
    if matches:
        server_id = matches[0]["id"]
        if not credentials.exists():
            if not credentials_id:
                raise SystemExit(
                    "Existing server has no local credentials or vault backup"
                )
            credentials.write_text(
                op("document", "get", credentials_id, "--vault", args.vault)
            )
    else:
        if credentials.exists() or credentials_id or token_id:
            raise SystemExit(
                "Existing credentials without the named server; resolve before provisioning"
            )
        # This command writes the file but prints a human-readable summary,
        # including when --format=json is selected. List is the JSON interface.
        op("connect", "server", "create", args.server, "--vaults", args.vault)
        servers = json.loads(op("connect", "server", "list", "--format", "json"))
        server_id = next(
            server["id"] for server in servers if server["name"] == args.server
        )
    credentials.chmod(0o600)
    if not credentials_id:
        op(
            "document",
            "create",
            str(credentials),
            "--vault",
            args.vault,
            "--title",
            credentials_title,
            "--tags",
            tags,
            "--format",
            "json",
        )
        items = json.loads(
            op("item", "list", "--vault", args.vault, "--format", "json")
        )
        credentials_id = existing(credentials_title)
    if not token_id:
        token = op(
            "connect",
            "token",
            "create",
            args.server + "-read",
            "--server",
            server_id,
            "--vault",
            args.vault + ",r",
        )
        item = {
            "title": token_title,
            "category": "API_CREDENTIAL",
            "tags": tags.split(","),
            "fields": [
                {
                    "id": "credential",
                    "label": "credential",
                    "type": "CONCEALED",
                    "value": token,
                }
            ],
        }
        result = json.loads(
            op(
                "item",
                "create",
                "-",
                "--vault",
                args.vault,
                "--tags",
                tags,
                "--format",
                "json",
                data=json.dumps(item),
            )
        )
        token_id = result["id"]
    print(
        json.dumps(
            {
                "serverId": server_id,
                "credentialsItemId": credentials_id,
                "tokenOpRef": f"op://{args.vault}/{token_id}/credential",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
