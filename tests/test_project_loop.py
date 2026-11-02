"""Contract tests through the offline CLI, without network or application stores."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "xfit-project-loop.py"


def ready_cycle():
    return {
        "schema_version": 1, "id": "cycle-1", "version": "v1",
        "tasks": [{"id": "T1", "title": "本地实现", "track": "product", "status": "done",
                   "evidence": ["outputs/verified.md"], "blockers": []}],
        "gates": {"local": "PASS", "device": "PASS", "human": "PASS", "effect": "PASS"},
        "notion": {"expected_workspace_id": "private-ws", "observed_workspace_id": "private-ws",
                   "access": "verified", "remote_readback": "PASS"},
    }


def blueprint():
    return {"schema_version": 1, "workspace_id": "private-ws", "records": [
        {"id": "goal-1", "kind": "goal", "title": "训练目标",
         "properties": {"名称": "训练目标", "状态": "待验证", "我的备注": "local ignored"},
         "content": "管理正文\n保留原文。"}], "bindings": {}}


def inventory(record=None):
    pages = [] if record is None else [{"stable_id": record["id"], "page_id": "page-1",
        "properties": copy.deepcopy(record["properties"]), "content": record["content"],
        "truncated": False, "unknown_block_count": 0}]
    return {"workspace_id": "private-ws", "complete": True, "pages": pages}


class ProjectLoopCLITests(unittest.TestCase):
    def cli(self, command, **documents):
        with tempfile.TemporaryDirectory(prefix="xfit-loop-contract-") as directory:
            args = [sys.executable, str(SCRIPT), command]
            originals = {}
            for name, document in documents.items():
                path = Path(directory) / (name + ".json")
                data = document.encode() if isinstance(document, str) else json.dumps(document, ensure_ascii=False).encode()
                path.write_bytes(data)
                originals[path] = data
                args.extend(["--" + name, str(path)])
            result = subprocess.run(args, text=True, capture_output=True, timeout=10)
            for path, before in originals.items():
                self.assertEqual(path.read_bytes(), before, "CLI must not rewrite inputs or acknowledge baselines")
            self.assertEqual(set(Path(directory).iterdir()), set(originals), "CLI must not create side-effect files")
            return result.returncode, json.loads(result.stdout)

    def test_status_is_ready_only_after_all_four_gates_and_matching_verified_notion(self):
        code, result = self.cli("status", cycle=ready_cycle())
        self.assertEqual(code, 0)
        self.assertEqual(result["overall"], "ready")
        self.assertEqual(result["task_counts"]["done"], 1)
        self.assertEqual(result["unfinished_tasks"], [])
        cycle = ready_cycle()
        cycle["gates"]["device"] = "NOT_RUN"
        cycle["gates"]["human"] = "BLOCKED_HUMAN"
        code, result = self.cli("status", cycle=cycle)
        self.assertEqual(code, 0)
        self.assertEqual(result["overall"], "partial")
        self.assertEqual(result["unfinished_gates"], {"device": "NOT_RUN", "human": "BLOCKED_HUMAN"})

    def test_status_rejects_duplicate_and_contradictory_or_incomplete_tasks(self):
        cases = []
        cycle = ready_cycle(); cycle["tasks"].append(copy.deepcopy(cycle["tasks"][0])); cases.append(cycle)
        cycle = ready_cycle(); cycle["tasks"][0]["evidence"] = []; cases.append(cycle)
        cycle = ready_cycle(); cycle["tasks"][0]["blockers"] = ["仍待确认"]; cases.append(cycle)
        cycle = ready_cycle(); cycle["tasks"][0]["status"] = "blocked"; cases.append(cycle)
        cycle = ready_cycle(); cycle["tasks"][0]["track"] = "unknown"; cases.append(cycle)
        cycle = ready_cycle(); del cycle["gates"]["human"]; cases.append(cycle)
        cycle = ready_cycle(); cycle["schema_version"] = True; cases.append(cycle)
        cycle = ready_cycle(); cycle["tasks"] = []; cases.append(cycle)
        for index, cycle in enumerate(cases):
            with self.subTest(case=index):
                code, result = self.cli("status", cycle=cycle)
                self.assertEqual(code, 2)
                self.assertIn("error", result)
                self.assertNotIn("overall", result)

    def test_status_reports_unfinished_tracks_and_unverified_notion_without_claiming_ready(self):
        cycle = ready_cycle()
        cycle["tasks"].extend([
            {"id": "T2", "title": "体系", "track": "framework", "status": "blocked", "evidence": [], "blockers": ["空间不符"]},
            {"id": "T3", "title": "内容", "track": "content", "status": "in_progress", "evidence": [], "blockers": []},
        ])
        cycle["notion"]["observed_workspace_id"] = "wrong-workspace"
        code, result = self.cli("status", cycle=cycle)
        self.assertEqual(code, 0)
        self.assertEqual(result["overall"], "partial")
        self.assertFalse(result["notion_verified"])
        self.assertEqual([t["id"] for t in result["unfinished_tasks"]], ["T2", "T3"])
        self.assertEqual(result["track_counts"], {"product": 1, "framework": 1, "content": 1})

    def test_preview_create_adopt_then_repeated_noop_preserves_human_fields(self):
        local = blueprint()
        code, created = self.cli("preview", blueprint=local, remote=inventory())
        self.assertEqual(code, 0)
        self.assertEqual(created["actions"][0]["action"], "create")
        self.assertNotIn("我的备注", created["actions"][0]["managed"]["properties"])
        self.assertEqual(created["actions"][0]["managed"]["content"], local["records"][0]["content"])
        remote = inventory(local["records"][0])
        remote["pages"][0]["properties"].update({"我的备注": "真实人工备注", "建议调整": "先不要增加组数"})
        code, adopted = self.cli("preview", blueprint=local, remote=remote)
        self.assertEqual(code, 0)
        self.assertEqual(adopted["actions"][0]["action"], "adopt")
        self.assertEqual(adopted["actions"][0]["managed_hash"], created["actions"][0]["managed_hash"])
        local["bindings"]["goal-1"] = {"page_id": "page-1", "managed_hash": adopted["actions"][0]["managed_hash"]}
        code, first = self.cli("preview", blueprint=local, remote=remote)
        code_again, second = self.cli("preview", blueprint=local, remote=remote)
        self.assertEqual((code, code_again), (0, 0))
        self.assertEqual(first, second)
        self.assertEqual(first["actions"][0]["action"], "no_op")
        remote["pages"][0]["properties"]["我的备注"] = "新的人工作业内容"
        code, human_changed = self.cli("preview", blueprint=local, remote=remote)
        self.assertEqual(code, 0)
        self.assertEqual(human_changed["actions"][0]["action"], "no_op")

    def test_preview_refuses_wrong_workspace_incomplete_inventory_and_duplicate_identities(self):
        cases = []
        local = blueprint(); remote = inventory(); remote["workspace_id"] = "wrong"; cases.append((local, remote))
        local = blueprint(); remote = inventory(); remote["complete"] = False; cases.append((local, remote))
        local = blueprint(); local["records"].append(copy.deepcopy(local["records"][0])); cases.append((local, inventory()))
        local = blueprint(); remote = inventory(local["records"][0]); remote["pages"].append(copy.deepcopy(remote["pages"][0])); cases.append((local, remote))
        local = blueprint(); remote = inventory(local["records"][0]); extra = copy.deepcopy(remote["pages"][0]); extra["stable_id"] = "other"; remote["pages"].append(extra); cases.append((local, remote))
        for key, replacement in [("truncated", True), ("unknown_block_count", 1), ("unknown_block_count", False), ("content", None), ("properties", [])]:
            local = blueprint(); remote = inventory(local["records"][0]); remote["pages"][0][key] = replacement; cases.append((local, remote))
        local = blueprint(); remote = inventory(local["records"][0]); del remote["pages"][0]["content"]; cases.append((local, remote))
        local = blueprint(); local["bindings"] = {"goal-1": {"page_id": "page-1", "managed_hash": "not-a-hash"}}; cases.append((local, inventory()))
        local = blueprint(); remote = inventory(); local["records"][0]["content"] = None; cases.append((local, remote))
        for index, (local, remote) in enumerate(cases):
            with self.subTest(case=index):
                code, result = self.cli("preview", blueprint=local, remote=remote)
                self.assertEqual(code, 2)
                self.assertIn("error", result)
                self.assertFalse(result["can_apply"])
                self.assertNotIn("actions", result)

    def test_preview_conflicts_on_changed_managed_sources_missing_or_replaced_bound_page(self):
        local = blueprint(); remote = inventory(local["records"][0])
        code, result = self.cli("preview", blueprint=local, remote=remote)
        self.assertEqual(code, 0)
        local["bindings"]["goal-1"] = {"page_id": "page-1", "managed_hash": result["actions"][0]["managed_hash"]}
        cases = []
        changed = copy.deepcopy(remote); changed["pages"][0]["content"] += "\n人工修改管理正文"; cases.append((local, changed, "remote_changed_since_binding"))
        changed = copy.deepcopy(remote); changed["pages"][0]["properties"]["状态"] = "已完成"; cases.append((local, changed, "remote_changed_since_binding"))
        changed = copy.deepcopy(local); changed["records"][0]["content"] += "\n新版本"; cases.append((changed, remote, "local_changed_since_binding"))
        cases.append((local, inventory(), "bound_page_missing_or_replaced"))
        changed = copy.deepcopy(remote); changed["pages"][0]["page_id"] = "replacement"; cases.append((local, changed, "bound_page_missing_or_replaced"))
        changed = copy.deepcopy(local); changed["records"] = []; cases.append((changed, remote, "bound_local_record_missing"))
        changed = copy.deepcopy(local); changed["bindings"] = {}; changed_remote = copy.deepcopy(remote); changed_remote["pages"][0]["content"] = "different"; cases.append((changed, changed_remote, "unbound_remote_record_differs"))
        for index, (candidate, source, reason) in enumerate(cases):
            with self.subTest(case=index):
                code, result = self.cli("preview", blueprint=candidate, remote=source)
                self.assertEqual(code, 2)
                self.assertFalse(result["can_apply"])
                self.assertEqual(result["actions"][0]["action"], "conflict")
                self.assertEqual(result["actions"][0]["reason"], reason)

    def test_json_duplicate_keys_and_nonfinite_values_are_rejected_as_invalid_input(self):
        valid = json.dumps(ready_cycle())
        duplicate = valid.replace('"schema_version": 1', '"schema_version": 0, "schema_version": 1')
        for raw in [duplicate, valid[:-1] + ', "extra": NaN}', '{broken', '[]']:
            with self.subTest(raw=raw[:25]):
                code, result = self.cli("status", cycle=raw)
                self.assertEqual(code, 2)
                self.assertIn("error", result)
                self.assertNotIn("overall", result)

    def test_each_unverified_notion_boundary_and_gate_keeps_status_partial(self):
        for gate in ["local", "device", "human", "effect"]:
            cycle = ready_cycle(); cycle["gates"][gate] = "FAIL"
            code, result = self.cli("status", cycle=cycle)
            self.assertEqual(code, 0)
            self.assertEqual(result["overall"], "partial")
        for field, value in [("access", "unavailable"), ("remote_readback", "NOT_RUN"),
                             ("observed_workspace_id", None)]:
            cycle = ready_cycle(); cycle["notion"][field] = value
            code, result = self.cli("status", cycle=cycle)
            self.assertEqual(code, 0)
            self.assertEqual(result["overall"], "partial")

    def test_human_properties_do_not_change_preview_fingerprint_and_unknown_remote_pages_are_not_deleted(self):
        local = blueprint(); remote = inventory(local["records"][0])
        extra = copy.deepcopy(remote["pages"][0]); extra.update(stable_id="other", page_id="page-2")
        remote["pages"].append(extra)
        code, before = self.cli("preview", blueprint=local, remote=remote)
        self.assertEqual(code, 0)
        local["records"][0]["properties"]["我的备注"] = "never managed"
        remote["pages"][0]["properties"]["建议调整"] = "human update"
        code, after = self.cli("preview", blueprint=local, remote=remote)
        self.assertEqual(code, 0)
        self.assertEqual(before["preview_hash"], after["preview_hash"])
        self.assertEqual([a["id"] for a in after["actions"]], ["goal-1"])


if __name__ == "__main__":
    unittest.main()
