#!/usr/bin/env python3
"""T3 offline semantic creation preview and simulation. No production transport."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import uuid


ROOT = Path(__file__).resolve().parents[1]
HUMAN_FIELDS = {"我的备注", "建议调整"}
SIMULATED_PARENT_ID = "00000000-0000-4000-8000-000000000001"
DATABASE_IDS = {"cycles": "XFO-DB-CYCLES-1", "work_items": "XFO-DB-WORK-1",
                "decisions_learning": "XFO-DB-LEARNING-1"}
KINDS = {"hub": 1, "cycle": 1, "work_item": 8, "decision": 6, "lesson_candidate": 1}

_spec = importlib.util.spec_from_file_location("xfit_workspace_offline_contract", Path(__file__).with_name("xfit-project-loop.py"))
offline = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(offline)
read_json = offline.read_json
digest = offline.digest


def require(condition, code):
    if not condition:
        raise ValueError(code)


def object_id(value):
    try:
        normalized = str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError):
        raise ValueError("invalid_object_uuid") from None
    require(value == normalized, "noncanonical_object_uuid")
    return normalized


def reference(stable_id, field="id"):
    return {"ref": stable_id, "field": field}


def resolve(value, objects, allow_missing=False):
    if isinstance(value, dict):
        if set(value) == {"ref", "field"}:
            target = objects.get(value["ref"])
            if target is None and allow_missing:
                return copy.deepcopy(value)
            require(target is not None and value["field"] in target, "unresolved_object_reference")
            return object_id(target[value["field"]])
        return {key: resolve(item, objects, allow_missing) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item, objects, allow_missing) for item in value]
    return value


def managed_object(item):
    names = ("kind", "title", "parent", "properties", "content", "schema", "relations", "description")
    result = {name: copy.deepcopy(item[name]) for name in names if name in item}
    if "properties" in result:
        result["properties"] = {key: value for key, value in result["properties"].items() if key not in HUMAN_FIELDS}
    return result


def referenced_ids(value):
    if isinstance(value, dict):
        if set(value) == {"ref", "field"}:
            return {value["ref"]}
        return set().union(*(referenced_ids(item) for item in value.values()))
    if isinstance(value, list):
        return set().union(*(referenced_ids(item) for item in value))
    return set()


def empty_simulation(blueprint):
    return {"schema_version": 1, "mode": "simulation_only", "complete": True,
            "workspace_id": blueprint["workspace_id"], "parent_page_id": SIMULATED_PARENT_ID,
            "private_parent_verified": True, "archive_access_verified": True,
            "existing_archive_database_id": blueprint["existing_archive_database_id"],
            "objects": [], "bindings": {}, "journal": [], "protected_objects": []}


def validate_inputs(blueprint, inventory):
    require(isinstance(blueprint, dict) and isinstance(inventory, dict), "object_inputs_required")
    require(type(blueprint.get("schema_version")) is int and blueprint["schema_version"] == 1, "invalid_blueprint_schema")
    require(blueprint.get("privacy") == "private_only", "private_only_blueprint_required")
    object_id(blueprint.get("workspace_id"))
    archive = object_id(blueprint.get("existing_archive_database_id"))
    records = blueprint.get("records")
    require(isinstance(records, list) and len(records) == 17, "original_17_record_scope_required")
    require(all(isinstance(record, dict) for record in records), "invalid_record")
    require({kind: sum(r.get("kind") == kind for r in records) for kind in KINDS} == KINDS,
            "original_record_kinds_required")
    databases = blueprint.get("databases")
    require(isinstance(databases, list) and len(databases) == 3, "original_three_database_scope_required")
    require(all(isinstance(database, dict) for database in databases), "invalid_database")
    require({d.get("key"): d.get("stable_id") for d in databases} == DATABASE_IDS, "database_scope_mismatch")
    require(type(inventory.get("schema_version")) is int and inventory["schema_version"] == 1
            and inventory.get("mode") == "simulation_only", "simulation_inventory_required")
    require(inventory.get("workspace_id") == blueprint["workspace_id"], "workspace_mismatch")
    require(inventory.get("complete") is True, "incomplete_inventory")
    parent = object_id(inventory.get("parent_page_id"))
    require(parent != archive, "original_archive_cannot_be_parent")
    require(inventory.get("private_parent_verified") is True, "private_parent_unverified")
    require(inventory.get("archive_access_verified") is True, "original_archive_access_unverified")
    require(inventory.get("existing_archive_database_id") == archive, "original_archive_mismatch")
    pages = []
    objects, identifiers = {}, {parent, archive}
    require(isinstance(inventory.get("objects"), list), "invalid_object_inventory")
    for item in inventory["objects"]:
        require(isinstance(item, dict), "invalid_object")
        stable_id = item.get("stable_id")
        require(isinstance(stable_id, str) and stable_id and stable_id not in objects, "duplicate_or_invalid_stable_id")
        item_id = object_id(item.get("id"))
        require(item_id not in identifiers, "duplicate_object_uuid")
        identifiers.add(item_id)
        require(item.get("truncated") is False and type(item.get("unknown_block_count")) is int
                and item["unknown_block_count"] == 0, "unknown_object_completeness")
        require(item.get("archived") is False, "archived_object_requires_review")
        require(isinstance(item.get("properties", {}), dict), "invalid_object_properties")
        if item.get("kind") == "database":
            source = object_id(item.get("data_source_id"))
            require(source not in identifiers, "database_and_data_source_ids_must_be_distinct")
            identifiers.add(source)
            require(isinstance(item.get("schema"), dict), "missing_database_schema")
        else:
            pages.append({"stable_id": stable_id, "page_id": item_id,
                          "properties": item.get("properties", {}), "content": item.get("content", ""),
                          "truncated": False, "unknown_block_count": 0})
        objects[stable_id] = item
    # Retain the existing read-only record/human-field validation contract.
    offline.validate_preview(blueprint, {"workspace_id": inventory["workspace_id"], "complete": True, "pages": pages})
    bindings = inventory.get("bindings")
    require(isinstance(bindings, dict) and isinstance(inventory.get("journal"), list), "invalid_simulation_state")
    for stable_id, binding in bindings.items():
        require(isinstance(binding, dict) and binding.get("id"), "invalid_creation_binding")
        object_id(binding["id"])
        require(isinstance(binding.get("managed_hash"), str) and len(binding["managed_hash"]) == 64,
                "invalid_binding_hash")
    for event in inventory["journal"]:
        require(isinstance(event, dict) and isinstance(event.get("stable_id"), str)
                and event.get("status") in {"pending", "verified"}, "invalid_creation_journal")
    require(isinstance(inventory.get("protected_objects"), list), "missing_protected_inventory")
    return objects


def templates(blueprint, parent_id):
    records = {record["id"]: record for record in blueprint["records"]}
    hub = next(record for record in records.values() if record["kind"] == "hub")
    require(hub["id"] == "XFO-HUB-1" and hub.get("database_key") is None, "hub_scope_mismatch")
    result = {hub["id"]: {"kind": "hub", "title": hub["title"],
        "parent": {"type": "page_id", "page_id": parent_id}, **offline.managed(hub)}}
    databases = {database["key"]: database for database in blueprint["databases"]}
    for key in DATABASE_IDS:
        database = databases[key]
        require(database.get("parent_stable_id") == hub["id"], "database_parent_scope_mismatch")
        require(isinstance(database.get("properties"), dict), "invalid_database_properties")
        schema = {}
        for name, kind in database["properties"].items():
            require(kind in {"TITLE", "RICH_TEXT", "SELECT"}, "unsupported_schema_type")
            schema[name] = {"type": kind.lower()}
        require(sum(s["type"] == "title" for s in schema.values()) == 1, "one_title_property_required")
        for relation in database.get("relations_to_resolve", []):
            target = relation["target_database_key"]
            require(target in DATABASE_IDS and relation["name"] not in schema, "invalid_schema_relation")
            schema[relation["name"]] = {"type": "relation", "data_source_id": reference(DATABASE_IDS[target], "data_source_id")}
        result[database["stable_id"]] = {"kind": "database", "title": database["title"],
            "description": "稳定ID：" + database["stable_id"],
            "parent": {"type": "page_id", "page_id": reference(hub["id"])}, "schema": schema}
    for record in blueprint["records"]:
        if record["id"] == hub["id"]:
            continue
        key = record.get("database_key")
        require(key in DATABASE_IDS, "unknown_record_database")
        database = databases[key]
        properties = offline.managed(record)["properties"]
        require(properties.get("记录ID") == record["id"] and properties.get("名称") == record["title"],
                "record_identity_mismatch")
        require(set(properties) <= set(database["properties"]), "record_schema_mismatch")
        relations = {}
        linked = properties.get("关联稳定ID", "")
        for relation in database.get("relations_to_resolve", []):
            require(linked in records and records[linked].get("database_key") == relation["target_database_key"],
                    "relation_target_missing_or_wrong_database")
            relations[relation["name"]] = [reference(linked)]
        result[record["id"]] = {"kind": record["kind"], "title": record["title"],
            "parent": {"type": "data_source_id", "data_source_id": reference(DATABASE_IDS[key], "data_source_id")},
            "relations": relations, **offline.managed(record)}
    ordered = {}
    while len(ordered) < len(result):
        ready = [stable_id for stable_id, item in result.items()
                 if stable_id not in ordered and referenced_ids(item) <= ordered.keys()]
        require(bool(ready), "cyclic_or_unknown_creation_dependency")
        for stable_id in ready:
            ordered[stable_id] = result[stable_id]
    return ordered


def creation_preview(blueprint, inventory):
    objects = validate_inputs(blueprint, inventory)
    actions = []
    expected = templates(blueprint, inventory["parent_page_id"])
    page_inventory = [{"stable_id": item["stable_id"], "page_id": item["id"],
                       "properties": item.get("properties", {}), "content": item.get("content", ""),
                       "truncated": item["truncated"], "unknown_block_count": item["unknown_block_count"]}
                      for item in inventory["objects"] if item.get("kind") != "database"]
    original_preview = offline.synchronization_preview(blueprint, {
        "workspace_id": inventory["workspace_id"], "complete": True, "pages": page_inventory})
    require(set(blueprint["bindings"]) <= expected.keys(), "original_binding_scope_mismatch")
    original_conflicts = {item["id"]: item["reason"] for item in original_preview["actions"] if item["action"] == "conflict"}
    for stable_id, template in expected.items():
        desired = resolve(template, objects, allow_missing=True)
        current = objects.get(stable_id)
        binding = inventory["bindings"].get(stable_id)
        reason = None
        if stable_id in original_conflicts:
            action, reason = "conflict", original_conflicts[stable_id]
        elif binding and (current is None or current["id"] != binding["id"]
                        or current.get("data_source_id") != binding.get("data_source_id")):
            action, reason = "conflict", "bound_object_missing_or_replaced"
        elif binding and digest(managed_object(current)) != binding["managed_hash"]:
            action, reason = "conflict", "managed_content_changed_since_binding"
        elif current and managed_object(current) != desired:
            action, reason = "conflict", "schema_parent_relation_or_content_mismatch"
        elif current:
            action = "no_op" if binding else "adopt"
        else:
            action = "create"
        actions.append({"stable_id": stable_id, "action": action, "reason": reason,
                        "object_id": current["id"] if current else None, "expected": desired})
    require(set(inventory["bindings"]) <= set(expected), "bound_local_object_missing")
    fingerprint = {"blueprint": {"workspace_id": blueprint["workspace_id"], "templates": expected,
                                  "bindings": blueprint["bindings"]},
                   "inventory": {**inventory, "objects": [{"stable_id": item["stable_id"], "id": item["id"],
                                    "data_source_id": item.get("data_source_id"), **managed_object(item)}
                                   for item in inventory["objects"]]}}
    return {"schema_version": 1, "mode": "simulation_only", "read_only": True, "remote_calls": 0,
            "can_apply_online": False, "can_simulate": all(a["action"] != "conflict" for a in actions),
            "workspace_id": blueprint["workspace_id"], "parent_page_id": inventory["parent_page_id"],
            "actions": actions, "preview_hash": digest(fingerprint),
            "preserved_human_fields": sorted(HUMAN_FIELDS)}


class SimulatedWorkspace:
    """External workspace stand-in. Returned UUIDs are never production bindings."""
    def __init__(self, inventory, checkpoint=None):
        self.document = copy.deepcopy(inventory)
        self.checkpoint = checkpoint

    def snapshot(self):
        return copy.deepcopy(self.document)

    def save(self):
        if self.checkpoint is not None:
            self.checkpoint(self.snapshot())

    def create_object(self, stable_id, expected):
        require(not any(item["stable_id"] == stable_id for item in self.document["objects"]), "duplicate_creation_refused")
        item = {"stable_id": stable_id, "id": str(uuid.uuid4()), **copy.deepcopy(expected),
                "archived": False, "truncated": False, "unknown_block_count": 0}
        if item["kind"] == "database":
            item["data_source_id"] = str(uuid.uuid4())
        self.document["objects"].append(item)
        self.save()
        return {"id": item["id"], "data_source_id": item.get("data_source_id")}

    def begin(self, stable_id, preview_hash):
        self.document["journal"].append({"stable_id": stable_id, "preview_hash": preview_hash, "status": "pending"})
        self.save()

    def bind(self, stable_id, item):
        binding = {"id": item["id"], "managed_hash": digest(managed_object(item))}
        if item.get("data_source_id"):
            binding["data_source_id"] = item["data_source_id"]
        self.document["bindings"][stable_id] = binding
        for event in self.document["journal"]:
            if event["stable_id"] == stable_id and event["status"] != "verified":
                event.update({"status": "verified", "id": item["id"]})
        self.save()


def create_workspace(blueprint, gateway, confirm_preview):
    # There is deliberately no production gateway or credential-enabled override.
    require(isinstance(gateway, SimulatedWorkspace), "simulation_gateway_required")
    before = gateway.snapshot()
    preview = creation_preview(blueprint, before)
    require(preview["can_simulate"], "creation_conflict_requires_review")
    require(confirm_preview == preview["preview_hash"], "stale_preview")
    objects_before = {item["stable_id"]: item for item in before["objects"]}
    unsettled = {event["stable_id"] for event in before["journal"] if event["status"] != "verified"}
    require(unsettled <= objects_before.keys(), "unsettled_creation_requires_review")
    created = []
    expected_templates = templates(blueprint, before["parent_page_id"])
    for action in preview["actions"]:
        stable_id = action["stable_id"]
        snapshot = gateway.snapshot()
        objects = validate_inputs(blueprint, snapshot)
        if action["action"] == "create":
            expected = resolve(expected_templates[stable_id], objects)
            gateway.begin(stable_id, preview["preview_hash"])
            returned = gateway.create_object(stable_id, expected)
            returned_id = object_id(returned.get("id"))
            after = gateway.snapshot()
            readback = validate_inputs(blueprint, after).get(stable_id)
            require(readback is not None and readback["id"] == returned_id, "created_object_readback_missing")
            require(readback.get("data_source_id") == returned.get("data_source_id"), "returned_data_source_mismatch")
            require(managed_object(readback) == expected, "created_object_readback_mismatch")
            gateway.bind(stable_id, readback)
            created.append({"stable_id": stable_id, "id": returned_id, "kind": readback["kind"]})
        elif action["action"] == "adopt" or stable_id in unsettled:
            gateway.bind(stable_id, objects[stable_id])
    after = gateway.snapshot()
    final = creation_preview(blueprint, after)
    require(final["can_simulate"] and all(a["action"] == "no_op" for a in final["actions"]), "final_readback_incomplete")
    require(after["protected_objects"] == before["protected_objects"], "protected_objects_changed")
    originals = {item["stable_id"]: item for item in before["objects"]}
    current = {item["stable_id"]: item for item in after["objects"]}
    require(all(current.get(stable_id) == item for stable_id, item in originals.items()), "existing_object_changed")
    return {"schema_version": 1, "mode": "simulation_only", "status": "PASS", "readback": "PASS",
            "remote_calls": 0, "can_apply_online": False, "created_count": len(created),
            "created_pages": sum(item["kind"] != "database" for item in created),
            "created_databases": sum(item["kind"] == "database" for item in created),
            "created": created, "bindings_are_simulated": True, "bindings": after["bindings"],
            "repeat_preview_hash": final["preview_hash"]}


def write_artifact(path, value):
    """Private, atomic files only within a newly selected local artifact directory."""
    path = Path(path)
    require(not path.is_symlink() and not any(p.is_symlink() for p in path.parents), "symlink_artifact_refused")
    fd, temporary = tempfile.mkstemp(prefix=".workspace-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            if isinstance(value, str):
                output.write(value)
            else:
                json.dump(value, output, ensure_ascii=False, indent=2, allow_nan=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def render_review(preview, result):
    lines = ["# X-Fit 工作台创建预览：仅本地模拟", "",
             "本文件不是线上创建回执。所有页面、数据库和数据源UUID均来自本地模拟，不可登记为真实绑定。", "",
             "范围：一个总览、三个协作库、17条页面记录；旧训练档案只引用，不复制、不迁移。", "",
             "| 对象 | 动作 | 标题 |", "|---|---|---|"]
    for action in preview["actions"]:
        title = action["expected"]["title"].replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {action['stable_id']} | {action['action']} | {title} |")
    lines += ["", "## 本次模拟结果", "",
              f"- 状态：{result['status']}；本地新增：{result.get('created_count', '未知')}；真实Notion调用：0。",
              "- 人工字段“我的备注”“建议调整”不写入、不清空；已有对象仅核对和采纳，不修改。",
              "- 三库下的记录使用返回的数据源ID；工作项、决定和经验关联返回的迭代页面ID。",
              "", "## 下一步真实核验", "",
              "1. 核实固定连接属于Edward工作区，原档案可完整读取；不切换共享认证。",
              "2. 核实确切私有父页和用户给出的线上写入范围；不以模拟私有标记代替ACL。",
              "3. 根据当前项目事实生成新预览；本版没有线上提交入口。",
              "4. 真实小批创建、schema/关联/全文回读和重复新增零通过后，才能关闭原T3。"]
    if result.get("error"):
        lines += ["", "失败代码：" + result["error"], "保留simulation-state.json；不删除未决创建记录、不盲重试。"]
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("preview", "simulate"):
        command = commands.add_parser(name)
        command.add_argument("--blueprint", required=True)
        command.add_argument("--inventory", help="A simulation-only state, never a live Notion snapshot")
        command.add_argument("--out-dir", required=name == "simulate")
        if name == "simulate":
            command.add_argument("--confirm-preview", help="Optional binding to a previously reviewed local preview hash")
    args = parser.parse_args(argv)
    output_dir, preview = None, None
    try:
        blueprint = read_json(args.blueprint)
        inventory = read_json(args.inventory) if args.inventory else empty_simulation(blueprint)
        preview = creation_preview(blueprint, inventory)
        if args.out_dir:
            proposed = Path(args.out_dir).absolute()
            require(not proposed.exists() and not proposed.is_symlink(), "artifact_directory_already_exists")
            require(not any(parent.is_symlink() for parent in proposed.parents), "symlink_artifact_refused")
            proposed.mkdir(parents=True, mode=0o700)
            output_dir = proposed
            write_artifact(output_dir / "preview.json", preview)
        if args.command == "preview":
            report = preview
        else:
            checkpoint = lambda state: write_artifact(output_dir / "simulation-state.json", state)
            gateway = SimulatedWorkspace(inventory, checkpoint=checkpoint)
            gateway.save()
            try:
                result = create_workspace(blueprint, gateway, args.confirm_preview or preview["preview_hash"])
            except (ValueError, KeyError, TypeError):
                gateway.save()
                raise
            report = {key: value for key, value in result.items() if key not in {"created", "bindings"}}
            report["artifact_directory"] = str(output_dir)
        if output_dir:
            write_artifact(output_dir / "result.json", report)
            write_artifact(output_dir / "review.md", render_review(preview, {"status": report.get("status", "PREVIEW"), **report}))
        print(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False))
        return 0 if report.get("can_simulate", True) else 2
    except (ValueError, KeyError, TypeError, OSError) as error:
        report = {"mode": "simulation_only", "status": "FAIL", "remote_calls": 0, "can_apply_online": False,
                  "error": str(error) if isinstance(error, ValueError) else "invalid_local_input_or_artifact"}
        if output_dir:
            write_artifact(output_dir / "result.json", report)
            if preview:
                write_artifact(output_dir / "review.md", render_review(preview, report))
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 2


if __name__ == "__main__":
    sys.exit(main())
