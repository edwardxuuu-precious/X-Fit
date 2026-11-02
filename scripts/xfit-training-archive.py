#!/usr/bin/env python3
"""Offline, fail-closed Notion mirror planning. Never performs network or device writes."""
import argparse
import hashlib
import json
import re
import sys

HUMAN_FIELDS = {"我的备注", "建议调整"}
IDENTITY_FIELDS = {"url", "createdTime", "last_edited_time"}


def normalize_text(value):
    # Notion may auto-link bare local filenames; this is a rendering change only.
    text = str(value).replace("\r\n", "\n")
    text = re.sub(r"\[([^\]\n]+)\]\(http://([^\)\n]+)\)",
                  lambda m: m[1] if m[1] == m[2] else m[0], text)
    text = text.replace("\\~", "~")
    return "\n".join(line.rstrip() for line in text.strip().splitlines() if line.strip())


def normalized_properties(properties):
    return {key: normalize_text(value) if isinstance(value, str) else value
            for key, value in properties.items()
            if key not in HUMAN_FIELDS | IDENTITY_FIELDS and value not in (None, "")
            and not (key.endswith(":is_datetime") and value == 0)}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(",", ":")).encode()).hexdigest()


def fingerprint(page):
    return digest({"properties": normalized_properties(page["properties"]),
                   "content": normalize_text(page["content"])})


def validate_inputs(records, remote):
    for key in ("workspace_id", "data_source_id"):
        if not records.get(key) or remote.get(key) != records[key]:
            raise ValueError(f"{key} mismatch")
    if remote.get("complete") is not True:
        raise ValueError("Incomplete remote inventory")
    local = {record["id"]: record for record in records["records"]}
    if len(local) != len(records["records"]):
        raise ValueError("Duplicate local record ID")
    indexed = {}
    page_ids = set()
    for page in remote["pages"]:
        if page.get("truncated") is not False or page.get("unknown_block_count") != 0:
            raise ValueError("Incomplete page content")
        rid, pid = page.get("record_id"), page.get("page_id")
        if not rid or not pid or rid in indexed or pid in page_ids:
            raise ValueError("Missing or duplicate remote identity")
        if page["properties"].get("档案ID") != rid:
            raise ValueError("Remote record property mismatch")
        indexed[rid] = page
        page_ids.add(pid)
    for rid, record in local.items():
        if record["properties"].get("档案ID") != rid or record["properties"].get("版本") != record["version"]:
            raise ValueError("Local record identity/version mismatch")
    return local, indexed


def preview(records, state, remote):
    local, indexed = validate_inputs(records, remote)
    for key in ("workspace_id", "data_source_id"):
        if state.get(key) != records[key]:
            raise ValueError(f"State {key} mismatch")
    actions = []
    bindings = state.get("bindings", {})
    for rid, record in local.items():
        page, base = indexed.get(rid), bindings.get(rid)
        reason = None
        if base:
            if not page or page["page_id"] != base["page_id"]:
                action, reason = "conflict", "bound_page_missing_or_replaced"
            elif fingerprint(page) != base["remote_hash"]:
                action, reason = "conflict", "remote_changed_since_readback"
            elif fingerprint(record) == base["local_hash"]:
                action = "no_op"
            elif record["version"] == base["version"]:
                action, reason = "conflict", "local_change_requires_new_version"
            else:
                # Confirmed snapshots are append-only: new versions must get a new stable ID.
                action, reason = "conflict", "append_new_version_with_new_record_id"
        elif page:
            if fingerprint(page) == fingerprint(record):
                action = "adopt_existing"
            else:
                action, reason = "conflict", "unbound_remote_record_differs"
        else:
            action = "create"
        actions.append({"record_id": rid, "action": action, "reason": reason,
                        "page_id": page["page_id"] if page else None})
    for rid in bindings.keys() - local.keys():
        actions.append({"record_id": rid, "action": "conflict", "reason": "bound_local_record_missing"})
    return {"can_apply": not any(a["action"] == "conflict" for a in actions),
            "actions": actions,
            "preview_hash": digest({"records": records, "state": state,
                                    "remote": [{"id": p["page_id"], "hash": fingerprint(p)}
                                               for p in remote["pages"]]})}


def acknowledge(records, state, remote):
    """Only enroll verified new/unchanged pages. Never bless changed remote baselines."""
    result = preview(records, state, remote)
    if not result["can_apply"]:
        raise ValueError("Conflict: refusing to replace synchronization baseline")
    local, indexed = validate_inputs(records, remote)
    bindings = dict(state.get("bindings", {}))
    for rid, record in local.items():
        page = indexed.get(rid)
        if not page or fingerprint(page) != fingerprint(record):
            raise ValueError(f"Readback differs from expected content: {rid}")
        bindings[rid] = {"page_id": page["page_id"], "version": record["version"],
                         "local_hash": fingerprint(record), "remote_hash": fingerprint(page)}
    return {**state, "schema_version": 1, "bindings": bindings}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["preview", "acknowledge"])
    parser.add_argument("--records", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--remote", required=True)
    args = parser.parse_args()
    try:
        documents = [json.load(open(path, encoding="utf-8"))
                     for path in (args.records, args.state, args.remote)]
        result = (preview if args.command == "preview" else acknowledge)(*documents)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result.get("can_apply", True) else 2
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"error": str(exc), "can_apply": False}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    sys.exit(main())
