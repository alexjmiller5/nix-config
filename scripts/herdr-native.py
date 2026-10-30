"""Native Herdr session identity, automatic titles, and close/resume history."""

import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

STATE = Path(
    os.environ.get(
        "HERDR_NATIVE_STATE_DIR",
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "herdr-native",
    )
)
APP = os.environ.get("HERDR_APP_BIN", "herdr-app")
HC = os.environ.get("HERDR_CORE_BIN", "hc")


def run(argv, **kwargs):
    result = subprocess.run(
        argv, capture_output=True, text=True, timeout=15, check=True, **kwargs
    )
    return json.loads(result.stdout) if result.stdout.strip() else {}


def app(command, **args):
    if command in ("ls", "status"):
        return run([APP, command])
    result = run([APP, "do", command, json.dumps(args)])
    if "error" in result:
        raise ValueError(result["error"])
    return result


def rpc(method, **params):
    result = run(
        [HC, "connect"],
        input=json.dumps(
            {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
        )
        + "\n",
    )
    if "error" in result:
        raise ValueError(result["error"].get("message", "Core request failed"))
    return result["result"]


def load(path):
    return json.loads(path.read_text()) if path.exists() else []


def save(path, value):
    text = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def short_title(text):
    words = re.findall(r"[\w]+(?:[-'][\w]+)*", text, re.UNICODE)
    skip = {
        "please",
        "can",
        "you",
        "could",
        "would",
        "help",
        "me",
        "the",
        "a",
        "an",
        "to",
        "i",
        "want",
    }
    words = [word for word in words if word.lower() not in skip]
    return " ".join(words[:3]).title()[:24].rstrip()


def replace_title(current, previous, desired, named=True):
    return bool(desired and current != desired and (not named or current == previous))


def register(agent, session, terminal=None, cwd=None, title=None, session_file=None):
    terminal = terminal or os.environ.get("HC_TERMINAL_ID", "")
    if not re.fullmatch(r"t[0-9a-z]+", terminal):
        raise ValueError(
            "Registration needs the actual core terminal, from its client/hook"
        )
    if agent in ("codex", "claude"):
        uuid.UUID(session)
    elif not session_file or not Path(session_file).is_absolute():
        raise ValueError("Pi registration needs its absolute session file")
    previous = run([HC, "get", terminal]).get("labels", {})
    labels = {"session.agent": agent, "session.id": session}
    if previous.get("session.id") != session:
        labels.update(
            {"session.title": "", "session.explicit-title": "", "session.file": ""}
        )
    if cwd:
        labels["session.cwd"] = cwd
    if session_file:
        labels["session.file"] = session_file
    if title and not (
        previous.get("session.id") == session and previous.get("session.explicit-title")
    ):
        candidate = short_title(title)
        existing = (
            previous.get("session.title")
            if previous.get("session.id") == session
            else None
        )
        if candidate and (len(candidate.split()) >= 2 or not existing):
            labels["session.title"] = candidate
    run([HC, "label", terminal, *[key + "=" + value for key, value in labels.items()]])


def clear(terminal, session):
    record = run([HC, "get", terminal])
    if record.get("labels", {}).get("session.id") == session:
        run(
            [
                HC,
                "label",
                terminal,
                "session.agent=",
                "session.id=",
                "session.title=",
                "session.cwd=",
                "session.file=",
                "session.explicit-title=",
            ]
        )


def locate(agent, session):
    matches = [
        record
        for record in run([HC, "ls"])["terminals"]
        if record.get("labels", {}).get("session.agent") == agent
        and session
        in (record["labels"].get("session.id"), record["labels"].get("session.file"))
    ]
    if not matches:
        raise LookupError("No native core session match")
    if len(matches) != 1:
        raise ValueError("Multiple native core session matches")
    record = matches[0]
    labels = record["labels"]
    prefix = (
        record["address"].split("/", 1)[0] + "/" if "/" in record["address"] else ""
    )
    return {
        "runtime": "core",
        "terminal_id": record["address"],
        "tab_id": prefix + labels.get("herdr.tab", ""),
        "workspace_id": prefix + labels.get("herdr.space", ""),
        "agent": agent,
        "agent_session": {"value": session},
    }


def hook(agent):
    event = json.load(sys.stdin)
    if not os.environ.get("HC_TERMINAL_ID") or event.get("agent_id"):
        return
    # Shared Codex daemon hook environments cannot identify a terminal.
    if agent == "codex" and os.environ.get("HERDR_NATIVE_DIRECT") != "1":
        return
    session = event.get("session_id")
    if not session:
        return
    if event.get("hook_event_name") == "SessionEnd":
        clear(os.environ["HC_TERMINAL_ID"], session)
        return
    register(agent, session, cwd=event.get("cwd"), title=event.get("prompt"))


def resume_record(record):
    status = record.get("status") or {}
    labels = record.get("labels") or {}
    foreground = (record.get("foreground") or {}).get("name", "")
    agent = labels.get("session.agent") or status.get("app")
    cwd = (
        labels.get("session.cwd")
        or (record.get("foreground") or {}).get("cwd")
        or record.get("cwd")
    )
    if not cwd or not Path(cwd).is_absolute():
        raise ValueError("Cannot capture the terminal working directory")
    if agent in ("codex", "claude", "claude-code"):
        agent = "claude" if agent == "claude-code" else agent
        session = labels.get("session.id", "")
        try:
            uuid.UUID(session)
        except ValueError:
            raise ValueError(
                "Agent identity is not enrolled; leaving the tab open"
            ) from None
        return {
            "cwd": cwd,
            "argv": [agent, "resume" if agent == "codex" else "--resume", session],
            "working": status.get("state") == "working",
            "title": labels.get("session.title", ""),
        }
    if agent == "pi":
        session_file = labels.get("session.file", "")
        if not Path(session_file).is_absolute():
            raise ValueError("Pi session file is not enrolled; leaving the tab open")
        return {
            "cwd": cwd,
            "argv": ["pi", "--session", session_file],
            "working": status.get("state") == "working",
            "title": labels.get("session.title", ""),
        }
    if agent or foreground not in ("sh", "bash", "zsh", "fish", "nu", "pwsh"):
        raise ValueError("Cannot safely resume this program; leaving the tab open")
    return {"cwd": cwd, "argv": []}


def leaves(node):
    if "content" in node:
        return [node]
    return [leaf for child in node.get("children", []) for leaf in leaves(child)]


def validate_spec(spec):
    if not Path(spec["cwd"]).is_absolute():
        raise ValueError("Invalid archived working directory")
    argv = spec["argv"]
    if not argv:
        return
    if len(argv) != 3 or (argv[0], argv[1]) not in [
        ("codex", "resume"),
        ("claude", "--resume"),
        ("pi", "--session"),
    ]:
        raise ValueError("Unsupported archived resume command")
    if argv[0] == "pi":
        if not Path(argv[2]).is_absolute():
            raise ValueError("Invalid archived Pi session file")
    else:
        uuid.UUID(argv[2])


def label_restored(result, spec):
    if not spec.get("argv"):
        return
    argv = spec["argv"]
    labels = {
        "session.agent": argv[0],
        "session.id": argv[2],
        "session.cwd": spec["cwd"],
    }
    if argv[0] == "pi":
        labels["session.file"] = argv[2]
    if spec.get("title"):
        labels["session.title"] = spec["title"]
    run(
        [
            HC,
            "label",
            result["terminal"],
            *[key + "=" + value for key, value in labels.items()],
        ]
    )


def first_spec(node, records):
    leaf = leaves(node)[0]
    content = leaf["content"]
    if "terminal" in content:
        spec = records[content["terminal"]]
        validate_spec(spec)
        return spec
    if "mod" in content:
        return {"mod": content["mod"], "props": content.get("props", {})}
    raise ValueError("Unsupported pane content; leaving the tab open")


def ensure_closed(entry):
    for space in app("ls")["spaces"]:
        if any(tab["id"] == entry["original_tab"] for tab in space["tabs"]):
            raise ValueError(
                "Original tab is still open; refusing a duplicate conversation"
            )
    identities = {
        record["argv"][-1]
        for record in entry.get("records", {}).values()
        if record["argv"]
    }
    if identities:
        for record in run([HC, "ls"])["terminals"]:
            labels = record.get("labels", {})
            if (
                labels.get("session.id") in identities
                or labels.get("session.file") in identities
            ):
                raise ValueError(
                    "This conversation is already running; refusing a duplicate"
                )
    if entry.get("restoring"):
        raise ValueError(
            "An interrupted restore has a receipt; inspect it before retrying"
        )


def cycle_pane(step):
    world, status = app("ls"), app("status")
    space = next((space for space in world["spaces"] if space.get("active")), None)
    if not space:
        return
    tab = next((tab for tab in space["tabs"] if tab.get("active")), None)
    if not tab:
        return
    machine = space.get("machine")
    prefix = machine + "/" if machine else ""
    document = rpc("doc.get", name="herdr-app", **({"on": machine} if machine else {}))[
        "value"
    ]
    tree = next(
        t["root"]
        for s in document["spaces"]
        for t in s["tabs"]
        if prefix + t["id"] == tab["id"]
    )
    panes = [prefix + leaf["id"] for leaf in leaves(tree)]
    if panes:
        current = (
            panes.index(status["focused_pane"])
            if status.get("focused_pane") in panes
            else (0 if step < 0 else -1)
        )
        app("pane.focus", pane=panes[(current + step) % len(panes)])


def reconnect():
    space = next((space for space in app("ls")["spaces"] if space.get("active")), None)
    if not space or not space.get("machine"):
        raise ValueError("Select a remote session before reconnecting")
    result = rpc("machine.connect", machine=space["machine"])
    if result.get("state") != "connected":
        raise ValueError("Remote machine needs attention; check hc machine ls")


def capture(tab_id=None):
    world = app("ls")
    selected = [
        (space, tab)
        for space in world["spaces"]
        for tab in space["tabs"]
        if (
            tab["id"] == tab_id if tab_id else space.get("active") and tab.get("active")
        )
    ]
    if len(selected) != 1:
        raise ValueError("No unique selected tab")
    space, tab = selected[0]
    machine = space.get("machine")
    document = rpc("doc.get", name="herdr-app", **({"on": machine} if machine else {}))[
        "value"
    ]
    local_id = tab["id"].split("/", 1)[-1] if machine else tab["id"]
    matches = [
        (s, t) for s in document["spaces"] for t in s["tabs"] if t["id"] == local_id
    ]
    if len(matches) != 1:
        raise ValueError("Could not capture the exact tab layout")
    source_space, source_tab = matches[0]
    machine_id = None
    if machine:
        machine_id = next(
            (
                item["id"]
                for item in run([HC, "machine", "ls"])["machines"]
                if item["name"] == machine
            ),
            None,
        )
        if not machine_id:
            raise ValueError("Cannot capture the machine identity; tab left open")
    records = {}
    for leaf in leaves(source_tab["root"]):
        terminal = leaf["content"].get("terminal")
        if terminal:
            address = machine + "/" + terminal if machine else terminal
            records[terminal] = resume_record(run([HC, "get", address]))
    for leaf in leaves(source_tab["root"]):
        first_spec(leaf, records)
    return {
        "id": uuid.uuid4().hex,
        "original_tab": tab["id"],
        "space": space["id"],
        "space_name": source_space["name"],
        "space_folder": source_space["folder"],
        "machine": machine,
        "machine_id": machine_id,
        "name": source_tab["name"],
        "auto_title": dict(load(STATE / "titles.json")).get(tab["id"])
        == source_tab["name"],
        "tree": source_tab["root"],
        "records": records,
        "focused": app("status").get("focused_pane"),
        "index": next(
            i for i, t in enumerate(space["tabs"], 1) if t["id"] == tab["id"]
        ),
    }


def check_snapshot(entry):
    machine = entry.get("machine")
    document = rpc("doc.get", name="herdr-app", **({"on": machine} if machine else {}))[
        "value"
    ]
    local_id = (
        entry["original_tab"].split("/", 1)[-1] if machine else entry["original_tab"]
    )
    matches = [
        tab
        for space in document["spaces"]
        for tab in space["tabs"]
        if tab["id"] == local_id
    ]
    if len(matches) != 1 or matches[0]["root"] != entry["tree"]:
        raise ValueError("Tab layout changed while saving; tab left open")
    for terminal, saved in entry.get("records", {}).items():
        address = machine + "/" + terminal if machine else terminal
        current = resume_record(run([HC, "get", address]))
        if current.get("argv") != saved.get("argv"):
            raise ValueError("Conversation changed while saving; tab left open")
        saved["working"] = current.get("working", False)


def close_tab(path, tab_id=None):
    entry = capture(tab_id)
    history = load(path)
    history = [
        item for item in history if item["original_tab"] != entry["original_tab"]
    ]
    history.append(entry)
    save(path, history)  # A durable snapshot is required before ending any process.
    check_snapshot(entry)
    for terminal, record in entry.get("records", {}).items():
        if record.get("working"):
            address = (
                entry["machine"] + "/" + terminal if entry["machine"] else terminal
            )
            run([HC, "interrupt", address, "--timeout", "5"])
            if (run([HC, "get", address]).get("status") or {}).get(
                "state"
            ) == "working":
                raise ValueError(
                    "The agent did not stop; snapshot saved and tab left open"
                )
    app("tab.close", id=entry["original_tab"], confirmed=True)
    # The window queues its kills; finish them before an immediate undo-close.
    for terminal in entry.get("records", {}):
        address = entry["machine"] + "/" + terminal if entry["machine"] else terminal
        try:
            record = run([HC, "get", address])
        except subprocess.CalledProcessError:
            continue
        if record.get("state") == "live":
            try:
                run([HC, "kill", address])
            except subprocess.CalledProcessError:
                if run([HC, "get", address]).get("state") == "live":
                    raise


def restore_splits(node, pane, records):
    children = node.get("children", [])
    if not children:
        return {node["id"]: pane}
    anchors = [pane]
    direction = "right" if node.get("type") == "row" else "down"
    # Create siblings before nesting, so a row of columns stays a row of columns.
    for child in children[1:]:
        spec = first_spec(child, records)
        if "mod" in spec:
            result = app("pane.split", pane=anchors[-1], direction=direction, **spec)
        else:
            app("pane.focus", pane=anchors[-1])
            result = app(
                "terminal.open",
                place=direction,
                folder=spec["cwd"],
                **({"argv": spec["argv"]} if spec["argv"] else {}),
            )
        label_restored(result, spec)
        anchors.append(result["pane"])
    mapped = {}
    for child, anchor in zip(children, anchors):
        mapped.update(restore_splits(child, anchor, records))
    return mapped


def reopen(path):
    history = load(path)
    if not history:
        return
    entry = history[-1]
    ensure_closed(entry)
    for record in entry.get("records", {}).values():
        validate_spec(record)
    world = app("ls")
    spec = first_spec(entry["tree"], entry["records"])
    machine = None
    if entry.get("machine"):
        machine = next(
            (
                item["name"]
                for item in run([HC, "machine", "ls"])["machines"]
                if item["id"] == entry.get("machine_id")
            ),
            None,
        )
        if not machine:
            raise ValueError("The saved machine is not enrolled here; history retained")
    entry["restoring"] = True
    save(path, history)  # An uncertain create is never automatically replayed.
    args = {
        "name": entry["name"],
        **({"argv": spec["argv"]} if spec.get("argv") else {}),
        **({"folder": spec["cwd"]} if "cwd" in spec else {}),
        **({k: v for k, v in spec.items() if k in ("mod", "props")}),
    }
    if any(s["id"] == entry["space"] for s in world["spaces"]):
        result = app("tab.new", space=entry["space"], **args)
    else:
        machine = {"machine": machine} if machine else {}
        if "mod" in spec:
            seed = app(
                "space.new",
                name=entry["space_name"],
                **machine,
                **(
                    {"folder": entry["space_folder"]}
                    if entry.get("space_folder")
                    else {}
                ),
            )
            entry["restored_tab"] = seed["tab"]
            save(path, history)
            result = app("tab.new", space=seed["space"], **args)
            app("tab.close", id=seed["tab"], confirmed=True)
        else:
            args["tab"] = args.pop("name")
            result = app("space.new", name=entry["space_name"], **machine, **args)
    label_restored(result, spec)
    created = result["tab"]
    entry["restored_tab"] = created
    save(path, history)
    world = app("ls")
    pane = result.get("pane") or next(
        p["pane"]
        for s in world["spaces"]
        for t in s["tabs"]
        if t["id"] == created
        for p in t["terminals"]
    )
    mapped = restore_splits(entry["tree"], pane, entry["records"])
    focused = (entry.get("focused") or "").split("/", 1)[-1]
    if focused in mapped:
        app("pane.focus", pane=mapped[focused])
    app("tab.move", id=created, index=entry["index"])
    if entry.get("auto_title"):
        previous = dict(load(STATE / "titles.json"))
        previous[created] = entry["name"]
        save(STATE / "titles.json", list(previous.items()))
    history.pop()
    save(path, history)


def preferred_title(record):
    labels = record.get("labels", {})
    fallback = labels.get("session.title", "")
    if labels.get("session.explicit-title"):
        return fallback
    native = short_title(record.get("title", "").split("|", 1)[0])
    if labels.get("session.agent") and native.lower() not in (
        "",
        "codex",
        "claude",
        "claude code",
        "pi",
        "working",
        "ready",
        "idle",
        "done",
        "openai codex",
    ):
        return native
    return fallback


def titles(path):
    try:
        world = app("ls")
    except (ValueError, subprocess.SubprocessError):
        return  # Never open a window just to rename it.
    records = {r["address"]: r for r in run([HC, "ls"])["terminals"]}
    previous = dict(load(path))
    named, available = set(), set()
    for machine in {space.get("machine") for space in world["spaces"]}:
        try:
            document = (
                rpc(
                    "doc.get", name="herdr-app", **({"on": machine} if machine else {})
                )["value"]
                or {}
            )
        except (ValueError, subprocess.SubprocessError):
            continue
        available.add(machine)
        for space in document.get("spaces", []):
            for tab in space["tabs"]:
                if tab.get("name"):
                    named.add(machine + "/" + tab["id"] if machine else tab["id"])
    for space in world["spaces"]:
        if space.get("machine") not in available:
            continue
        for tab in space["tabs"]:
            names = [
                preferred_title(records.get(t["terminal"], {}))
                for t in tab["terminals"]
            ]
            desired = next((name for name in names if name), "")
            if replace_title(
                tab["name"], previous.get(tab["id"]), desired, named=tab["id"] in named
            ):
                previous[tab["id"]] = desired
                save(path, list(previous.items()))
                app("tab.rename", id=tab["id"], name=desired)


def watch():
    with subprocess.Popen([HC, "events"], stdout=subprocess.PIPE, text=True) as process:
        try:
            for line in process.stdout:
                event = json.loads(line)
                if "terminals" in event or event.get("type") in (
                    "labels",
                    "label",
                    "title",
                    "doc",
                ):
                    with (STATE / "lock").open("a") as lock:
                        fcntl.flock(lock, fcntl.LOCK_EX)
                        titles(STATE / "titles.json")
        finally:
            process.terminate()
            process.wait()


def guard_legacy(root):
    # Provider installers own these files; the Nix activation reapplies compatibility guards.
    paths = [
        (
            root / ".claude/hooks/herdr-agent-state.sh",
            "set -eu\n",
            'set -eu\n[ -z "${HC_TERMINAL_ID:-}" ] || exit 0\n',
        ),
        (
            root / ".pi/agent/extensions/herdr-agent-state.ts",
            'return HERDR_ENV === "1"',
            'return !process.env.HC_TERMINAL_ID && HERDR_ENV === "1"',
        ),
    ]
    for path, before, after in paths:
        if path.exists():
            text = path.read_text()
            if "HC_TERMINAL_ID" not in text:
                if before not in text:
                    raise ValueError(
                        "Legacy Herdr adapter changed; review its native guard"
                    )
                path.write_text(text.replace(before, after, 1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=[
            "guard-legacy",
            "register",
            "clear",
            "locate",
            "name",
            "hook",
            "close",
            "reopen",
            "titles",
            "watch",
            "pane-next",
            "pane-previous",
            "reconnect",
        ],
    )
    parser.add_argument(
        "--tab", help="Explicit tab to close; defaults to the selected tab"
    )
    parser.add_argument("--agent", choices=["codex", "claude", "pi"])
    parser.add_argument("--session")
    parser.add_argument("--terminal")
    parser.add_argument("--cwd")
    parser.add_argument("--title")
    parser.add_argument("--session-file")
    args = parser.parse_args()
    if args.command in ("register", "hook", "locate", "name") and not args.agent:
        parser.error("--agent is required")
    if args.command in ("register", "clear", "locate", "name") and not args.session:
        parser.error("--session is required")
    if args.command == "clear" and not args.terminal:
        parser.error("--terminal is required")
    try:
        STATE.mkdir(parents=True, exist_ok=True)
        if args.command == "guard-legacy":
            guard_legacy(Path.home())
        elif args.command == "register":
            register(
                args.agent,
                args.session,
                args.terminal,
                args.cwd,
                args.title,
                args.session_file,
            )
        elif args.command in ("locate", "name"):
            found = locate(args.agent, args.session)
            if args.command == "locate":
                print(json.dumps(found))
            else:
                title = short_title(args.title or "")
                if not title:
                    raise ValueError("A task title is required")
                run(
                    [
                        HC,
                        "label",
                        found["terminal_id"],
                        "session.title=" + title,
                        "session.explicit-title=1",
                    ]
                )
        elif args.command == "clear":
            clear(args.terminal, args.session)
        elif args.command == "hook":
            hook(args.agent)
        elif args.command == "watch":
            watch()
        elif args.command in ("pane-next", "pane-previous"):
            cycle_pane(1 if args.command == "pane-next" else -1)
        elif args.command == "reconnect":
            reconnect()
        else:
            with (STATE / "lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                if args.command == "close":
                    close_tab(STATE / "archive.json", args.tab)
                elif args.command == "reopen":
                    reopen(STATE / "archive.json")
                else:
                    titles(STATE / "titles.json")
    except LookupError as error:
        print("Herdr: " + str(error), file=sys.stderr)
        return 3
    except (OSError, ValueError, TypeError, subprocess.SubprocessError) as error:
        print("Herdr: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
