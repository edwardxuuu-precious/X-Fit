"""Public dedicated-access boundary: real orchestration, fake external Notion API."""
import copy
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("notion_access", ROOT / "scripts/xfit-notion-access.py")
access = importlib.util.module_from_spec(spec)
spec.loader.exec_module(access)


class FakeNotion:
    def __init__(self):
        self.workspace = "11111111-1111-4111-8111-111111111111"
        self.database = "22222222-2222-4222-8222-222222222222"
        self.source = "33333333-3333-4333-8333-333333333333"
        self.pages = []
        self.contents = {}
        self.calls = []

    def me(self):
        self.calls.append("me")
        return {"object": "user", "id": "44444444-4444-4444-8444-444444444444", "type": "bot",
                "bot": {"workspace_id": self.workspace, "workspace_name": "Edward's Notion"}}

    def retrieve_database(self, database_id):
        self.calls.append("database")
        return {"object": "database", "id": self.database, "data_sources": [{"id": self.source}]}

    def retrieve_data_source(self, source_id):
        self.calls.append("source")
        return {"object": "data_source", "id": self.source,
                "parent": {"type": "database_id", "database_id": self.database},
                "properties": {"标题": {"type": "title"}, "档案ID": {"type": "rich_text"},
                               "版本": {"type": "rich_text"}, "我的备注": {"type": "rich_text"},
                               "建议调整": {"type": "rich_text"}, "类型": {"type": "select"},
                               "状态": {"type": "select"}, "生效日期": {"type": "date"},
                               "到期日期": {"type": "date"}, "偏好版本": {"type": "rich_text"},
                               "来源": {"type": "rich_text"}}}

    def query_data_source(self, source_id, cursor=None):
        self.calls.append("query")
        start = int(cursor or 0)
        rows = self.pages[start:start + 1]
        more = start + 1 < len(self.pages)
        return {"object": "list", "results": copy.deepcopy(rows), "has_more": more,
                "next_cursor": str(start + 1) if more else None}

    def retrieve_page(self, page_id):
        self.calls.append("page")
        return copy.deepcopy(next(p for p in self.pages if p["id"] == page_id))

    def retrieve_markdown(self, page_id):
        self.calls.append("markdown")
        return {"object": "page_markdown", "id": page_id, "markdown": self.contents[page_id],
                "truncated": False, "unknown_block_ids": []}

    def add(self, number, record_id, note="保留我的意见"):
        page_id = "55555555-5555-4555-8555-%012d" % number
        raw = lambda value, kind="rich_text": {"type": kind, kind: [{"plain_text": value, "text": {"content": value}}]}
        page = {"object": "page", "id": page_id,
                "parent": {"type": "data_source_id", "data_source_id": self.source},
                "last_edited_time": "2026-10-04T11:00:00.000Z", "archived": False,
                "properties": {"标题": raw("训练规则", "title"), "档案ID": raw(record_id),
                               "版本": raw("v1"), "我的备注": raw(note)}}
        self.pages.append(page)
        self.contents[page_id] = "## 已确认\n原始训练规则"
        return page

    def create_page(self, payload):
        self.calls.append("create")
        rid = payload["properties"]["档案ID"]["rich_text"][0]["text"]["content"]
        page = self.add(len(self.pages) + 1, rid, note="")
        self.contents[page["id"]] = payload["markdown"]
        page["properties"] = {name: {"type": next(iter(value)), **copy.deepcopy(value)}
                              for name, value in payload["properties"].items()}
        return copy.deepcopy(page)


class DedicatedAccessTests(unittest.TestCase):
    def setUp(self):
        self.api = FakeNotion()
        self.config = {"schema_version": 1, "api_version": "2026-03-11",
                       "workspace_id": self.api.workspace, "workspace_name": "Edward's Notion",
                       "writes_enabled": False}
        self.state = {"schema_version": 1, "workspace_id": self.api.workspace,
                      "database_id": self.api.database, "data_source_id": self.api.source,
                      "bindings": {}}

    def test_wrong_workspace_stops_before_archive_access(self):
        self.api.workspace = "99999999-9999-4999-8999-999999999999"
        client = access.DedicatedAccess(self.config, self.state, self.api)
        with self.assertRaisesRegex(access.AccessError, "workspace_mismatch"):
            client.doctor()
        self.assertEqual(self.api.calls, ["me"])

    def test_full_snapshot_follows_pagination_and_keeps_human_feedback(self):
        one = self.api.add(1, "XFT-ONE")
        two = self.api.add(2, "XFT-TWO", note="不想增加组数")
        self.state["bindings"] = {"XFT-ONE": {"page_id": one["id"]}, "XFT-TWO": {"page_id": two["id"]}}
        snapshot = access.DedicatedAccess(self.config, self.state, self.api).snapshot()
        self.assertTrue(snapshot["complete"])
        self.assertEqual([p["record_id"] for p in snapshot["pages"]], ["XFT-ONE", "XFT-TWO"])
        self.assertEqual(snapshot["pages"][1]["properties"]["我的备注"], "不想增加组数")
        self.assertEqual(snapshot["pages"][0]["content"], "## 已确认\n原始训练规则")

    def test_duplicate_stable_identity_is_not_a_complete_inventory(self):
        self.api.add(1, "XFT-ONE")
        self.api.add(2, "XFT-ONE")
        with self.assertRaisesRegex(access.AccessError, "duplicate_remote_identity"):
            access.DedicatedAccess(self.config, self.state, self.api).snapshot()

    def test_truncated_or_unknown_content_stops_the_whole_snapshot(self):
        self.api.add(1, "XFT-ONE")
        good = self.api.retrieve_markdown
        self.api.retrieve_markdown = lambda page_id: {**good(page_id), "truncated": True,
                                                     "unknown_block_ids": ["unread-block"]}
        with self.assertRaisesRegex(access.AccessError, "incomplete_markdown"):
            access.DedicatedAccess(self.config, self.state, self.api).snapshot()

    def test_query_result_limit_is_not_treated_as_complete(self):
        self.api.add(1, "XFT-ONE")
        good = self.api.query_data_source
        self.api.query_data_source = lambda source, cursor=None: {
            **good(source, cursor), "request_status": {"type": "incomplete", "incomplete_reason": "query_result_limit_reached"}}
        with self.assertRaisesRegex(access.AccessError, "query_incomplete"):
            access.DedicatedAccess(self.config, self.state, self.api).snapshot()

    def test_missing_bound_page_is_not_recreated(self):
        self.state["bindings"] = {"XFT-OLD": {"page_id": "55555555-5555-4555-8555-000000000001"}}
        with self.assertRaisesRegex(access.AccessError, "bound_page_missing_or_replaced"):
            access.DedicatedAccess(self.config, self.state, self.api).snapshot()

    def test_edit_during_read_stops_instead_of_mixing_versions(self):
        self.api.add(1, "XFT-ONE")
        good = self.api.retrieve_page
        self.api.retrieve_page = lambda page_id: {**good(page_id), "last_edited_time": "2026-10-04T11:01:00.000Z"}
        with self.assertRaisesRegex(access.AccessError, "remote_changed_during_read"):
            access.DedicatedAccess(self.config, self.state, self.api).snapshot()

    def test_unknown_block_tag_is_rejected_even_if_not_reported_as_truncated(self):
        page = self.api.add(1, "XFT-ONE")
        self.api.contents[page["id"]] = '<unknown url="https://notion.so/opaque"/>'
        with self.assertRaisesRegex(access.AccessError, "incomplete_markdown"):
            access.DedicatedAccess(self.config, self.state, self.api).snapshot()

    def test_second_inventory_detects_a_new_page_during_read(self):
        self.api.add(1, "XFT-ONE")
        good = self.api.retrieve_markdown
        def add_after_read(page_id):
            value = good(page_id)
            self.api.add(2, "XFT-TWO")
            return value
        self.api.retrieve_markdown = add_after_read
        with self.assertRaisesRegex(access.AccessError, "remote_changed_during_read"):
            access.DedicatedAccess(self.config, self.state, self.api).snapshot()

    def test_partially_returned_rich_text_is_not_silently_dropped(self):
        page = self.api.add(1, "XFT-ONE")
        page["properties"]["我的备注"]["rich_text"] = [{"type": "mention", "mention": {"type": "user"}}]
        with self.assertRaisesRegex(access.AccessError, "incomplete_rich_text"):
            access.DedicatedAccess(self.config, self.state, self.api).snapshot()

    def test_preview_reuses_immutable_archive_rules_and_preserves_human_fields(self):
        page = self.api.add(1, "XFT-ONE")
        record = {"id": "XFT-ONE", "version": "v1", "properties": {"标题": "训练规则", "档案ID": "XFT-ONE", "版本": "v1"},
                  "content": "## 已确认\n原始训练规则"}
        records = {"workspace_id": self.api.workspace, "data_source_id": self.api.source, "records": [record]}
        client = access.DedicatedAccess(self.config, self.state, self.api)
        preview = client.preview(records)
        self.assertEqual(preview["actions"][0]["action"], "adopt_existing")
        self.state["bindings"] = preview["verified_binding_candidate"]["bindings"]
        self.api.pages[0]["properties"]["我的备注"]["rich_text"][0]["plain_text"] = "我的新反馈"
        self.assertEqual(client.preview(records)["actions"][0]["action"], "no_op")
        self.api.contents[page["id"]] += "\n人工更改正式规则"
        conflict = client.preview(records)
        self.assertFalse(conflict["can_apply"])
        self.assertEqual(conflict["actions"][0]["reason"], "remote_changed_since_readback")

    def test_explicit_append_is_read_back_and_repeat_creates_nothing(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        journal = access.WriteJournal(Path(tmp.name) / "journal.json")
        record = {"id": "XFT-NEW", "version": "v1",
                  "properties": {"标题": "训练规则", "档案ID": "XFT-NEW", "版本": "v1", "我的备注": "不应上传这个字段"},
                  "content": "## 已确认\n原始训练规则"}
        records = {"workspace_id": self.api.workspace, "data_source_id": self.api.source, "records": [record]}
        self.config["writes_enabled"] = True
        client = access.DedicatedAccess(self.config, self.state, self.api)
        preview = client.preview(records)
        result = client.sync(records, preview["preview_hash"], ["XFT-NEW"], allow_write=True, journal=journal)
        self.assertEqual(result["created_count"], 1)
        self.assertEqual(result["readback"], "PASS")
        self.assertNotIn("我的备注", self.api.pages[0]["properties"])
        self.state["bindings"] = result["verified_binding_candidate"]["bindings"]
        again = client.preview(records)
        repeated = client.sync(records, again["preview_hash"], ["XFT-NEW"], allow_write=True, journal=journal)
        self.assertEqual(repeated["created_count"], 0)
        self.assertEqual(self.api.calls.count("create"), 1)

    def test_current_eight_bound_records_remain_unchanged_and_no_op(self):
        records = access.read_json(ROOT / "docs/training/archive-records.json")
        state = access.read_json(ROOT / "docs/training/notion-sync-state.json")
        self.api.workspace, self.api.database, self.api.source = state["workspace_id"], state["database_id"], state["data_source_id"]
        self.config["workspace_id"] = state["workspace_id"]
        schema = self.api.retrieve_data_source(self.api.source)["properties"]
        for number, record in enumerate(records["records"], 1):
            page = self.api.add(number, record["id"])
            old_id = page["id"]
            page["id"] = state["bindings"][record["id"]]["page_id"]
            page["properties"] = {name: {"type": next(iter(value)), **value}
                                  for name, value in access.encode_properties(record["properties"], schema).items()}
            page["properties"]["我的备注"] = {"type": "rich_text", "rich_text": [{"plain_text": "我的真实反馈"}]}
            self.api.contents.pop(old_id)
            self.api.contents[page["id"]] = record["content"]
        result = access.DedicatedAccess(self.config, state, self.api).preview(records)
        self.assertTrue(result["can_apply"])
        self.assertEqual([a["action"] for a in result["actions"]], ["no_op"] * 8)
        self.assertEqual(len(result["verified_binding_candidate"]["bindings"]), 8)
        self.assertEqual(self.api.calls.count("create"), 0)

    def test_missing_write_grant_cannot_mutate_or_read_the_remote(self):
        with self.assertRaisesRegex(access.AccessError, "writes_not_enabled"):
            access.DedicatedAccess(self.config, self.state, self.api).sync({}, "irrelevant", ["XFT-ONE"], allow_write=True)
        self.assertEqual(self.api.calls, [])

    def test_unknown_create_outcome_is_durable_and_not_blindly_retried(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        journal_path = Path(tmp.name) / "journal.json"
        journal = access.WriteJournal(journal_path)
        self.config["writes_enabled"] = True
        record = {"id": "XFT-NEW", "version": "v1", "properties": {"标题": "训练规则", "档案ID": "XFT-NEW", "版本": "v1"},
                  "content": "## 已确认\n原始训练规则"}
        records = {"workspace_id": self.api.workspace, "data_source_id": self.api.source, "records": [record]}
        client = access.DedicatedAccess(self.config, self.state, self.api)
        preview = client.preview(records)
        calls = []
        def uncertain(payload):
            calls.append(payload)
            raise access.AccessError("write_outcome_unknown")
        self.api.create_page = uncertain
        with self.assertRaisesRegex(access.AccessError, "write_outcome_unknown"):
            client.sync(records, preview["preview_hash"], ["XFT-NEW"], allow_write=True, journal=journal)
        reloaded = access.WriteJournal(journal_path)
        self.assertEqual(reloaded.unsettled("XFT-NEW")["status"], "pending")
        with self.assertRaisesRegex(access.AccessError, "unsettled_write_requires_review"):
            client.sync(records, preview["preview_hash"], ["XFT-NEW"], allow_write=True, journal=reloaded)
        self.assertEqual(len(calls), 1)

    def test_accepted_create_with_lost_response_is_recovered_without_duplicate(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        journal_path = Path(tmp.name) / "journal.json"
        self.config["writes_enabled"] = True
        record = {"id": "XFT-NEW", "version": "v1", "properties": {"标题": "训练规则", "档案ID": "XFT-NEW", "版本": "v1"},
                  "content": "## 已确认\n原始训练规则"}
        records = {"workspace_id": self.api.workspace, "data_source_id": self.api.source, "records": [record]}
        client = access.DedicatedAccess(self.config, self.state, self.api)
        before = client.preview(records)
        create = self.api.create_page

        def accepted_but_timed_out(payload):
            create(payload)
            raise access.AccessError("write_outcome_unknown")

        self.api.create_page = accepted_but_timed_out
        with self.assertRaisesRegex(access.AccessError, "write_outcome_unknown"):
            client.sync(records, before["preview_hash"], ["XFT-NEW"], allow_write=True,
                        journal=access.WriteJournal(journal_path))
        fresh = client.preview(records)
        self.assertEqual(fresh["actions"][0]["action"], "adopt_existing")
        recovered = client.sync(records, fresh["preview_hash"], ["XFT-NEW"], allow_write=True,
                                journal=access.WriteJournal(journal_path))
        self.assertEqual(recovered["created_count"], 0)
        self.assertEqual(recovered["readback"], "PASS")
        self.assertIsNone(access.WriteJournal(journal_path).unsettled("XFT-NEW"))
        self.assertEqual(self.api.calls.count("create"), 1)

    def test_stale_preview_and_unapproved_record_stop_before_create(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        journal = access.WriteJournal(Path(tmp.name) / "journal.json")
        self.config["writes_enabled"] = True
        record = {"id": "XFT-NEW", "version": "v1", "properties": {"标题": "训练规则", "档案ID": "XFT-NEW", "版本": "v1"},
                  "content": "## 已确认\n原始训练规则"}
        other = {**record, "id": "XFT-OTHER", "properties": {**record["properties"], "档案ID": "XFT-OTHER"}}
        records = {"workspace_id": self.api.workspace, "data_source_id": self.api.source, "records": [record, other]}
        client = access.DedicatedAccess(self.config, self.state, self.api)
        preview = client.preview(records)
        with self.assertRaisesRegex(access.AccessError, "preview_changed"):
            client.sync(records, "0" * 64, ["XFT-NEW"], allow_write=True, journal=journal)
        with self.assertRaisesRegex(access.AccessError, "record_not_authorized"):
            client.sync(records, preview["preview_hash"], ["XFT-NEW"], allow_write=True, journal=journal)
        self.assertEqual(self.api.calls.count("create"), 0)


class HttpBoundaryTests(unittest.TestCase):
    def test_provider_error_body_never_leaks_a_credential(self):
        from urllib.error import HTTPError
        marker = "ntn_test_credential_should_not_appear"

        class Denied:
            def open(self, request, timeout):
                raise HTTPError(request.full_url, 401, "denied", {},
                                io.BytesIO(json.dumps({"code": "unauthorized", "message": marker}).encode()))

        with self.assertRaises(access.AccessError) as failure:
            access.NotionAPI(marker, opener=Denied()).me()
        self.assertEqual(failure.exception.code, "notion_unauthorized")
        self.assertNotIn(marker, str(failure.exception))

    def test_notions_fixed_host_and_version_are_used(self):
        seen = []

        class Response(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *_):
                self.close()

        class Gateway:
            def open(self, request, timeout):
                seen.append((request.full_url, dict(request.header_items()), request.data, timeout))
                return Response(b'{"object":"user","type":"bot"}')

        access.NotionAPI("ntn_local_test_credential_only", opener=Gateway()).me()
        self.assertEqual(seen[0][0], "https://api.notion.com/v1/users/me")
        self.assertEqual(seen[0][1]["Notion-version"], "2026-03-11")
        self.assertIsNone(seen[0][2])

    def test_create_timeout_does_not_trigger_a_second_request(self):
        attempts = []
        class Gateway:
            def open(self, request, timeout):
                attempts.append(request)
                raise TimeoutError()
        with self.assertRaisesRegex(access.AccessError, "write_outcome_unknown"):
            access.NotionAPI("ntn_local_test_credential_only", opener=Gateway()).create_page({"markdown": "只做边界测试"})
        self.assertEqual(len(attempts), 1)

    def test_access_restriction_is_not_retried_as_an_ordinary_rate_limit(self):
        from urllib.error import HTTPError
        attempts = []
        class Gateway:
            def open(self, request, timeout):
                attempts.append(request)
                body = b'{"code":"rate_limited","additional_data":{"rate_limit_reason":"public_api_request_blocked"}}'
                raise HTTPError(request.full_url, 429, "denied", {"Retry-After": "0"}, io.BytesIO(body))
        with self.assertRaisesRegex(access.AccessError, "notion_api_restricted"):
            access.NotionAPI("ntn_local_test_credential_only", opener=Gateway()).me()
        self.assertEqual(len(attempts), 1)


class CliBoundaryTests(unittest.TestCase):
    def test_missing_dedicated_credential_returns_one_clear_gate_without_network(self):
        class MissingCredential:
            def get(self):
                raise access.AccessError("credential_missing")

        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = access.main(["doctor"], credential_store=MissingCredential())
        report = json.loads(output.getvalue())
        self.assertEqual(code, 2)
        self.assertEqual(report["status"], "BLOCKED_ENV")
        self.assertEqual(report["error"], "credential_missing")
        self.assertEqual(report["remote_calls"], 0)
        self.assertIn("auth-set", report["next_action"])

    def test_output_cannot_overwrite_the_original_binding_file(self):
        with self.assertRaisesRegex(access.AccessError, "artifact_output_outside_allowed_directory"):
            access.artifact_output(ROOT / "docs/training/notion-sync-state.json")

    def test_other_projects_environment_token_does_not_replace_dedicated_credential(self):
        class MissingCredential:
            def get(self):
                raise access.AccessError("credential_missing")
        output = io.StringIO()
        with mock.patch.dict(access.os.environ, {"NOTION_TOKEN": "ntn_other_project_not_for_xfit", "NOTION_API_TOKEN": "ntn_other_project_not_for_xfit"}), contextlib.redirect_stdout(output):
            result = access.main(["doctor"], credential_store=MissingCredential())
        self.assertEqual(result, 2)
        self.assertEqual(json.loads(output.getvalue())["remote_calls"], 0)
        self.assertNotIn("ntn_other_project", output.getvalue())

    def test_same_dedicated_channel_cannot_be_used_by_two_processes_at_once(self):
        workspace = "77777777-7777-4777-8777-777777777777"
        with tempfile.TemporaryDirectory() as runtime:
            with access.channel_lock(workspace, runtime_root=Path(runtime)):
                with self.assertRaisesRegex(access.AccessError, "dedicated_channel_busy"):
                    with access.channel_lock(workspace, runtime_root=Path(runtime)):
                        self.fail("second owner should not run")


class SecureInputTests(unittest.TestCase):
    def test_dialog_explains_generated_token_is_not_login_password(self):
        with mock.patch.object(access.sys, "platform", "darwin"), mock.patch.object(access.subprocess, "run", return_value=mock.Mock(returncode=0, stdout="local-token\n")) as run:
            self.assertEqual(access.secure_input(dialog=True), "local-token")
        script = run.call_args.args[0][2]
        self.assertIn("不是你的 Notion 登录密码", script)
        self.assertIn("若尚未生成令牌，请点取消", script)
        self.assertIn("hidden answer", script)
        self.assertIn("系统钥匙串", script)
        self.assertEqual(run.call_args.kwargs["timeout"], 600)

    def test_cancelled_dialog_does_not_return_a_credential(self):
        with mock.patch.object(access.sys, "platform", "darwin"), mock.patch.object(access.subprocess, "run", return_value=mock.Mock(returncode=1, stdout="")):
            with self.assertRaisesRegex(access.AccessError, "credential_input_cancelled"):
                access.secure_input(dialog=True)

    def test_terminal_prompt_distinguishes_token_from_login_password(self):
        with mock.patch.object(access.sys.stdin, "isatty", return_value=True), mock.patch.object(access.getpass, "getpass", return_value="local-token") as getpass:
            self.assertEqual(access.secure_input(), "local-token")
        self.assertIn("不是登录密码", getpass.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
