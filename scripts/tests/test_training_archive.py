import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("archive", Path(__file__).parents[1] / "xfit-training-archive.py")
archive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archive)


class TrainingArchiveTests(unittest.TestCase):
    def setUp(self):
        self.record = {"id": "record-1", "version": "v1", "properties": {"档案ID": "record-1", "版本": "v1", "标题": "偏好"}, "content": "## 已确认\n训练规则"}
        self.records = {"workspace_id": "workspace", "data_source_id": "source", "records": [self.record]}
        self.state = {"workspace_id": "workspace", "data_source_id": "source", "bindings": {}}
        self.remote = {"workspace_id": "workspace", "data_source_id": "source", "complete": True, "pages": []}

    def seed(self):
        page = {"record_id": "record-1", "page_id": "page-1", "properties": copy.deepcopy(self.record["properties"]), "content": self.record["content"], "truncated": False, "unknown_block_count": 0}
        self.remote["pages"] = [page]
        self.state = archive.acknowledge(self.records, self.state, self.remote)
        return page

    def test_create_readback_repeat_is_no_op(self):
        self.assertEqual(archive.preview(self.records, self.state, self.remote)["actions"][0]["action"], "create")
        self.seed()
        self.assertEqual(archive.preview(self.records, self.state, self.remote)["actions"][0]["action"], "no_op")

    def test_human_fields_are_preserved_outside_managed_hash(self):
        page = self.seed()
        page["properties"]["我的备注"] = "请考虑我的新反馈"
        page["properties"]["建议调整"] = "暂不加组"
        self.assertEqual(archive.preview(self.records, self.state, self.remote)["actions"][0]["action"], "no_op")
        self.assertEqual(page["properties"]["我的备注"], "请考虑我的新反馈")

    def test_remote_body_conflict_cannot_be_acknowledged(self):
        self.seed()["content"] += "\n人工修改正式规则"
        self.assertFalse(archive.preview(self.records, self.state, self.remote)["can_apply"])
        with self.assertRaises(ValueError):
            archive.acknowledge(self.records, self.state, self.remote)

    def test_changed_management_property_conflicts(self):
        self.seed()["properties"]["版本"] = "v2"
        self.assertFalse(archive.preview(self.records, self.state, self.remote)["can_apply"])

    def test_missing_bound_page_does_not_recreate(self):
        self.seed()
        self.remote["pages"] = []
        self.assertEqual(archive.preview(self.records, self.state, self.remote)["actions"][0]["action"], "conflict")

    def test_duplicate_identity_and_wrong_workspace_stop(self):
        page = self.seed()
        self.remote["pages"].append(copy.deepcopy(page))
        with self.assertRaises(ValueError):
            archive.preview(self.records, self.state, self.remote)
        self.remote["pages"].pop()
        self.remote["workspace_id"] = "wrong"
        with self.assertRaises(ValueError):
            archive.preview(self.records, self.state, self.remote)

    def test_incomplete_inventory_or_page_stops(self):
        self.seed()
        for field, value in (("truncated", True), ("unknown_block_count", 1)):
            modified = copy.deepcopy(self.remote)
            modified["pages"][0][field] = value
            with self.assertRaises(ValueError):
                archive.preview(self.records, self.state, modified)
        self.remote["complete"] = False
        with self.assertRaises(ValueError):
            archive.preview(self.records, self.state, self.remote)

    def test_snapshot_updates_require_append_not_overwrite(self):
        self.seed()
        self.record["content"] += "\n新规则"
        self.record["version"] = "v2"
        self.record["properties"]["版本"] = "v2"
        self.assertEqual(archive.preview(self.records, self.state, self.remote)["actions"][0]["reason"], "append_new_version_with_new_record_id")

    def test_notion_renderer_normalization_preserves_semantics(self):
        self.record["content"] = "\n~/.codex/SKILL.md\n\n"
        page = {"record_id": "record-1", "page_id": "page-1", "properties": self.record["properties"], "content": "\\~/.codex/[SKILL.md](http://SKILL.md)\n", "truncated": False, "unknown_block_count": 0}
        self.remote["pages"] = [page]
        self.assertIn("record-1", archive.acknowledge(self.records, self.state, self.remote)["bindings"])


if __name__ == "__main__":
    unittest.main()
