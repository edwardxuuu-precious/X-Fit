#!/usr/bin/env python3
"""Dedicated X-Fit Notion access. Fixed identity; append-only, explicitly gated writes."""
import argparse
import contextlib
import ctypes
import datetime
import fcntl
import getpass
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import tempfile
from urllib import error, parse, request
import uuid

HUMAN_FIELDS = {"我的备注", "建议调整"}
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "docs/operations/notion-access.json"

_archive_spec = importlib.util.spec_from_file_location("xfit_archive_offline", Path(__file__).with_name("xfit-training-archive.py"))
archive = importlib.util.module_from_spec(_archive_spec)
_archive_spec.loader.exec_module(archive)


class AccessError(Exception):
    """Only stable, locally authored errors may cross the CLI boundary."""
    def __init__(self, code, detail=None):
        self.code = code
        self.detail = detail
        super().__init__(code + (": " + detail if detail else ""))


def require(condition, code, detail=None):
    if not condition:
        raise AccessError(code, detail)


def normalized_id(value):
    try:
        return str(uuid.UUID(str(value)))
    except (ValueError, AttributeError, TypeError):
        raise AccessError("invalid_uuid") from None


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def secure_json(path, value):
    """Atomic private artifact writes, never credential persistence."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    require(not path.is_symlink(), "symlink_artifact_refused")
    fd, temporary = tempfile.mkstemp(prefix=".xfit-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            json.dump(value, output, ensure_ascii=False, indent=2, allow_nan=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class WriteJournal:
    """Durable creation receipts. An uncertain create is never blindly repeated."""
    def __init__(self, path):
        self.path = Path(path)
        require(not self.path.is_symlink(), "symlink_journal_refused")
        self.document = json.loads(self.path.read_text(encoding="utf-8")) if self.path.exists() else {"schema_version": 1, "attempts": []}
        require(self.document.get("schema_version") == 1 and isinstance(self.document.get("attempts"), list), "invalid_write_journal")

    def unsettled(self, rid):
        return next((event for event in reversed(self.document["attempts"])
                     if event["record_id"] == rid and event["status"] != "verified"), None)

    def begin(self, rid, preview_hash):
        require(self.unsettled(rid) is None, "unsettled_write_requires_review")
        self.document["attempts"].append({"record_id": rid, "preview_hash": preview_hash, "status": "pending",
                                          "page_id": None, "observed_at": utc_now()})
        secure_json(self.path, self.document)

    def received(self, rid, page_id):
        event = self.unsettled(rid)
        require(event is not None, "write_journal_missing_intent")
        event.update({"status": "created", "page_id": normalized_id(page_id)})
        secure_json(self.path, self.document)

    def verified(self, rid, page_id):
        event = self.unsettled(rid)
        if event:
            require(event.get("page_id") in (None, normalized_id(page_id)), "write_recovery_id_mismatch")
            event.update({"status": "verified", "page_id": normalized_id(page_id), "verified_at": utc_now()})
            secure_json(self.path, self.document)


def encode_properties(properties, schema):
    output, dates = {}, {}
    for name, value in properties.items():
        if name in HUMAN_FIELDS:
            continue
        if name.startswith("date:"):
            segments = name.split(":")
            require(len(segments) == 3 and segments[2] in ("start", "end", "is_datetime"), "unsupported_date_field")
            _, date_name, field = segments
            dates.setdefault(date_name, {})[field] = value
            continue
        require(name in schema, "write_schema_mismatch", name)
        kind = schema[name].get("type")
        if kind in ("title", "rich_text"):
            require(isinstance(value, str) and len(value) <= 190_000, "invalid_text_property", name)
            output[name] = {kind: [{"text": {"content": value[i:i + 1900]}} for i in range(0, len(value), 1900)]}
        elif kind == "select":
            require(isinstance(value, str), "invalid_select_property", name)
            output[name] = {kind: {"name": value} if value else None}
        elif kind in ("number", "checkbox", "url"):
            output[name] = {kind: value}
        else:
            raise AccessError("unsupported_write_property", name)
    for name, value in dates.items():
        require(schema.get(name, {}).get("type") == "date" and isinstance(value.get("start"), str), "write_date_schema_mismatch")
        flag = value.get("is_datetime", int("T" in value["start"]))
        require(flag in (0, 1) and bool(flag) == ("T" in value["start"]), "date_kind_mismatch")
        output[name] = {"date": {field: val for field, val in value.items() if field != "is_datetime"}}
    return output


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class NotionAPI:
    """External HTTP seam. Tokens never enter URLs, exception text, or logging."""
    def __init__(self, token, opener=None):
        require(isinstance(token, str) and len(token) >= 20 and not re.search(r"\s", token), "invalid_credential")
        self._token = token
        self._opener = opener or request.build_opener(NoRedirect())
        self.remote_calls = 0

    def _request(self, method, path, body=None, read_only=True, params=None):
        require(path.startswith("/v1/") and "?" not in path and ".." not in path, "invalid_api_path")
        if params is not None:
            require(method == "GET" and set(params) <= {"page_size", "start_cursor"}, "invalid_query_parameters")
            require(all(isinstance(value, (str, int)) and not isinstance(value, bool) for value in params.values()),
                    "invalid_query_parameters")
            path += "?" + parse.urlencode(params)
        data = None if body is None else json.dumps(body, ensure_ascii=False, allow_nan=False).encode("utf-8")
        require(data is None or len(data) <= 500_000, "request_too_large")
        req = request.Request("https://api.notion.com" + path, data=data, method=method,
                              headers={"Authorization": "Bearer " + self._token, "Notion-Version": "2026-03-11",
                                       "Content-Type": "application/json", "User-Agent": "XFit-NotionAccess/0.1"})
        for attempt in range(3):
            try:
                self.remote_calls += 1
                with self._opener.open(req, timeout=20) as response:
                    raw = response.read(8_000_001)
                require(len(raw) <= 8_000_000, "response_too_large")
                value = json.loads(raw)
                require(isinstance(value, dict), "invalid_api_response")
                return value
            except error.HTTPError as exc:
                status = exc.code
                retry_after = str(exc.headers.get("Retry-After", "")) if exc.headers else ""
                restricted = False
                if status in (429, 529):
                    try:
                        provider = json.loads(exc.read(16_384))
                        restricted = provider.get("additional_data", {}).get("rate_limit_reason") == "public_api_request_blocked"
                    except (ValueError, AttributeError, OSError):
                        pass
                exc.close()
                require(not restricted, "notion_api_restricted")
                delay = int(retry_after) if retry_after.isdigit() else 2 ** attempt
                if read_only and status in (429, 529, 500, 502, 503, 504) and attempt < 2 and delay <= 5:
                    time.sleep(delay)
                    continue
                code = {401: "notion_unauthorized", 403: "notion_permission_denied", 404: "notion_object_not_found",
                        409: "notion_conflict", 429: "notion_rate_limited", 529: "notion_overloaded"}.get(status, "notion_http_error")
                if not read_only and status >= 500:
                    code = "write_outcome_unknown"
                raise AccessError(code, "http_status=" + str(status)) from None
            except (error.URLError, TimeoutError, OSError):
                if read_only and attempt < 2:
                    time.sleep(2 ** attempt)
                    continue
                raise AccessError("notion_network_unavailable" if read_only else "write_outcome_unknown") from None
            except (ValueError, UnicodeError):
                raise AccessError("invalid_api_response" if read_only else "write_outcome_unknown") from None

    def me(self):
        return self._request("GET", "/v1/users/me")

    def retrieve_database(self, database_id):
        return self._request("GET", "/v1/databases/" + normalized_id(database_id))

    def retrieve_data_source(self, source_id):
        return self._request("GET", "/v1/data_sources/" + normalized_id(source_id))

    def query_data_source(self, source_id, cursor=None):
        body = {"page_size": 100, "sorts": [{"timestamp": "created_time", "direction": "ascending"}]}
        if cursor:
            body["start_cursor"] = cursor
        return self._request("POST", "/v1/data_sources/" + normalized_id(source_id) + "/query", body)

    def retrieve_page(self, page_id):
        return self._request("GET", "/v1/pages/" + normalized_id(page_id))

    def retrieve_markdown(self, page_id):
        return self._request("GET", "/v1/pages/" + normalized_id(page_id) + "/markdown")

    def create_page(self, payload):
        return self._request("POST", "/v1/pages", payload, read_only=False)

    def create_database(self, payload):
        return self._request("POST", "/v1/databases", payload, read_only=False)

    def retrieve_block_children(self, block_id, cursor=None):
        params = {"page_size": 100}
        if cursor:
            params["start_cursor"] = cursor
        return self._request("GET", "/v1/blocks/" + normalized_id(block_id) + "/children", params=params)


def flatten_properties(properties):
    result = {}
    require(isinstance(properties, dict), "incomplete_properties")
    for name, item in properties.items():
        kind = item.get("type")
        if kind in ("title", "rich_text"):
            parts = item.get(kind)
            require(isinstance(parts, list) and len(parts) < 25 and not item.get("has_more"),
                    "incomplete_property", name)
            text = []
            for part in parts:
                value = part.get("plain_text", part.get("text", {}).get("content"))
                require(isinstance(value, str), "incomplete_rich_text", name)
                text.append(value)
            result[name] = "".join(text)
        elif kind == "select":
            result[name] = (item.get(kind) or {}).get("name", "")
        elif kind == "date":
            value = item.get(kind)
            if value:
                require(value.get("time_zone") is None, "unsupported_date_timezone", name)
                for field in ("start", "end"):
                    if value.get(field) is not None:
                        result["date:" + name + ":" + field] = value[field]
                result["date:" + name + ":is_datetime"] = int("T" in value.get("start", ""))
        elif kind in ("url", "number", "checkbox", "created_time", "last_edited_time"):
            result[name] = item.get(kind)
        else:
            raise AccessError("unsupported_property", name)
    return result


class DedicatedAccess:
    def __init__(self, config, state, api):
        self.config, self.state, self.api = config, state, api
        require(config.get("schema_version") == 1, "invalid_config_schema")
        require(config.get("api_version") == "2026-03-11", "unsupported_api_version")
        self.workspace = normalized_id(config.get("workspace_id"))
        require(normalized_id(state.get("workspace_id")) == self.workspace, "binding_workspace_mismatch")
        self.database = normalized_id(state.get("database_id"))
        self.source = normalized_id(state.get("data_source_id"))
        self.source_schema = None

    def doctor(self):
        me = self.api.me()
        require(me.get("type") == "bot", "internal_connection_required")
        bot = me.get("bot", {})
        require(bool(bot.get("workspace_id")), "workspace_identity_unavailable")
        require(normalized_id(bot["workspace_id"]) == self.workspace, "workspace_mismatch")
        database = self.api.retrieve_database(self.database)
        require(database.get("object") == "database" and normalized_id(database.get("id")) == self.database,
                "database_mismatch")
        require(not database.get("archived") and not database.get("in_trash"), "archive_not_active")
        require(any(normalized_id(source.get("id")) == self.source
                    for source in database.get("data_sources", [])), "data_source_not_in_archive")
        source = self.api.retrieve_data_source(self.source)
        require(source.get("object") == "data_source" and normalized_id(source.get("id")) == self.source,
                "data_source_mismatch")
        parent = source.get("parent", {})
        require(parent.get("type") == "database_id" and normalized_id(parent.get("database_id")) == self.database,
                "data_source_parent_mismatch")
        require(not source.get("archived") and not source.get("in_trash"), "source_not_active")
        schema = source.get("properties")
        require(isinstance(schema, dict) and schema.get("档案ID", {}).get("type") == "rich_text",
                "archive_schema_mismatch")
        self.source_schema = schema
        return {"status": "PASS", "read_only": True, "workspace_id": self.workspace,
                "workspace_name": bot.get("workspace_name"), "database_id": self.database,
                "data_source_id": self.source, "private_acl_verification": "NOT_RUN"}

    def inventory(self):
        rows, cursor, seen_cursors, seen_pages = [], None, set(), set()
        for _ in range(100):
            batch = self.api.query_data_source(self.source, cursor)
            require(batch.get("object") == "list" and isinstance(batch.get("results"), list), "incomplete_query")
            status = batch.get("request_status")
            require(status is None or (isinstance(status, dict) and status.get("type") == "complete"), "query_incomplete")
            for row in batch["results"]:
                require(row.get("object") == "page" and isinstance(row.get("last_edited_time"), str),
                        "incomplete_page_metadata")
                row_id = normalized_id(row.get("id"))
                require(row_id not in seen_pages, "duplicate_remote_identity")
                seen_pages.add(row_id)
            rows.extend(batch["results"])
            require(type(batch.get("has_more")) is bool, "incomplete_query")
            if not batch["has_more"]:
                require(batch.get("next_cursor") is None, "inconsistent_query_cursor")
                return rows
            cursor = batch.get("next_cursor")
            require(isinstance(cursor, str) and cursor and cursor not in seen_cursors, "query_cursor_loop")
            seen_cursors.add(cursor)
        raise AccessError("query_page_limit")

    def snapshot(self):
        identity = self.doctor()
        rows = self.inventory()
        pages, seen_records = [], set()
        for row in rows:
            page_id = normalized_id(row.get("id"))
            page = self.api.retrieve_page(page_id)
            require(page.get("object") == "page" and normalized_id(page.get("id")) == page_id, "page_id_mismatch")
            parent = page.get("parent", {})
            require(parent.get("type") == "data_source_id" and normalized_id(parent.get("data_source_id")) == self.source,
                    "page_parent_mismatch")
            require(not page.get("archived") and not page.get("in_trash"), "page_not_active")
            require(page.get("last_edited_time") == row["last_edited_time"] and
                    page.get("properties") == row.get("properties"), "remote_changed_during_read")
            properties = flatten_properties(page.get("properties"))
            record_id = properties.get("档案ID")
            require(isinstance(record_id, str) and record_id.strip(), "record_id_missing")
            require(record_id not in seen_records, "duplicate_remote_identity")
            seen_records.add(record_id)
            markdown = self.api.retrieve_markdown(page_id)
            require(markdown.get("object") == "page_markdown" and normalized_id(markdown.get("id")) == page_id,
                    "markdown_id_mismatch")
            require(isinstance(markdown.get("markdown"), str), "incomplete_markdown")
            require(markdown.get("truncated") is False and markdown.get("unknown_block_ids") == [] and
                    not re.search(r"<unknown\b", markdown["markdown"], re.IGNORECASE), "incomplete_markdown")
            pages.append({"page_id": page_id, "record_id": record_id, "properties": properties,
                          "content": markdown["markdown"], "truncated": markdown.get("truncated"),
                          "unknown_block_count": len(markdown.get("unknown_block_ids", [])),
                          "last_edited_time": page.get("last_edited_time")})
        indexed = {page["record_id"]: page for page in pages}
        for rid, binding in self.state.get("bindings", {}).items():
            require(rid in indexed and indexed[rid]["page_id"] == normalized_id(binding.get("page_id")),
                    "bound_page_missing_or_replaced")
        signature = lambda inventory: {normalized_id(p["id"]): (p["last_edited_time"], p.get("properties")) for p in inventory}
        require(signature(rows) == signature(self.inventory()), "remote_changed_during_read")
        return {"schema_version": 1, "workspace_id": self.workspace, "database_id": self.database,
                "data_source_id": self.source, "complete": True, "pages": pages,
                "observed_at": utc_now(), "identity": identity, "transport": "notion-public-api-markdown"}

    def preview(self, records):
        require(records.get("workspace_id") == self.workspace and records.get("data_source_id") == self.source,
                "record_scope_mismatch")
        snapshot = self.snapshot()
        try:
            result = archive.preview(records, self.state, snapshot)
            if result["can_apply"] and not any(a["action"] == "create" for a in result["actions"]):
                result["verified_binding_candidate"] = archive.acknowledge(records, self.state, snapshot)
        except (ValueError, TypeError, KeyError):
            raise AccessError("invalid_archive_preview_inputs") from None
        return {**result, "read_only": True, "workspace_id": self.workspace, "database_id": self.database,
                "data_source_id": self.source, "observed_at": snapshot["observed_at"], "snapshot": snapshot,
                "binding_update_applied": False}

    def sync(self, records, confirm_hash, allowed_record_ids, allow_write=False, journal=None):
        require(allow_write is True and self.config.get("writes_enabled") is True, "writes_not_enabled")
        require(journal is not None, "persistent_write_journal_required")
        result = self.preview(records)
        require(result["can_apply"], "archive_conflict")
        require(result["preview_hash"] == confirm_hash, "preview_changed")
        allowed = set(allowed_record_ids)
        local = {r["id"]: r for r in records["records"]}
        require(allowed and allowed <= local.keys(), "invalid_authorized_record_scope")
        creates = [action for action in result["actions"] if action["action"] == "create"]
        require(all(action["record_id"] in allowed for action in creates), "record_not_authorized")
        snapshot = result["snapshot"]
        index = {page["record_id"]: page for page in snapshot["pages"]}
        for rid in allowed:
            pending = journal.unsettled(rid)
            if pending:
                require(rid in index and archive.fingerprint(index[rid]) == archive.fingerprint(local[rid]),
                        "unsettled_write_requires_review")
                journal.verified(rid, index[rid]["page_id"])
        payloads = {action["record_id"]: {"parent": {"data_source_id": self.source},
                                         "properties": encode_properties(local[action["record_id"]]["properties"], self.source_schema),
                                         "markdown": local[action["record_id"]]["content"]} for action in creates}
        signatures = lambda snap: {p["record_id"]: (p["page_id"], archive.fingerprint(p)) for p in snap["pages"]}
        created = []
        for action in creates:
            rid = action["record_id"]
            fresh = self.snapshot()
            require(signatures(fresh) == signatures(snapshot), "remote_changed_before_write")
            journal.begin(rid, confirm_hash)
            response = self.api.create_page(payloads[rid])
            require(response.get("object") == "page", "write_outcome_unknown")
            page_id = normalized_id(response.get("id"))
            journal.received(rid, page_id)
            after = self.snapshot()
            after_index = {p["record_id"]: p for p in after["pages"]}
            require(rid in after_index and after_index[rid]["page_id"] == page_id and
                    archive.fingerprint(after_index[rid]) == archive.fingerprint(local[rid]), "write_readback_differs")
            old_signatures = {k: v for k, v in signatures(after).items() if k != rid}
            require(old_signatures == signatures(snapshot), "existing_archive_changed_after_write")
            journal.verified(rid, page_id)
            created.append({"record_id": rid, "page_id": page_id})
            snapshot = after
        try:
            candidate = archive.acknowledge(records, self.state, snapshot)
        except (ValueError, TypeError, KeyError):
            raise AccessError("final_readback_differs") from None
        return {"status": "PASS", "created_count": len(created), "created": created,
                "readback": "PASS", "verified_binding_candidate": candidate,
                "binding_update_applied": False, "snapshot": snapshot,
                "repeat_preview": archive.preview(records, candidate, snapshot)}


class KeychainCredential:
    """Modern macOS SecItem API. No token-bearing argv, environment, or plaintext file."""
    def __init__(self, service, account):
        require(sys.platform == "darwin", "macos_keychain_required")
        require(service == "com.xfit.notion-access" or service.startswith("com.xfit.notion-access.selftest."), "credential_service_not_allowed")
        self.service, self.account = service, normalized_id(account)
        self.sec = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
        self.cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        ptr = ctypes.c_void_p
        self.cf.CFStringCreateWithCString.argtypes = [ptr, ctypes.c_char_p, ctypes.c_uint32]
        self.cf.CFStringCreateWithCString.restype = ptr
        self.cf.CFDataCreate.argtypes = [ptr, ptr, ctypes.c_long]
        self.cf.CFDataCreate.restype = ptr
        self.cf.CFDictionaryCreate.argtypes = [ptr, ctypes.POINTER(ptr), ctypes.POINTER(ptr), ctypes.c_long, ptr, ptr]
        self.cf.CFDictionaryCreate.restype = ptr
        self.cf.CFDataGetLength.argtypes = [ptr]
        self.cf.CFDataGetLength.restype = ctypes.c_long
        self.cf.CFDataGetBytePtr.argtypes = [ptr]
        self.cf.CFDataGetBytePtr.restype = ptr
        self.cf.CFRelease.argtypes = [ptr]
        self.cf.CFRelease.restype = None
        self.sec.SecItemCopyMatching.argtypes = [ptr, ctypes.POINTER(ptr)]
        self.sec.SecItemCopyMatching.restype = ctypes.c_int32
        self.sec.SecItemAdd.argtypes = [ptr, ctypes.POINTER(ptr)]
        self.sec.SecItemAdd.restype = ctypes.c_int32
        self.sec.SecItemUpdate.argtypes = [ptr, ptr]
        self.sec.SecItemUpdate.restype = ctypes.c_int32
        self.sec.SecItemDelete.argtypes = [ptr]
        self.sec.SecItemDelete.restype = ctypes.c_int32

    def constant(self, name):
        library = self.cf if name.startswith("kCF") else self.sec
        return ctypes.c_void_p.in_dll(library, name).value

    @contextlib.contextmanager
    def dictionary(self, entries):
        owned, keys, values, dictionary = [], [], [], None
        try:
            for key, (kind, value) in entries.items():
                keys.append(self.constant(key))
                if kind == "constant":
                    pointer = self.constant(value)
                elif kind == "text":
                    pointer = self.cf.CFStringCreateWithCString(None, value.encode("utf-8"), 0x08000100)
                    owned.append(pointer)
                elif kind == "data":
                    raw = value.encode("utf-8")
                    pointer = self.cf.CFDataCreate(None, ctypes.c_char_p(raw), len(raw))
                    owned.append(pointer)
                else:
                    raise AccessError("invalid_keychain_value")
                require(bool(pointer), "keychain_allocation_failed")
                values.append(pointer)
            array = ctypes.c_void_p * len(keys)
            callbacks = lambda name: ctypes.addressof(ctypes.c_byte.in_dll(self.cf, name))
            dictionary = self.cf.CFDictionaryCreate(None, array(*keys), array(*values), len(keys),
                                                   callbacks("kCFTypeDictionaryKeyCallBacks"), callbacks("kCFTypeDictionaryValueCallBacks"))
            require(bool(dictionary), "keychain_allocation_failed")
            yield dictionary
        finally:
            if dictionary:
                self.cf.CFRelease(dictionary)
            for pointer in owned:
                if pointer:
                    self.cf.CFRelease(pointer)

    def selector(self):
        return {"kSecClass": ("constant", "kSecClassGenericPassword"),
                "kSecAttrService": ("text", self.service), "kSecAttrAccount": ("text", self.account)}

    def lookup(self, metadata=False):
        entries = {**self.selector(), "kSecMatchLimit": ("constant", "kSecMatchLimitOne"),
                   ("kSecReturnAttributes" if metadata else "kSecReturnData"): ("constant", "kCFBooleanTrue")}
        if metadata:
            entries["kSecUseAuthenticationUI"] = ("constant", "kSecUseAuthenticationUIFail")
        result = ctypes.c_void_p()
        with self.dictionary(entries) as query:
            status = self.sec.SecItemCopyMatching(query, ctypes.byref(result))
        if status == -25300:
            if metadata:
                return False
            raise AccessError("credential_missing")
        require(status == 0, "keychain_access_unavailable", "os_status=" + str(status))
        try:
            if metadata:
                return True
            length = self.cf.CFDataGetLength(result)
            require(0 < length <= 4096, "invalid_credential_length")
            return ctypes.string_at(self.cf.CFDataGetBytePtr(result), length).decode("utf-8")
        finally:
            if result.value:
                self.cf.CFRelease(result)

    def present(self):
        return self.lookup(metadata=True)

    def get(self):
        return self.lookup()

    def set(self, token, replace=False):
        require(isinstance(token, str) and 20 <= len(token) <= 4096 and not re.search(r"\s", token), "invalid_credential")
        entries = {**self.selector(), "kSecValueData": ("data", token),
                   "kSecAttrSynchronizable": ("constant", "kCFBooleanFalse")}
        with self.dictionary(entries) as query:
            status = self.sec.SecItemAdd(query, None)
        if status == -25299:
            require(replace is True, "credential_exists_use_explicit_replace")
            with self.dictionary(self.selector()) as query, self.dictionary({"kSecValueData": ("data", token)}) as changes:
                status = self.sec.SecItemUpdate(query, changes)
        require(status == 0, "keychain_save_failed", "os_status=" + str(status))

    def remove_selftest(self):
        require(self.service.startswith("com.xfit.notion-access.selftest."), "production_credential_delete_not_exposed")
        with self.dictionary(self.selector()) as query:
            status = self.sec.SecItemDelete(query)
        require(status in (0, -25300), "keychain_selftest_cleanup_failed", "os_status=" + str(status))


def read_json(path):
    def unique(pairs):
        document = {}
        for key, value in pairs:
            require(key not in document, "duplicate_json_key")
            document[key] = value
        return document
    def nonfinite(_):
        raise AccessError("non_finite_json")
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=unique, parse_constant=nonfinite)
    except (ValueError, UnicodeError):
        raise AccessError("invalid_json_file") from None


def project_path(value):
    require(isinstance(value, str) and value, "missing_project_path")
    resolved = (ROOT / value).resolve()
    require(ROOT in resolved.parents, "project_path_outside_workspace")
    return resolved


def artifact_output(path):
    resolved = Path(path).resolve()
    directory = ROOT / "artifacts/notion-independent"
    require(directory in resolved.parents, "artifact_output_outside_allowed_directory")
    return resolved


def keychain_selftest():
    """Only an isolated non-Notion sentinel; the production credential is untouched."""
    identifier = str(uuid.uuid4())
    store = KeychainCredential("com.xfit.notion-access.selftest." + identifier, identifier)
    marker = "xfit_non_production_selftest_" + identifier
    created = False
    try:
        require(store.present() is False, "selftest_item_already_exists")
        store.set(marker)
        created = True
        require(store.present() is True and store.get() == marker, "keychain_selftest_readback_differs")
        try:
            store.set(marker + "replacement")
        except AccessError as exc:
            require(exc.code == "credential_exists_use_explicit_replace", "keychain_selftest_replace_guard_failed")
        else:
            raise AccessError("keychain_selftest_replace_guard_failed")
        store.set(marker + "replacement", replace=True)
        require(store.get() == marker + "replacement", "keychain_selftest_readback_differs")
    finally:
        if created:
            store.remove_selftest()
    require(store.present() is False, "keychain_selftest_cleanup_failed")
    return {"status": "PASS", "scope": "isolated_non_production_keychain_item", "roundtrip": "PASS",
            "replace_guard": "PASS", "cleanup": "PASS", "production_credentials_touched": False,
            "remote_calls": 0, "content_writes": 0}


@contextlib.contextmanager
def channel_lock(workspace, runtime_root=None):
    root = Path(runtime_root) if runtime_root is not None else Path.home() / "Library/Application Support/XFit/Notion"
    directory = root / normalized_id(workspace)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / "channel.lock"
    require(not path.is_symlink(), "symlink_lock_refused")
    with os.fdopen(os.open(str(path), os.O_RDWR | os.O_CREAT, 0o600), "a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise AccessError("dedicated_channel_busy") from None
        try:
            yield directory
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def secure_input(dialog=False):
    if dialog:
        require(sys.platform == "darwin", "macos_dialog_required")
        script = 'text returned of (display dialog "这里需要的是 Notion 为 X-Fit Sync 生成的 API 访问令牌，不是你的 Notion 登录密码。若尚未生成令牌，请点取消，不要填写账号密码。已有令牌才粘贴到这里；只在本机验证，正确后保存到系统钥匙串，不会发到聊天或存入项目文件。" with title "X-Fit 程序授权（不是登录）" default answer "" with hidden answer buttons {"取消", "验证后保存"} default button "验证后保存" cancel button "取消")'
        result = subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True, text=True, timeout=600)
        require(result.returncode == 0, "credential_input_cancelled")
        return result.stdout.rstrip("\r\n")
    require(sys.stdin.isatty(), "interactive_input_required", "使用 auth-set --dialog 或在终端执行 auth-set；不要通过聊天或命令参数传凭证。")
    return getpass.getpass("Notion 为 X-Fit Sync 生成的 API 访问令牌（不是登录密码；输入不回显）：")


def public_report(document):
    # Full personal text remains in a private artifact, not routine CLI output.
    return {key: value for key, value in document.items() if key not in ("snapshot", "pages", "verified_binding_candidate")}


def main(argv=None, credential_store=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status", help="本地目标和专用凭证元数据；不联网")
    sub.add_parser("keychain-selftest", help="独立测试项验证Keychain存读／替换护栏／清理，不使用Notion凭证")
    sub.add_parser("doctor", help="只读核验专用凭证、工作区、原库及数据源")
    auth = sub.add_parser("auth-set", help="安全输入凭证；核验正确工作区和原库后保存到Keychain")
    auth.add_argument("--dialog", action="store_true")
    auth.add_argument("--replace", action="store_true")
    snapshot = sub.add_parser("snapshot", help="只读保存完整原档案，文件权限0600")
    snapshot.add_argument("--output", type=Path, required=True)
    preview = sub.add_parser("preview", help="只读取得当前档案并执行原离线预检")
    preview.add_argument("--output", type=Path)
    sync = sub.add_parser("sync", help="只追加明确授权的新档案ID；不PATCH/DELETE旧快照")
    sync.add_argument("--confirm-preview", required=True)
    sync.add_argument("--allow-record", action="append", required=True)
    sync.add_argument("--allow-write", action="store_true")
    sync.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    api = None
    try:
        config = read_json(args.config)
        state = read_json(project_path(config.get("archive_state")))
        DedicatedAccess(config, state, None)
        store = credential_store or KeychainCredential(config["keychain_service"], config["keychain_account"])
        require(normalized_id(config["workspace_id"]) == normalized_id(state["workspace_id"]) == normalized_id(config["keychain_account"]),
                "local_target_mismatch")
        if args.command == "keychain-selftest":
            report = keychain_selftest()
        elif args.command == "status":
            report = {"status": "PASS", "read_only": True, "remote_calls": 0, "workspace_id": config["workspace_id"],
                      "workspace_name": config["workspace_name"], "database_id": state["database_id"],
                      "bound_page_count": len(state["bindings"]), "dedicated_credential_present": store.present(),
                      "writes_enabled": config.get("writes_enabled") is True, "private_parent_page_id": config.get("private_parent_page_id"),
                      "remote_verification": "NOT_RUN"}
        else:
            token = secure_input(args.dialog) if args.command == "auth-set" else store.get()
            api = NotionAPI(token)
            client = DedicatedAccess(config, state, api)
            with channel_lock(config["workspace_id"]) as runtime:
                if args.command in ("doctor", "auth-set"):
                    report = client.doctor()
                    if args.command == "auth-set":
                        store.set(token, replace=args.replace)
                        report.update({"credential_saved": True, "content_writes": 0})
                elif args.command == "snapshot":
                    output = artifact_output(args.output)
                    document = client.snapshot()
                    secure_json(output, document)
                    report = {"status": "PASS", "complete": True, "read_only": True, "page_count": len(document["pages"]),
                              "observed_at": document["observed_at"], "output": str(args.output.resolve())}
                else:
                    output = artifact_output(args.output) if args.output else None
                    records = read_json(project_path(config["archive_records"]))
                    if args.command == "preview":
                        document = client.preview(records)
                    else:
                        journal = WriteJournal(runtime / "write-journal.json")
                        document = client.sync(records, args.confirm_preview, args.allow_record, allow_write=args.allow_write, journal=journal)
                    if output:
                        secure_json(output, document)
                    report = public_report(document)
                    if args.output:
                        report["output"] = str(args.output.resolve())
            report["remote_calls"] = api.remote_calls
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0 if report.get("can_apply", True) else 2
    except AccessError as exc:
        report = {"status": "BLOCKED_ENV", "error": exc.code, "remote_calls": api.remote_calls if api else 0,
                  "content_writes": "unknown" if exc.code.startswith("write_") else "not_claimed"}
        if exc.detail:
            report["detail"] = exc.detail
        if exc.code == "credential_missing":
            report["content_writes"] = 0
            report["next_action"] = "一次创建并授权 X-Fit Sync 后，在本机运行 python3 scripts/xfit-notion-access.py auth-set --dialog。不要把凭证发到聊天。"
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 2
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
        print(json.dumps({"status": "FAIL", "error": "local_io_or_configuration_error", "remote_calls": api.remote_calls if api else 0}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
