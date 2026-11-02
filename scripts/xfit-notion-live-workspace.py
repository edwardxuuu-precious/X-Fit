#!/usr/bin/env python3
"""Finite T3 creation through the existing, independently authorized X-Fit connection.

prepare is offline. preview is read-only. apply requires an exact private-parent
grant, a fresh preview hash and --allow-write. No PATCH or DELETE is exposed.
"""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


access = module("xfit_live_access", "xfit-notion-access.py")
creator = module("xfit_live_semantics", "xfit-notion-workspace.py")
require, digest = access.require, creator.digest
HUMAN_FIELDS = creator.HUMAN_FIELDS


def rich_text(value):
    """The blueprint uses text and ordinary Markdown links, never mentions."""
    require(isinstance(value, str), "text_required")
    result, start = [], 0
    for match in re.finditer(r"\[([^\]\n]+)\]\((https://[^\s)]+)\)", value):
        for offset in range(start, match.start(), 1900):
            result.append({"type": "text", "text": {"content": value[offset:min(offset + 1900, match.start())]}})
        result.append({"type": "text", "text": {"content": match[1], "link": {"url": match[2]}}})
        start = match.end()
    for offset in range(start, len(value), 1900):
        result.append({"type": "text", "text": {"content": value[offset:offset + 1900]}})
    require(len(result) <= 100, "rich_text_limit")
    return result


def text_value(parts, markdown_links=False):
    require(isinstance(parts, list), "incomplete_rich_text")
    result = []
    for part in parts:
        require(part.get("type", "text") == "text", "unsupported_rich_text")
        raw = part.get("text", {})
        value = raw.get("content", part.get("plain_text"))
        require(isinstance(value, str), "incomplete_rich_text")
        link = raw.get("link")
        if markdown_links and link:
            require(isinstance(link.get("url"), str), "incomplete_link")
            value = "[" + value + "](" + link["url"] + ")"
        result.append(value)
    return "".join(result)


def body_blocks(content):
    require(isinstance(content, str) and len(content) <= 100_000, "invalid_managed_content")
    content = re.sub(r"(?m)^(#{1,3}) (.+)\n(?=\S)", r"\1 \2\n\n", content.strip())
    blocks = []
    for paragraph in re.split(r"\n\s*\n", content):
        heading = re.fullmatch(r"(#{1,3}) (.+)", paragraph)
        kind = "heading_" + str(len(heading[1])) if heading else "paragraph"
        blocks.append({"object": "block", "type": kind,
                       kind: {"rich_text": rich_text(heading[2] if heading else paragraph)}})
    require(len(blocks) <= 100, "managed_block_limit")
    return blocks


def body_content(blocks, allowed_children=None):
    paragraphs = []
    for block in blocks:
        require(not block.get("archived") and not block.get("in_trash"), "managed_block_inactive")
        kind = block.get("type")
        if kind in {"child_database", "child_page"}:
            require(access.normalized_id(block.get("id")) in (allowed_children or set()), "unregistered_child_object")
            continue
        require(kind in {"paragraph", "heading_1", "heading_2", "heading_3"}
                and not block.get("has_children"), "unsupported_managed_block")
        value = text_value(block.get(kind, {}).get("rich_text"), markdown_links=True)
        paragraphs.append(("#" * int(kind[-1]) + " " if kind.startswith("heading_") else "") + value)
    return "\n\n".join(paragraphs).strip()


def expected_objects(blueprint, parent):
    # The original validator is used only for the blueprint's finite semantics;
    # the production inventory is separately obtained from the real API.
    creator.validate_inputs(blueprint, creator.empty_simulation(blueprint))
    result = creator.templates(blueprint, access.normalized_id(parent))
    for item in result.values():
        if "content" in item:
            item["content"] = body_content(body_blocks(item["content"]))
    return result


def validate_grant(grant, config, expected):
    require(grant.get("schema_version") == 1 and grant.get("approved") is True, "exact_parent_grant_required")
    require(access.normalized_id(grant.get("workspace_id")) == access.normalized_id(config["workspace_id"]),
            "grant_workspace_mismatch")
    require(grant.get("private_parent_confirmed") is True and bool(grant.get("confirmation_reference")),
            "private_parent_confirmation_required")
    require(isinstance(grant.get("allowed_stable_ids"), list)
            and len(grant["allowed_stable_ids"]) == len(expected)
            and set(grant["allowed_stable_ids"]) == set(expected), "grant_object_scope_mismatch")
    require(expected["XFO-HUB-1"]["parent"]["page_id"] == access.normalized_id(grant.get("parent_page_id")),
            "grant_parent_mismatch")


def schema_payload(schema):
    result = {}
    for name, item in schema.items():
        kind = item["type"]
        require(kind in {"title", "rich_text", "select", "relation"}, "unsupported_schema_type")
        if kind == "relation":
            result[name] = {"relation": {"data_source_id": access.normalized_id(item["data_source_id"]),
                                          "type": "single_property",
                                          "single_property": {}}}
        else:
            result[name] = {kind: {}}
    return result


def normalize_schema(properties):
    result = {}
    for name, prop in properties.items():
        kind = prop.get("type")
        require(kind in {"title", "rich_text", "select", "relation"}, "unsupported_remote_schema")
        result[name] = {"type": kind}
        if kind == "relation":
            relation = prop.get("relation", {})
            require(relation.get("type") == "single_property", "unexpected_relation_direction")
            result[name]["data_source_id"] = access.normalized_id(relation.get("data_source_id"))
    return result


class LiveWorkspace:
    def __init__(self, blueprint, config, state, grant, api, bindings=None):
        self.blueprint, self.config, self.state, self.grant, self.api = blueprint, config, state, grant, api
        self.parent = access.normalized_id(grant.get("parent_page_id"))
        self.expected = expected_objects(blueprint, self.parent)
        validate_grant(grant, config, self.expected)
        require(access.normalized_id(blueprint["workspace_id"]) == access.normalized_id(config["workspace_id"]),
                "blueprint_workspace_mismatch")
        require(access.normalized_id(blueprint["existing_archive_database_id"]) == access.normalized_id(state["database_id"]),
                "blueprint_archive_mismatch")
        require(self.parent != access.normalized_id(state["database_id"]), "archive_cannot_be_parent")
        self.bindings = copy.deepcopy(bindings or {})
        require(set(self.bindings) <= set(self.expected), "binding_scope_mismatch")

    def identity(self):
        identity = access.DedicatedAccess(self.config, self.state, self.api).doctor()
        parent = self.api.retrieve_page(self.parent)
        require(parent.get("object") == "page" and access.normalized_id(parent.get("id")) == self.parent
                and not parent.get("archived") and not parent.get("in_trash"), "parent_unavailable")
        return identity, parent

    def children(self, parent):
        rows, cursor, cursors = [], None, set()
        for _ in range(10):
            batch = self.api.retrieve_block_children(parent, cursor)
            require(batch.get("object") == "list" and isinstance(batch.get("results"), list)
                    and type(batch.get("has_more")) is bool, "incomplete_block_list")
            rows.extend(batch["results"])
            if not batch["has_more"]:
                require(batch.get("next_cursor") is None, "inconsistent_block_cursor")
                return rows
            cursor = batch.get("next_cursor")
            require(isinstance(cursor, str) and cursor and cursor not in cursors, "block_cursor_loop")
            cursors.add(cursor)
        raise access.AccessError("block_scan_limit")

    def rows(self, source):
        rows, cursor, cursors = [], None, set()
        for _ in range(10):
            batch = self.api.query_data_source(source, cursor)
            require(batch.get("object") == "list" and isinstance(batch.get("results"), list)
                    and type(batch.get("has_more")) is bool, "incomplete_source_query")
            status = batch.get("request_status")
            require(status is None or status.get("type") == "complete", "source_query_pending")
            rows.extend(batch["results"])
            if not batch["has_more"]:
                require(batch.get("next_cursor") is None, "inconsistent_source_cursor")
                return rows
            cursor = batch.get("next_cursor")
            require(isinstance(cursor, str) and cursor and cursor not in cursors, "source_cursor_loop")
            cursors.add(cursor)
        raise access.AccessError("source_scan_limit")

    def read_object(self, stable_id, object_id, allowed_children=None):
        template = self.expected[stable_id]
        identifier = access.normalized_id(object_id)
        if template["kind"] == "database":
            obj = self.api.retrieve_database(identifier)
            require(obj.get("object") == "database" and access.normalized_id(obj.get("id")) == identifier,
                    "database_readback_mismatch")
            sources = obj.get("data_sources", [])
            require(len(sources) == 1, "unexpected_data_source_count")
            source_id = access.normalized_id(sources[0].get("id"))
            require(source_id != identifier, "database_source_identity_collision")
            source = self.api.retrieve_data_source(source_id)
            require(source.get("object") == "data_source" and access.normalized_id(source.get("id")) == source_id
                    and source.get("parent", {}).get("type") == "database_id"
                    and access.normalized_id(source["parent"].get("database_id")) == identifier,
                    "data_source_readback_mismatch")
            require(not source.get("archived") and not source.get("in_trash"), "source_inactive")
            result = {"kind": "database", "title": text_value(obj.get("title")),
                      "description": text_value(obj.get("description")), "schema": normalize_schema(source["properties"]),
                      "data_source_id": source_id}
        else:
            obj = self.api.retrieve_page(identifier)
            require(obj.get("object") == "page" and access.normalized_id(obj.get("id")) == identifier,
                    "page_readback_mismatch")
            properties, relations = copy.deepcopy(obj.get("properties", {})), {}
            for name in list(properties):
                prop = properties[name]
                if prop.get("type") == "relation":
                    require(prop.get("has_more") is False and isinstance(prop.get("relation"), list),
                            "incomplete_relation")
                    relations[name] = [access.normalized_id(item.get("id")) for item in prop["relation"]]
                    del properties[name]
            flattened = access.flatten_properties(properties)
            result = {"kind": template["kind"], "title": flattened.get("title", flattened.get("名称")),
                      "properties": flattened,
                      "content": body_content(self.children(identifier), allowed_children)}
            if template["kind"] != "hub":
                result["relations"] = relations
        require(not obj.get("archived") and not obj.get("in_trash"), "object_inactive")
        parent = obj.get("parent", {})
        kind = parent.get("type")
        require(kind in {"page_id", "data_source_id"}, "unexpected_parent_type")
        result.update({"stable_id": stable_id, "id": identifier,
                       "parent": {"type": kind, kind: access.normalized_id(parent.get(kind))},
                       "archived": False, "truncated": False, "unknown_block_count": 0})
        return result

    def snapshot(self):
        identity, parent = self.identity()
        roots = self.children(self.parent)
        title = self.expected["XFO-HUB-1"]["title"]
        hubs = [b for b in roots if b.get("type") == "child_page" and b.get("child_page", {}).get("title") == title]
        require(len(hubs) <= 1, "duplicate_hub")
        objects = {}
        if hubs:
            hub_id = access.normalized_id(hubs[0]["id"])
            hub_children = self.children(hub_id)
            db_children = [b for b in hub_children if b.get("type") == "child_database"]
            registered_db_ids = set()
            for stable_id, template in self.expected.items():
                if template["kind"] != "database":
                    continue
                candidates = [b for b in db_children if b.get("child_database", {}).get("title") == template["title"]]
                require(len(candidates) <= 1, "duplicate_database")
                if candidates:
                    item = self.read_object(stable_id, candidates[0]["id"])
                    require(item["parent"]["page_id"] == hub_id, "database_parent_mismatch")
                    objects[stable_id] = item
                    registered_db_ids.add(item["id"])
            objects["XFO-HUB-1"] = self.read_object("XFO-HUB-1", hub_id, registered_db_ids)
            for db_id in creator.DATABASE_IDS.values():
                if db_id not in objects:
                    continue
                source = objects[db_id]["data_source_id"]
                for row in self.rows(source):
                    properties = row.get("properties", {})
                    rid = text_value(properties.get("记录ID", {}).get("rich_text", []))
                    if rid not in self.expected:
                        continue
                    require(rid not in objects, "duplicate_record")
                    require(self.expected[rid]["parent"]["data_source_id"] == creator.reference(db_id, "data_source_id"),
                            "record_source_mismatch")
                    objects[rid] = self.read_object(rid, row["id"])
        for rid, binding in self.bindings.items():
            require(rid in objects and objects[rid]["id"] == binding["id"], "bound_object_missing_or_replaced")
        return {"identity": identity, "parent_properties": parent.get("properties"),
                "parent_children": sorted((b["id"], b.get("type")) for b in roots), "objects": objects}

    def preview(self):
        snapshot = self.snapshot()
        actions = []
        for rid, template in self.expected.items():
            desired = creator.resolve(template, snapshot["objects"], allow_missing=True)
            current = snapshot["objects"].get(rid)
            binding = self.bindings.get(rid)
            action = "create" if current is None else "adopt"
            if current:
                actual = creator.managed_object(current)
                if actual != desired or (binding and digest(actual) != binding["managed_hash"]):
                    action = "conflict"
                elif binding:
                    action = "no_op"
            actions.append({"stable_id": rid, "action": action, "expected": desired,
                            "object_id": current["id"] if current else None})
        fingerprint = {"grant": self.grant, "expected": self.expected, "snapshot": snapshot, "bindings": self.bindings}
        return {"mode": "dedicated_live", "read_only": True, "actions": actions,
                "can_apply": all(item["action"] != "conflict" for item in actions),
                "parent_page_id": self.parent, "preview_hash": digest(fingerprint), "snapshot": snapshot}

    def create(self, rid, expected):
        if expected["kind"] == "database":
            payload = {"parent": expected["parent"], "title": rich_text(expected["title"]),
                       "description": rich_text(expected["description"]),
                       "initial_data_source": {"properties": schema_payload(expected["schema"])}}
            return self.api.create_database(payload)
        schema = {name: {"type": "title" if name in {"title", "名称"} else
                         ("select" if name in {"类型", "状态"} else "rich_text")}
                  for name in expected["properties"]}
        properties = access.encode_properties(expected["properties"], schema)
        properties.update({name: {"relation": [{"id": identifier} for identifier in ids]}
                           for name, ids in expected.get("relations", {}).items()})
        return self.api.create_page({"parent": expected["parent"], "properties": properties,
                                     "children": body_blocks(expected["content"])})

    def apply(self, preview_hash, journal, save_bindings, allow_write=False):
        require(allow_write is True, "explicit_write_switch_required")
        before = self.preview()
        require(before["can_apply"], "creation_conflict_requires_review")
        require(before["preview_hash"] == preview_hash, "stale_preview")
        objects = before["snapshot"]["objects"]
        created = []
        for action in before["actions"]:
            rid = action["stable_id"]
            expected = creator.resolve(self.expected[rid], objects)
            pending = journal.unsettled(rid)
            if rid not in objects:
                require(pending is None, "unsettled_write_requires_review")
                # Recheck the one target scope immediately before its create.
                parent = expected["parent"]
                if parent["type"] == "page_id":
                    children = self.children(parent["page_id"])
                    child_kind = "child_database" if expected["kind"] == "database" else "child_page"
                    require(not any(b.get("type") == child_kind and b.get(child_kind, {}).get("title") == expected["title"]
                                    for b in children), "target_appeared_after_preview")
                else:
                    require(not any(text_value(row.get("properties", {}).get("记录ID", {}).get("rich_text", [])) == rid
                                    for row in self.rows(parent["data_source_id"])), "target_appeared_after_preview")
                journal.begin(rid, preview_hash)
                returned = self.create(rid, expected)
                identifier = access.normalized_id(returned.get("id"))
                journal.received(rid, identifier)
                objects[rid] = self.read_object(rid, identifier)
                require(creator.managed_object(objects[rid]) == expected, "created_object_readback_mismatch")
                created.append(rid)
            else:
                if pending and pending.get("page_id"):
                    require(pending["page_id"] == objects[rid]["id"], "unsettled_object_identity_mismatch")
                require(creator.managed_object(objects[rid]) == expected, "existing_content_conflict")
            self.bindings[rid] = {"id": objects[rid]["id"], "managed_hash": digest(creator.managed_object(objects[rid]))}
            if objects[rid].get("data_source_id"):
                self.bindings[rid]["data_source_id"] = objects[rid]["data_source_id"]
            save_bindings(self.bindings)
            journal.verified(rid, objects[rid]["id"])
        final = self.preview()
        require(final["can_apply"] and all(a["action"] == "no_op" for a in final["actions"]), "final_readback_incomplete")
        require(before["snapshot"]["parent_properties"] == final["snapshot"]["parent_properties"], "parent_properties_changed")
        old_children = set(before["snapshot"]["parent_children"])
        require(old_children <= set(final["snapshot"]["parent_children"]), "original_child_missing")
        return {"status": "PASS", "readback": "PASS", "created_count": len(created), "created": created,
                "verified_pages": 17, "verified_databases": 3, "bindings": self.bindings,
                "repeat_preview_hash": final["preview_hash"], "private_acl_evidence": "user_parent_confirmation"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "preview", "apply"])
    parser.add_argument("--config", type=Path, default=access.DEFAULT_CONFIG)
    parser.add_argument("--blueprint", type=Path, default=ROOT / "docs/operations/notion-blueprint.json")
    parser.add_argument("--grant", type=Path)
    parser.add_argument("--parent-page-id")
    parser.add_argument("--confirm-preview")
    parser.add_argument("--allow-write", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    api = None
    try:
        config, blueprint = access.read_json(args.config), access.read_json(args.blueprint)
        output = access.artifact_output(args.output)
        if args.command == "prepare":
            expected = expected_objects(blueprint, args.parent_page_id)
            require(access.normalized_id(blueprint["workspace_id"]) == access.normalized_id(config["workspace_id"]),
                    "blueprint_workspace_mismatch")
            document = {"status": "PROPOSAL", "remote_calls": 0, "content_writes": 0,
                        "parent_page_id": args.parent_page_id, "workspace_id": blueprint["workspace_id"],
                        "objects": expected, "allowed_stable_ids": list(expected),
                        "requires": ["exact_private_parent_grant", "dedicated_keychain_credential", "fresh_live_preview"]}
        else:
            require(args.grant is not None, "exact_parent_grant_required")
            grant = access.read_json(args.grant)
            expected = expected_objects(blueprint, grant.get("parent_page_id"))
            validate_grant(grant, config, expected)
            state = access.read_json(access.project_path(config["archive_state"]))
            token = access.KeychainCredential(config["keychain_service"], config["keychain_account"]).get()
            api = access.NotionAPI(token)
            with access.channel_lock(config["workspace_id"]) as runtime:
                binding_path = runtime / "workspace-bindings.json"
                bindings = access.read_json(binding_path) if binding_path.exists() else {}
                client = LiveWorkspace(blueprint, config, state, grant, api, bindings)
                if args.command == "preview":
                    document = client.preview()
                else:
                    require(args.confirm_preview, "exact_preview_hash_required")
                    journal = access.WriteJournal(runtime / "workspace-journal.json")
                    document = client.apply(args.confirm_preview, journal,
                                            lambda value: access.secure_json(binding_path, value), args.allow_write)
                document["remote_calls"] = api.remote_calls
        access.secure_json(output, document)
        report = {key: value for key, value in document.items() if key not in {"objects", "snapshot", "bindings", "actions"}}
        report["output"] = str(output)
        if "actions" in document:
            report["action_counts"] = {kind: sum(item["action"] == kind for item in document["actions"])
                                       for kind in {"create", "adopt", "no_op", "conflict"}}
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0 if document.get("can_apply", True) else 2
    except (access.AccessError, ValueError, OSError, KeyError, TypeError) as exc:
        code = exc.code if isinstance(exc, access.AccessError) else "local_or_semantic_input_invalid"
        print(json.dumps({"status": "BLOCKED_ENV", "error": code,
                          "remote_calls": api.remote_calls if api else 0,
                          "content_writes": "unknown" if code.startswith("write_") else "not_claimed"}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
