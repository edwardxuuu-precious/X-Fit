"""Actual T3 orchestration with a fake HTTP boundary; no credentials or remote writes."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("xfit_live_workspace_tests", ROOT / "scripts/xfit-notion-live-workspace.py")
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)


class FakeAPI:
    def __init__(self, blueprint):
        self.workspace = blueprint["workspace_id"]
        self.archive = blueprint["existing_archive_database_id"]
        self.archive_source = str(uuid.uuid4())
        self.parent = str(uuid.uuid4())
        self.pages = {self.parent: {"object": "page", "id": self.parent, "archived": False,
                                   "in_trash": False, "properties": {"title": {"type": "title", "title": live.rich_text("原私有页")}}}}
        self.databases, self.sources, self.blocks, self.source_rows = {}, {}, {self.parent: []}, {}
        self.calls = []
        self.lose_response = False

    def me(self):
        self.calls.append("me")
        return {"object": "user", "type": "bot", "bot": {"workspace_id": self.workspace,
                "workspace_name": "Edward's Notion"}}

    def retrieve_database(self, identifier):
        self.calls.append("read_database")
        if identifier == self.archive:
            return {"object": "database", "id": identifier, "archived": False,
                    "data_sources": [{"id": self.archive_source}]}
        return copy.deepcopy(self.databases[identifier])

    def retrieve_data_source(self, identifier):
        self.calls.append("read_source")
        if identifier == self.archive_source:
            return {"object": "data_source", "id": identifier, "archived": False,
                    "parent": {"type": "database_id", "database_id": self.archive},
                    "properties": {"档案ID": {"type": "rich_text"}}}
        return copy.deepcopy(self.sources[identifier])

    def retrieve_page(self, identifier):
        self.calls.append("read_page")
        return copy.deepcopy(self.pages[identifier])

    @staticmethod
    def batch(rows, cursor):
        start = int(cursor or 0)
        more = start + 2 < len(rows)
        return {"object": "list", "results": copy.deepcopy(rows[start:start + 2]), "has_more": more,
                "next_cursor": str(start + 2) if more else None}

    def retrieve_block_children(self, identifier, cursor=None):
        self.calls.append("read_blocks")
        return self.batch(self.blocks.get(identifier, []), cursor)

    def query_data_source(self, identifier, cursor=None):
        self.calls.append("read_rows")
        return self.batch([self.pages[pid] for pid in self.source_rows[identifier]], cursor)

    def create_database(self, payload):
        self.calls.append("create_database")
        identifier, source = str(uuid.uuid4()), str(uuid.uuid4())
        schema = {}
        for name, value in payload["initial_data_source"]["properties"].items():
            kind = next(iter(value))
            schema[name] = {"type": kind, **copy.deepcopy(value)}
            if kind == "relation":
                schema[name]["relation"]["type"] = "single_property"
        self.databases[identifier] = {"object": "database", "id": identifier, "archived": False,
             "in_trash": False, "title": payload["title"], "description": payload["description"],
             "parent": payload["parent"], "data_sources": [{"id": source}]}
        self.sources[source] = {"object": "data_source", "id": source, "archived": False,
            "in_trash": False, "parent": {"type": "database_id", "database_id": identifier}, "properties": schema}
        self.source_rows[source] = []
        self.blocks[payload["parent"]["page_id"]].append({"id": identifier, "type": "child_database",
            "child_database": {"title": live.text_value(payload["title"])}})
        return copy.deepcopy(self.databases[identifier])

    def create_page(self, payload):
        self.calls.append("create_page")
        identifier = str(uuid.uuid4())
        properties = {}
        if payload["parent"]["type"] == "data_source_id":
            source = payload["parent"]["data_source_id"]
            self.source_rows[source].append(identifier)
            for name, prop in self.sources[source]["properties"].items():
                kind = prop["type"]
                properties[name] = {"type": kind, kind: [] if kind in {"title", "rich_text", "relation"} else None}
                if kind == "relation":
                    properties[name]["has_more"] = False
        else:
            title = live.text_value(payload["properties"]["title"]["title"])
            self.blocks[payload["parent"]["page_id"]].append({"id": identifier, "type": "child_page",
                                                              "child_page": {"title": title}})
        for name, value in payload["properties"].items():
            kind = next(iter(value))
            properties[name] = {"type": kind, **copy.deepcopy(value)}
            if kind == "relation":
                properties[name]["has_more"] = False
        page = {"object": "page", "id": identifier, "parent": payload["parent"],
                "archived": False, "in_trash": False, "properties": properties}
        self.pages[identifier] = page
        self.blocks[identifier] = [{"id": str(uuid.uuid4()), "archived": False, "in_trash": False,
                                  "has_children": False, **copy.deepcopy(block)} for block in payload["children"]]
        if self.lose_response:
            self.lose_response = False
            raise live.access.AccessError("write_outcome_unknown")
        return copy.deepcopy(page)


class LiveWorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.blueprint = live.access.read_json(ROOT / "docs/operations/notion-blueprint.json")
        self.api = FakeAPI(self.blueprint)
        self.config = {"schema_version": 1, "api_version": "2026-03-11",
                       "workspace_id": self.api.workspace, "workspace_name": "Edward's Notion"}
        self.state = {"workspace_id": self.api.workspace, "database_id": self.api.archive,
                      "data_source_id": self.api.archive_source}
        self.grant = {"schema_version": 1, "approved": True, "workspace_id": self.api.workspace,
            "parent_page_id": self.api.parent, "private_parent_confirmed": True,
            "confirmation_reference": "isolated-test-only",
            "allowed_stable_ids": list(live.expected_objects(self.blueprint, self.api.parent))}
        self.client = live.LiveWorkspace(self.blueprint, self.config, self.state, self.grant, self.api)
        self.directory = tempfile.TemporaryDirectory(prefix="xfit-live-creator-")
        self.addCleanup(self.directory.cleanup)
        self.journal = live.access.WriteJournal(Path(self.directory.name) / "journal.json")

    def apply(self):
        return self.client.apply(self.client.preview()["preview_hash"], self.journal,
                                 lambda value: live.access.secure_json(Path(self.directory.name) / "bindings.json", value), True)

    def test_creates_original_twenty_objects_with_real_parent_and_source_relations_and_repeats_zero(self):
        result = self.apply()
        self.assertEqual((result["created_count"], result["verified_pages"], result["verified_databases"]), (20, 17, 3))
        self.assertEqual(self.api.calls.count("create_database"), 3)
        self.assertEqual(self.api.calls.count("create_page"), 17)
        objects = self.client.snapshot()["objects"]
        cycles = objects["XFO-DB-CYCLES-1"]
        self.assertNotEqual(cycles["id"], cycles["data_source_id"])
        self.assertEqual(objects["XFO-T1"]["relations"], {"所属迭代": [objects["XFO-CYCLE-20260927-01"]["id"]]})
        self.assertEqual(self.apply()["created_count"], 0)
        self.assertNotIn(self.api.archive, result["bindings"])
        self.assertTrue(all(event["status"] == "verified" for event in self.journal.document["attempts"]))

    def test_missing_write_switch_never_mutates(self):
        preview = self.client.preview()
        with self.assertRaisesRegex(live.access.AccessError, "explicit_write_switch"):
            self.client.apply(preview["preview_hash"], self.journal, lambda _: None)
        self.assertNotIn("create_page", self.api.calls)

    def test_missing_private_confirmation_and_expanded_scope_fail_before_access(self):
        for field, value in [("private_parent_confirmed", False), ("approved", False),
                             ("allowed_stable_ids", self.grant["allowed_stable_ids"] + ["unrelated"] )]:
            grant = {**self.grant, field: value}
            with self.subTest(field=field), self.assertRaises(live.access.AccessError):
                live.LiveWorkspace(self.blueprint, self.config, self.state, grant, self.api)
        self.assertEqual(self.api.calls, [])

    def test_wrong_workspace_stops_before_archive_read(self):
        self.api.workspace = str(uuid.uuid4())
        with self.assertRaisesRegex(live.access.AccessError, "workspace_mismatch"):
            self.client.preview()
        self.assertEqual(self.api.calls, ["me"])

    def test_blueprint_of_another_archive_is_rejected_before_access(self):
        blueprint = copy.deepcopy(self.blueprint)
        blueprint["existing_archive_database_id"] = str(uuid.uuid4())
        with self.assertRaisesRegex(live.access.AccessError, "blueprint_archive_mismatch"):
            live.LiveWorkspace(blueprint, self.config, self.state, self.grant, self.api)
        self.assertEqual(self.api.calls, [])

    def test_stale_preview_stops_before_creation(self):
        preview = self.client.preview()
        self.api.pages[self.api.parent]["properties"]["title"]["title"] = live.rich_text("本人修改了父页")
        with self.assertRaisesRegex(live.access.AccessError, "stale_preview"):
            self.client.apply(preview["preview_hash"], self.journal, lambda _: None, True)
        self.assertNotIn("create_page", self.api.calls)

    def test_lost_response_recovers_same_created_hub_without_duplicate(self):
        self.api.lose_response = True
        with self.assertRaisesRegex(live.access.AccessError, "write_outcome_unknown"):
            self.apply()
        self.assertEqual(self.api.calls.count("create_page"), 1)
        result = self.apply()
        self.assertEqual(result["created_count"], 19)
        self.assertEqual(self.api.calls.count("create_page"), 17)
        self.assertIsNone(self.journal.unsettled("XFO-HUB-1"))

    def test_unknown_write_without_visible_object_is_not_retried(self):
        self.journal.begin("XFO-HUB-1", "a" * 64)
        with self.assertRaisesRegex(live.access.AccessError, "unsettled_write_requires_review"):
            self.apply()
        self.assertNotIn("create_page", self.api.calls)

    def test_human_notes_survive_repeat_but_managed_content_drift_blocks(self):
        self.apply()
        objects = self.client.snapshot()["objects"]
        pid = objects["XFO-T1"]["id"]
        self.api.pages[pid]["properties"]["我的备注"]["rich_text"] = live.rich_text("本人反馈")
        self.assertEqual(self.apply()["created_count"], 0)
        self.assertEqual(live.text_value(self.api.pages[pid]["properties"]["我的备注"]["rich_text"]), "本人反馈")
        self.api.blocks[pid][0]["paragraph"]["rich_text"] = live.rich_text("人工改了管理正文")
        self.assertFalse(self.client.preview()["can_apply"])
        with self.assertRaisesRegex(live.access.AccessError, "creation_conflict_requires_review"):
            self.apply()

    def test_duplicate_and_unregistered_children_block(self):
        self.apply()
        hub = self.client.snapshot()["objects"]["XFO-HUB-1"]["id"]
        self.api.blocks[hub].append({"id": str(uuid.uuid4()), "type": "child_page", "child_page": {"title": "未知子页"}})
        with self.assertRaisesRegex(live.access.AccessError, "unregistered_child_object"):
            self.client.preview()

    def test_missing_bound_object_and_incomplete_relation_are_not_success(self):
        self.apply()
        objects = self.client.snapshot()["objects"]
        pid = objects["XFO-T1"]["id"]
        self.api.pages[pid]["properties"]["所属迭代"]["has_more"] = True
        with self.assertRaisesRegex(live.access.AccessError, "incomplete_relation"):
            self.client.preview()

    def test_schema_target_change_is_conflict(self):
        self.apply()
        objects = self.client.snapshot()["objects"]
        source = objects["XFO-DB-WORK-1"]["data_source_id"]
        self.api.sources[source]["properties"]["所属迭代"]["relation"]["data_source_id"] = str(uuid.uuid4())
        self.assertFalse(self.client.preview()["can_apply"])


if __name__ == "__main__":
    unittest.main()
