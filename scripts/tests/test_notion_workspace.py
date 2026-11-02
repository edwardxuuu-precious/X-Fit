"""Public local-workspace creation contracts; no Notion, credentials or App stores."""
import importlib.util
import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("notion_workspace_local", ROOT / "scripts/xfit-notion-workspace.py")
creator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(creator)


class WorkspaceCreationTests(unittest.TestCase):
    def setUp(self):
        self.blueprint = creator.read_json(ROOT / "docs/operations/notion-blueprint.json")

    def completed_simulation(self):
        gateway = creator.SimulatedWorkspace(creator.empty_simulation(self.blueprint))
        preview = creator.creation_preview(self.blueprint, gateway.snapshot())
        creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        return gateway.snapshot()

    def test_original_blueprint_has_a_complete_dependency_ordered_preview(self):
        blueprint = creator.read_json(ROOT / "docs/operations/notion-blueprint.json")
        inventory = creator.empty_simulation(blueprint)
        result = creator.creation_preview(blueprint, inventory)
        self.assertTrue(result["can_simulate"])
        self.assertFalse(result["can_apply_online"])
        self.assertEqual(result["mode"], "simulation_only")
        self.assertEqual(len(result["actions"]), 20)
        ids = [action["stable_id"] for action in result["actions"]]
        self.assertEqual(ids[:4], ["XFO-HUB-1", "XFO-DB-CYCLES-1", "XFO-DB-WORK-1", "XFO-DB-LEARNING-1"])
        self.assertLess(ids.index("XFO-CYCLE-20260927-01"), ids.index("XFO-T1"))
        self.assertTrue(all(action["action"] == "create" for action in result["actions"]))
        work_db = next(action for action in result["actions"] if action["stable_id"] == "XFO-DB-WORK-1")
        self.assertEqual(work_db["expected"]["schema"]["所属迭代"],
                         {"type": "relation", "data_source_id": {"ref": "XFO-DB-CYCLES-1", "field": "data_source_id"}})

    def test_create_reads_back_database_sources_and_page_relations_then_repeat_adds_zero(self):
        gateway = creator.SimulatedWorkspace(creator.empty_simulation(self.blueprint))
        preview = creator.creation_preview(self.blueprint, gateway.snapshot())
        result = creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        self.assertEqual(result["created_count"], 20)
        self.assertEqual(result["created_pages"], 17)
        self.assertEqual(result["created_databases"], 3)
        self.assertEqual(result["readback"], "PASS")
        state = gateway.snapshot()
        objects = {item["stable_id"]: item for item in state["objects"]}
        hub = objects["XFO-HUB-1"]
        cycles = objects["XFO-DB-CYCLES-1"]
        work = objects["XFO-DB-WORK-1"]
        self.assertNotEqual(cycles["id"], cycles["data_source_id"])
        self.assertEqual(work["parent"], {"type": "page_id", "page_id": hub["id"]})
        self.assertEqual(work["schema"]["所属迭代"]["data_source_id"], cycles["data_source_id"])
        self.assertEqual(objects["XFO-T1"]["parent"], {"type": "data_source_id", "data_source_id": work["data_source_id"]})
        self.assertEqual(objects["XFO-T1"]["relations"], {"所属迭代": [objects["XFO-CYCLE-20260927-01"]["id"]]})
        self.assertEqual(objects["XFO-D01"]["relations"], {"所属迭代": [objects["XFO-CYCLE-20260927-01"]["id"]]})
        self.assertNotIn("我的备注", objects["XFO-T1"]["properties"])
        self.assertNotIn("建议调整", objects["XFO-T1"]["properties"])
        before = copy.deepcopy(state)
        again = creator.creation_preview(self.blueprint, state)
        repeated = creator.create_workspace(self.blueprint, gateway, again["preview_hash"])
        self.assertEqual(repeated["created_count"], 0)
        self.assertEqual(gateway.snapshot(), before)
        self.assertFalse(repeated["can_apply_online"])

    def test_unknown_create_outcome_is_not_blindly_retried_after_reload(self):
        class UncertainGateway(creator.SimulatedWorkspace):
            def create_object(self, stable_id, expected):
                raise ValueError("simulated_response_lost_without_acceptance")

        gateway = UncertainGateway(creator.empty_simulation(self.blueprint))
        preview = creator.creation_preview(self.blueprint, gateway.snapshot())
        with self.assertRaisesRegex(ValueError, "simulated_response_lost"):
            creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        reloaded = creator.SimulatedWorkspace(gateway.snapshot())
        fresh = creator.creation_preview(self.blueprint, reloaded.snapshot())
        with self.assertRaisesRegex(ValueError, "unsettled_creation_requires_review"):
            creator.create_workspace(self.blueprint, reloaded, fresh["preview_hash"])
        self.assertEqual(reloaded.snapshot()["objects"], [])
        self.assertEqual(len(reloaded.snapshot()["journal"]), 1)

    def test_blueprint_record_order_does_not_change_creation_dependencies(self):
        self.blueprint["records"].reverse()
        gateway = creator.SimulatedWorkspace(creator.empty_simulation(self.blueprint))
        preview = creator.creation_preview(self.blueprint, gateway.snapshot())
        result = creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        self.assertEqual(result["created_count"], 20)
        ids = [action["stable_id"] for action in preview["actions"]]
        self.assertLess(ids.index("XFO-CYCLE-20260927-01"), ids.index("XFO-L01"))

    def test_boolean_schema_version_is_not_an_inventory_version(self):
        inventory = creator.empty_simulation(self.blueprint)
        inventory["schema_version"] = True
        with self.assertRaisesRegex(ValueError, "simulation_inventory_required"):
            creator.creation_preview(self.blueprint, inventory)

    def test_cli_creates_reviewable_local_artifacts_and_reuses_state_without_duplicates(self):
        source = ROOT / "docs/operations/notion-blueprint.json"
        before = source.read_bytes()
        with tempfile.TemporaryDirectory(prefix="xfit-workspace-contract-") as directory:
            # macOS exposes /var as a system symlink; use the actual temporary
            # directory, retaining the creator's no-symlink artifact boundary.
            directory = str(Path(directory).resolve())
            first_dir = Path(directory) / "first"
            command = [sys.executable, str(ROOT / "scripts/xfit-notion-workspace.py"), "simulate",
                       "--blueprint", str(source), "--out-dir", str(first_dir)]
            first = subprocess.run(command, capture_output=True, text=True, timeout=10)
            self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
            result = json.loads(first.stdout)
            self.assertEqual(result["created_count"], 20)
            self.assertEqual(result["remote_calls"], 0)
            self.assertFalse(result["can_apply_online"])
            self.assertEqual({p.name for p in first_dir.iterdir()},
                             {"preview.json", "simulation-state.json", "result.json", "review.md"})
            self.assertIn("仅本地模拟", (first_dir / "review.md").read_text())
            repeat = subprocess.run(command[:-1] + [str(Path(directory) / "repeat"), "--inventory",
                                    str(first_dir / "simulation-state.json")], capture_output=True, text=True, timeout=10)
            self.assertEqual(repeat.returncode, 0, repeat.stderr)
            self.assertEqual(json.loads(repeat.stdout)["created_count"], 0)
        self.assertEqual(source.read_bytes(), before)

    def test_human_edits_preserve_preview_and_unrelated_or_old_objects(self):
        inventory = self.completed_simulation()
        before = creator.creation_preview(self.blueprint, inventory)
        record = next(item for item in inventory["objects"] if item["stable_id"] == "XFO-T1")
        record["properties"].update({"我的备注": "本人保留，不能清空", "建议调整": "先查实际强度"})
        after = creator.creation_preview(self.blueprint, inventory)
        self.assertEqual(before["preview_hash"], after["preview_hash"])
        unrelated = {"stable_id": "human-owned-unrelated", "id": "88888888-8888-4888-8888-888888888888",
                     "kind": "unrelated", "title": "不管理此页", "content": "人工内容不复制",
                     "properties": {"我的备注": "保留"}, "archived": False, "truncated": False, "unknown_block_count": 0}
        inventory["objects"].append(unrelated)
        inventory["protected_objects"] = [{"id": self.blueprint["existing_archive_database_id"], "unchanged_marker": "old-archive"}]
        original = copy.deepcopy(inventory)
        gateway = creator.SimulatedWorkspace(inventory)
        preview = creator.creation_preview(self.blueprint, inventory)
        result = creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        self.assertEqual(result["created_count"], 0)
        self.assertEqual(gateway.snapshot(), original)

    def test_exact_existing_structure_can_be_adopted_without_creating_or_overwriting(self):
        inventory = self.completed_simulation()
        inventory["bindings"] = {}
        inventory["journal"] = []
        gateway = creator.SimulatedWorkspace(inventory)
        preview = creator.creation_preview(self.blueprint, inventory)
        self.assertTrue(all(action["action"] == "adopt" for action in preview["actions"]))
        result = creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        self.assertEqual(result["created_count"], 0)
        self.assertEqual(gateway.snapshot()["objects"], inventory["objects"])
        self.assertEqual(len(gateway.snapshot()["bindings"]), 20)

    def test_accepted_creation_with_lost_response_recovers_the_same_object(self):
        class AcceptedButLost(creator.SimulatedWorkspace):
            def create_object(self, stable_id, expected):
                super().create_object(stable_id, expected)
                raise ValueError("simulated_accepted_response_lost")

        gateway = AcceptedButLost(creator.empty_simulation(self.blueprint))
        preview = creator.creation_preview(self.blueprint, gateway.snapshot())
        with self.assertRaisesRegex(ValueError, "simulated_accepted_response_lost"):
            creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        first_id = gateway.snapshot()["objects"][0]["id"]
        reloaded = creator.SimulatedWorkspace(gateway.snapshot())
        fresh = creator.creation_preview(self.blueprint, reloaded.snapshot())
        resumed = creator.create_workspace(self.blueprint, reloaded, fresh["preview_hash"])
        self.assertEqual(resumed["created_count"], 19)
        self.assertEqual(reloaded.snapshot()["objects"][0]["id"], first_id)
        self.assertEqual(len(reloaded.snapshot()["objects"]), 20)
        self.assertTrue(all(event["status"] == "verified" for event in reloaded.snapshot()["journal"]))

    def test_wrong_identity_parent_archive_or_completeness_stops_before_creation(self):
        cases = [("workspace_id", "99999999-9999-4999-8999-999999999999"),
                 ("complete", False), ("private_parent_verified", None),
                 ("parent_page_id", self.blueprint["existing_archive_database_id"]),
                 ("archive_access_verified", False), ("existing_archive_database_id", "99999999-9999-4999-8999-999999999999"),
                 ("mode", "live_notion")]
        for field, value in cases:
            with self.subTest(field=field):
                inventory = creator.empty_simulation(self.blueprint)
                inventory[field] = value
                gateway = creator.SimulatedWorkspace(inventory)
                with self.assertRaises(ValueError):
                    creator.create_workspace(self.blueprint, gateway, "not-a-preview")
                self.assertEqual(gateway.snapshot()["objects"], [])
                self.assertEqual(gateway.snapshot()["journal"], [])

    def test_duplicate_object_ids_or_missing_content_completeness_stop(self):
        complete = self.completed_simulation()
        cases = []
        changed = copy.deepcopy(complete); changed["objects"].append(copy.deepcopy(changed["objects"][0])); cases.append(changed)
        changed = copy.deepcopy(complete); changed["objects"][1]["id"] = changed["objects"][0]["id"]; cases.append(changed)
        changed = copy.deepcopy(complete); changed["objects"][1]["data_source_id"] = changed["objects"][1]["id"]; cases.append(changed)
        for field, value in [("truncated", True), ("unknown_block_count", False), ("unknown_block_count", 1), ("archived", True)]:
            changed = copy.deepcopy(complete); changed["objects"][0][field] = value; cases.append(changed)
        for index, inventory in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(ValueError):
                creator.creation_preview(self.blueprint, inventory)

    def test_managed_drift_missing_binding_or_changed_sources_never_recreate_or_patch(self):
        complete = self.completed_simulation()
        cases = []
        changed = copy.deepcopy(complete); changed["objects"][0]["content"] += "\n人工更改正文"; cases.append((self.blueprint, changed))
        changed = copy.deepcopy(complete); changed["objects"].pop(); cases.append((self.blueprint, changed))
        changed = copy.deepcopy(complete); changed["objects"][1]["schema"]["状态"] = {"type": "rich_text"}; cases.append((self.blueprint, changed))
        changed = copy.deepcopy(self.blueprint); changed["records"][1]["content"] += "\n新版本待确认"; cases.append((changed, complete))
        changed = copy.deepcopy(complete)
        next(item for item in changed["objects"] if item["stable_id"] == "XFO-T1")["relations"] = {"所属迭代": ["88888888-8888-4888-8888-888888888888"]}
        cases.append((self.blueprint, changed))
        for blueprint, inventory in cases:
            with self.subTest(case=len(inventory["objects"])):
                gateway = creator.SimulatedWorkspace(inventory)
                preview = creator.creation_preview(blueprint, inventory)
                self.assertFalse(preview["can_simulate"])
                with self.assertRaisesRegex(ValueError, "creation_conflict_requires_review"):
                    creator.create_workspace(blueprint, gateway, preview["preview_hash"])
                self.assertEqual(gateway.snapshot(), inventory)

    def test_stale_preview_and_non_simulation_gateway_stop(self):
        inventory = creator.empty_simulation(self.blueprint)
        gateway = creator.SimulatedWorkspace(inventory)
        with self.assertRaisesRegex(ValueError, "stale_preview"):
            creator.create_workspace(self.blueprint, gateway, "0" * 64)
        self.assertEqual(gateway.snapshot(), inventory)
        with self.assertRaisesRegex(ValueError, "simulation_gateway_required"):
            creator.create_workspace(self.blueprint, object(), "0" * 64)

    def test_schema_or_relation_corruption_in_create_readback_stops_the_batch(self):
        class WrongSchema(creator.SimulatedWorkspace):
            def create_object(self, stable_id, expected):
                changed = copy.deepcopy(expected)
                if stable_id == "XFO-DB-WORK-1":
                    changed["schema"]["所属迭代"]["data_source_id"] = "88888888-8888-4888-8888-888888888888"
                return super().create_object(stable_id, changed)

        gateway = WrongSchema(creator.empty_simulation(self.blueprint))
        preview = creator.creation_preview(self.blueprint, gateway.snapshot())
        with self.assertRaisesRegex(ValueError, "created_object_readback_mismatch"):
            creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        self.assertEqual(len(gateway.snapshot()["objects"]), 3)
        self.assertNotIn("XFO-DB-WORK-1", gateway.snapshot()["bindings"])

    def test_cli_preview_does_not_write_and_credential_or_online_options_do_not_exist(self):
        script = ROOT / "scripts/xfit-notion-workspace.py"
        source = ROOT / "docs/operations/notion-blueprint.json"
        with tempfile.TemporaryDirectory(prefix="xfit-workspace-preview-") as directory:
            result = subprocess.run([sys.executable, str(script), "preview", "--blueprint", str(source)],
                                    cwd=directory, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(result.stdout)["remote_calls"], 0)
            self.assertEqual(list(Path(directory).iterdir()), [])
            for flag in ("--allow-write", "--credential", "--token", "--online"):
                rejected = subprocess.run([sys.executable, str(script), "preview", "--blueprint", str(source), flag],
                                          cwd=directory, capture_output=True, text=True, timeout=10)
                self.assertEqual(rejected.returncode, 2)
                self.assertEqual(list(Path(directory).iterdir()), [])

    def test_cli_existing_artifact_directory_is_not_overwritten(self):
        with tempfile.TemporaryDirectory(prefix="xfit-workspace-protected-") as directory:
            target = Path(directory).resolve()
            sentinel = target / "human.md"
            sentinel.write_text("不能覆盖", encoding="utf-8")
            result = subprocess.run([sys.executable, str(ROOT / "scripts/xfit-notion-workspace.py"), "simulate",
                                     "--blueprint", str(ROOT / "docs/operations/notion-blueprint.json"),
                                     "--out-dir", str(target)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(json.loads(result.stdout)["error"], "artifact_directory_already_exists")
            self.assertEqual({p.name for p in target.iterdir()}, {"human.md"})
            self.assertEqual(sentinel.read_text(), "不能覆盖")

    def test_original_blueprint_page_binding_is_not_ignored_when_remote_object_is_absent(self):
        self.blueprint["bindings"]["XFO-HUB-1"] = {
            "page_id": "88888888-8888-4888-8888-888888888888",
            "managed_hash": creator.digest(creator.offline.managed(self.blueprint["records"][0]))}
        inventory = creator.empty_simulation(self.blueprint)
        preview = creator.creation_preview(self.blueprint, inventory)
        self.assertFalse(preview["can_simulate"])
        self.assertEqual(preview["actions"][0]["action"], "conflict")
        gateway = creator.SimulatedWorkspace(inventory)
        with self.assertRaisesRegex(ValueError, "creation_conflict_requires_review"):
            creator.create_workspace(self.blueprint, gateway, preview["preview_hash"])
        self.assertEqual(gateway.snapshot()["objects"], [])

    def test_malformed_structured_inputs_fail_at_the_public_validation_boundary(self):
        inventory = creator.empty_simulation(self.blueprint)
        cases = [(None, inventory), (self.blueprint, []),
                 ({**self.blueprint, "records": [None] * 17}, inventory),
                 ({**self.blueprint, "databases": [None] * 3}, inventory)]
        for blueprint, state in cases:
            with self.subTest(input_type=type(blueprint).__name__), self.assertRaises(ValueError):
                creator.creation_preview(blueprint, state)


if __name__ == "__main__":
    unittest.main()
