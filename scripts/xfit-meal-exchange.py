#!/usr/bin/env python3
"""Explicit, local Mac ↔ X-Fit exchange. Never opens or writes phone SQLite."""
import argparse
import base64
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

BUNDLE = "com.edward.FitnessApp"


def week_bounds(start):
    day = datetime.date.fromisoformat(start)
    return day.isoformat(), (day + datetime.timedelta(days=6)).isoformat()


def checked_payload(path, approved_sha256):
    data = Path(path).read_bytes()
    if not approved_sha256 or hashlib.sha256(data).hexdigest() != approved_sha256.lower():
        raise ValueError("写入需要已确认结果包的准确 SHA-256；未写手机。")
    json.loads(data)
    return data


def materialize_photos(package, output):
    if package.get("schemaVersion") != 1 or not isinstance(package.get("meals"), list):
        raise ValueError("周包版本或餐食列表无效")
    assets = [asset for meal in package.get("meals", []) for asset in meal.get("photos", [])]
    validated = []
    seen = set()
    for asset in assets:
        attachment = asset["attachment"]
        name = attachment["relativePath"]
        try:
            expected = str(uuid.UUID(attachment["id"])).lower() + ".jpg"
        except (KeyError, ValueError):
            raise ValueError("周包照片标识无效")
        if name != expected or Path(name).name != name:
            raise ValueError("周包照片路径无效")
        if name in seen:
            raise ValueError("周包照片标识重复，未写入")
        seen.add(name)
        data = base64.b64decode(asset["data"], validate=True)
        if len(data) != attachment["byteCount"] or hashlib.sha256(data).hexdigest() != attachment["sha256"]:
            raise ValueError("周包照片完整性校验失败")
        validated.append((name, data))
    output.mkdir(parents=True, exist_ok=True)
    for name, data in validated:
        target = output / name
        if target.exists() and target.read_bytes() != data:
            raise ValueError("输出目录已有不同内容的同名照片，未覆盖")
    for name, data in validated:
        (output / name).write_bytes(data)


def device_command(arguments, receipt):
    # Launch consumes everything after the bundle as app arguments.
    subcommands = 2 if arguments[:2] == ["process", "launch"] else 1
    command = ["xcrun", "devicectl", "device"] + arguments[:subcommands] + \
              ["--timeout", "45", "--json-output", str(receipt)] + arguments[subcommands:]
    completed = subprocess.run(command,
                               capture_output=True, text=True, timeout=55)
    if completed.returncode:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip() or "手机连接不可用")
    result = json.loads(receipt.read_text())
    if result.get("info", {}).get("outcome") == "failed" or "error" in result:
        raise RuntimeError("设备操作失败，请检查设备回执。")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["export", "apply", "notes", "travel-preview", "travel-apply",
                                               "training-preview", "training-apply", "training-readback",
                                               "daily-training-preview", "daily-training-apply", "daily-training-readback",
                                               "historical-correction"])
    parser.add_argument("--device", required=True, help="配对的 iPhone identifier")
    parser.add_argument("--output", required=True, type=Path, help="新的本地结果目录")
    parser.add_argument("--week-start", help="指定周的开始日期 YYYY-MM-DD")
    parser.add_argument("--payload", type=Path)
    parser.add_argument("--approved-sha256", help="本人已确认的写入包 SHA-256")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("--output 必须为新的目录，避免覆盖已有证据")
    operation = {"export": "exportWeek", "apply": "applyReview", "notes": "importNotes",
                 "travel-preview": "previewTravelWeek", "travel-apply": "applyTravelWeek",
                 "training-preview": "previewTrainingPlan", "training-apply": "applyTrainingPlan",
                 "training-readback": "readTrainingPlan", "daily-training-preview": "previewDailyTrainingPlan",
                 "daily-training-apply": "applyDailyTrainingPlan", "daily-training-readback": "readDailyTrainingPlan",
                 "historical-correction": "correctHistoricalExercise"}[args.operation]
    request_id = str(uuid.uuid4())
    request = {"version": 1, "id": request_id, "operation": operation}
    payload = None
    if args.operation == "export":
        if not args.week_start:
            parser.error("export 需要 --week-start")
        request["startLocalDay"], request["endLocalDay"] = week_bounds(args.week_start)
    if args.operation in ("apply", "notes", "travel-apply", "training-preview", "training-apply", "training-readback",
                          "daily-training-preview", "daily-training-apply", "daily-training-readback", "historical-correction"):
        if not args.payload:
            parser.error("此操作需要 --payload 和 --approved-sha256，绑定准确的确认包或预览")
        payload = checked_payload(args.payload, args.approved_sha256)
        request["payloadFileName"] = "meal-payload-" + request_id + ".json"
        request["approvedSHA256"] = hashlib.sha256(payload).hexdigest()
    args.output.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="xfit-meal-exchange-") as temporary:
        folder = Path(temporary)
        if payload is not None:
            local_payload = folder / request["payloadFileName"]
            local_payload.write_bytes(payload)
            device_command(["copy", "to", "--device", args.device, "--source", str(local_payload),
                            "--destination", "Documents/" + local_payload.name, "--domain-type", "appDataContainer",
                            "--domain-identifier", BUNDLE], args.output / "payload-copy.json")
        request_name = "meal-request-" + request_id + ".json"
        request_path = folder / request_name
        request_path.write_text(json.dumps(request, ensure_ascii=False, indent=2))
        (args.output / "request.json").write_bytes(request_path.read_bytes())
        device_command(["copy", "to", "--device", args.device, "--source", str(request_path),
                        "--destination", "Documents/" + request_name, "--domain-type", "appDataContainer",
                        "--domain-identifier", BUNDLE], args.output / "request-copy.json")
        device_command(["process", "launch", "--device", args.device, "--terminate-existing", BUNDLE,
                        "--meal-exchange-request=" + request_name], args.output / "launch.json")
        # The request-bound receipt, not a process exit code, determines success.
        last_error = None
        for attempt in range(12):
            try:
                device_command(["copy", "from", "--device", args.device,
                                "--source", "Documents/MealExchange/" + request_id,
                                "--destination", str(args.output / "result"), "--domain-type", "appDataContainer",
                                "--domain-identifier", BUNDLE], args.output / "result-copy.json")
                receipt_path = args.output / "result" / "receipt.json"
                if receipt_path.exists():
                    receipt = json.loads(receipt_path.read_text())
                    if receipt.get("requestID", "").lower() != request_id.lower():
                        raise ValueError("回执请求标识不匹配")
                    if receipt.get("status") != "completed":
                        raise ValueError(receipt.get("message", "App 未完成操作"))
                    for name in ("week.json", "travel-preview.json", "training-preview.json", "training-readback.json",
                                 "daily-training-preview.json", "daily-training-readback.json"):
                        path = args.output / "result" / name
                        if path.exists():
                            print(name + " SHA-256: " + hashlib.sha256(path.read_bytes()).hexdigest())
                            if name == "week.json":
                                materialize_photos(json.loads(path.read_text()), args.output / "photos")
                    print(receipt.get("message", "已完成并回读回执"))
                    return
            except RuntimeError as error:
                last_error = error
            if attempt < 11:
                time.sleep(2)
        raise RuntimeError("未取得完成回执；不能视为写入成功。可重试同一数据包并回读，勿重新造记录。" + str(last_error or ""))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))
