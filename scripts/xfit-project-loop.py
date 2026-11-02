#!/usr/bin/env python3
"""Read-only project-cycle status and offline Notion synchronization preview."""
import argparse
import hashlib
import json
import sys

TASK_STATUSES = {"pending", "in_progress", "blocked", "done"}
TRACKS = {"product", "framework", "content"}
GATE_STATUSES = {"PASS", "FAIL", "BLOCKED_ENV", "BLOCKED_HUMAN", "NOT_RUN"}
HUMAN_FIELDS = {"我的备注", "建议调整"}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON object key")
        result[key] = value
    return result


def reject_constant(_value):
    raise ValueError("Non-finite JSON number")


def read_json(path):
    with open(path, encoding="utf-8") as source:
        return json.load(source, object_pairs_hook=unique_object, parse_constant=reject_constant)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def object_value(value, label):
    require(isinstance(value, dict), f"{label} must be an object")
    return value


def text_value(value, label, allow_empty=False):
    require(isinstance(value, str) and (allow_empty or bool(value.strip())), f"{label} must be a string")
    return value


def array_value(value, label):
    require(isinstance(value, list), f"{label} must be an array")
    return value


def strings(value, label):
    for entry in array_value(value, label):
        text_value(entry, label + " item")
    return value


def schema(value, label):
    object_value(value, label)
    require(type(value.get("schema_version")) is int and value["schema_version"] == 1,
            f"{label}.schema_version must be 1")


def validate_cycle(cycle):
    schema(cycle, "cycle")
    text_value(cycle.get("id"), "cycle.id")
    text_value(cycle.get("version"), "cycle.version")
    tasks = array_value(cycle.get("tasks"), "cycle.tasks")
    require(bool(tasks), "cycle.tasks must not be empty")
    seen = set()
    for task in tasks:
        object_value(task, "task")
        task_id = text_value(task.get("id"), "task.id")
        require(task_id not in seen, "Duplicate task ID")
        seen.add(task_id)
        text_value(task.get("title"), "task.title")
        require(text_value(task.get("track"), "task.track") in TRACKS, "Invalid task track")
        status = text_value(task.get("status"), "task.status")
        require(status in TASK_STATUSES, "Invalid task status")
        evidence = strings(task.get("evidence"), "task.evidence")
        blockers = strings(task.get("blockers"), "task.blockers")
        require(status != "done" or (bool(evidence) and not blockers), "Done tasks require evidence and no blockers")
        require(status != "blocked" or bool(blockers), "Blocked tasks require blockers")
    gates = object_value(cycle.get("gates"), "cycle.gates")
    require(set(gates) == {"local", "device", "human", "effect"}, "All four gates are required")
    for gate in gates.values():
        require(text_value(gate, "gate") in GATE_STATUSES, "Invalid gate status")
    notion = object_value(cycle.get("notion"), "cycle.notion")
    text_value(notion.get("expected_workspace_id"), "notion.expected_workspace_id")
    require("observed_workspace_id" in notion, "notion.observed_workspace_id is required")
    if notion["observed_workspace_id"] is not None:
        text_value(notion["observed_workspace_id"], "notion.observed_workspace_id")
    text_value(notion.get("access"), "notion.access")
    require(text_value(notion.get("remote_readback"), "notion.remote_readback") in GATE_STATUSES,
            "Invalid Notion readback status")


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(",", ":"), allow_nan=False).encode("utf-8")).hexdigest()


def cycle_status(cycle):
    validate_cycle(cycle)
    counts = {status: 0 for status in sorted(TASK_STATUSES)}
    for task in cycle["tasks"]:
        counts[task["status"]] += 1
    unfinished = [task for task in cycle["tasks"] if task["status"] != "done"]
    gates = {key: value for key, value in cycle["gates"].items() if value != "PASS"}
    notion = cycle["notion"]
    verified = (notion["access"] == "verified" and notion["remote_readback"] == "PASS"
                and notion["expected_workspace_id"] == notion["observed_workspace_id"])
    return {"schema_version": 1, "read_only": True, "id": cycle["id"], "version": cycle["version"],
            "task_counts": {"total": len(cycle["tasks"]), **counts},
            "track_counts": {track: sum(t["track"] == track for t in cycle["tasks"]) for track in sorted(TRACKS)},
            "unfinished_tasks": unfinished, "unfinished_gates": gates,
            "notion_verified": verified, "overall": "ready" if not unfinished and not gates and verified else "partial",
            "status_hash": digest(cycle)}


def managed(page):
    return {"properties": {key: value for key, value in page["properties"].items() if key not in HUMAN_FIELDS},
            "content": page["content"]}


def validate_preview(blueprint, remote):
    schema(blueprint, "blueprint")
    workspace = text_value(blueprint.get("workspace_id"), "blueprint.workspace_id")
    object_value(remote, "remote")
    require(text_value(remote.get("workspace_id"), "remote.workspace_id") == workspace, "Workspace mismatch")
    require(remote.get("complete") is True, "Incomplete remote inventory")
    local_ids = set()
    for record in array_value(blueprint.get("records"), "blueprint.records"):
        object_value(record, "record")
        stable_id = text_value(record.get("id"), "record.id")
        require(stable_id not in local_ids, "Duplicate local record ID")
        local_ids.add(stable_id)
        text_value(record.get("kind"), "record.kind")
        text_value(record.get("title"), "record.title")
        object_value(record.get("properties"), "record.properties")
        text_value(record.get("content"), "record.content", allow_empty=True)
    remote_ids, page_ids = set(), set()
    for page in array_value(remote.get("pages"), "remote.pages"):
        object_value(page, "remote page")
        stable_id = text_value(page.get("stable_id"), "page.stable_id")
        page_id = text_value(page.get("page_id"), "page.page_id")
        require(stable_id not in remote_ids and page_id not in page_ids, "Duplicate remote stable ID or page ID")
        remote_ids.add(stable_id); page_ids.add(page_id)
        require(page.get("truncated") is False, "Truncated or unknown page completeness")
        require(type(page.get("unknown_block_count")) is int and page["unknown_block_count"] == 0,
                "Unknown blocks or missing block inventory")
        object_value(page.get("properties"), "page.properties")
        text_value(page.get("content"), "page.content", allow_empty=True)
    binding_pages = set()
    for stable_id, binding in object_value(blueprint.get("bindings"), "blueprint.bindings").items():
        text_value(stable_id, "binding ID")
        object_value(binding, "binding")
        page_id = text_value(binding.get("page_id"), "binding.page_id")
        require(page_id not in binding_pages, "Duplicate bound page ID")
        binding_pages.add(page_id)
        fingerprint = text_value(binding.get("managed_hash"), "binding.managed_hash")
        require(len(fingerprint) == 64 and all(c in "0123456789abcdef" for c in fingerprint), "Invalid managed hash")


def synchronization_preview(blueprint, remote):
    validate_preview(blueprint, remote)
    pages = {page["stable_id"]: page for page in remote["pages"]}
    actions = []
    for record in blueprint["records"]:
        stable_id = record["id"]
        content = managed(record)
        local_hash = digest(content)
        page = pages.get(stable_id)
        base = blueprint["bindings"].get(stable_id)
        remote_hash = digest(managed(page)) if page else None
        reason = None
        if base:
            if not page or page["page_id"] != base["page_id"]:
                action, reason = "conflict", "bound_page_missing_or_replaced"
            elif remote_hash != base["managed_hash"]:
                action, reason = "conflict", "remote_changed_since_binding"
            elif local_hash != base["managed_hash"]:
                action, reason = "conflict", "local_changed_since_binding"
            else:
                action = "no_op"
        elif page:
            if remote_hash == local_hash:
                action = "adopt"
            else:
                action, reason = "conflict", "unbound_remote_record_differs"
        else:
            action = "create"
        actions.append({"id": stable_id, "kind": record["kind"], "title": record["title"],
                        "action": action, "reason": reason, "page_id": page["page_id"] if page else None,
                        "managed": content, "managed_hash": local_hash, "remote_hash": remote_hash})
    local_ids = {record["id"] for record in blueprint["records"]}
    for missing in sorted(blueprint["bindings"].keys() - local_ids):
        actions.append({"id": missing, "action": "conflict", "reason": "bound_local_record_missing",
                        "page_id": blueprint["bindings"][missing]["page_id"]})
    return {"schema_version": 1, "read_only": True,
            "can_apply": not any(action["action"] == "conflict" for action in actions),
            "workspace_id": blueprint["workspace_id"], "actions": actions,
            "preserved_human_fields": sorted(HUMAN_FIELDS),
            # Human properties are not managed, even for preview identity. Unknown
            # remote pages participate in inventory integrity but produce no actions.
            "preview_hash": digest({
                "workspace_id": blueprint["workspace_id"], "bindings": blueprint["bindings"],
                "records": [{"id": r["id"], "kind": r["kind"], "title": r["title"], **managed(r)}
                            for r in blueprint["records"]],
                "pages": [{"stable_id": p["stable_id"], "page_id": p["page_id"], **managed(p)}
                          for p in remote["pages"]]})}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    status = commands.add_parser("status")
    status.add_argument("--cycle", required=True)
    preview = commands.add_parser("preview")
    preview.add_argument("--blueprint", required=True)
    preview.add_argument("--remote", required=True)
    args = parser.parse_args()
    try:
        if args.command == "status":
            result = cycle_status(read_json(args.cycle))
        else:
            result = synchronization_preview(read_json(args.blueprint), read_json(args.remote))
        print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
        return 0 if result.get("can_apply", True) else 2
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({"error": str(error), "read_only": True, "can_apply": False}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    sys.exit(main())
