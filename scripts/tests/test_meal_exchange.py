import importlib.util
from pathlib import Path
import tempfile
import unittest
import base64
import uuid
import json
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("meal_exchange", Path(__file__).parents[1] / "xfit-meal-exchange.py")
exchange = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exchange)


class MealExchangeTests(unittest.TestCase):
    def test_confirmed_training_commands_require_exact_payload_and_bind_app_receipt(self):
        operations = {
            "training-preview": "previewTrainingPlan",
            "training-apply": "applyTrainingPlan",
            "training-readback": "readTrainingPlan",
            "daily-training-preview": "previewDailyTrainingPlan",
            "daily-training-apply": "applyDailyTrainingPlan",
            "daily-training-readback": "readDailyTrainingPlan",
        }
        for command, operation in operations.items():
            with self.subTest(command=command), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                payload = root / "confirmed.json"
                payload.write_text('{"confirmedFixture":true}')
                digest = exchange.hashlib.sha256(payload.read_bytes()).hexdigest()
                output = root / "result"

                def device_boundary(arguments, receipt):
                    if arguments[:2] == ["copy", "from"]:
                        request = json.loads((output / "request.json").read_text())
                        self.assertEqual(request["operation"], operation)
                        self.assertEqual(request["approvedSHA256"], digest)
                        result = output / "result"
                        result.mkdir()
                        (result / "receipt.json").write_text(json.dumps({
                            "requestID": request["id"], "status": "completed", "message": "isolated transport fixture"
                        }))
                    return {}

                arguments = ["xfit-meal-exchange.py", command, "--device", "isolated-device", "--output", str(output),
                             "--payload", str(payload), "--approved-sha256", digest]
                with patch.object(sys, "argv", arguments), patch.object(exchange, "device_command", side_effect=device_boundary):
                    exchange.main()

    def test_write_requires_exact_fresh_confirmation_digest(self):
        with tempfile.TemporaryDirectory() as folder:
            payload = Path(folder) / "review.json"
            payload.write_text('{"schemaVersion":1}')
            with self.assertRaises(ValueError):
                exchange.checked_payload(payload, None)
            with self.assertRaises(ValueError):
                exchange.checked_payload(payload, "0" * 64)
            expected = exchange.hashlib.sha256(payload.read_bytes()).hexdigest()
            self.assertEqual(exchange.checked_payload(payload, expected), payload.read_bytes())

    def test_export_week_is_exact_seven_civil_days(self):
        self.assertEqual(exchange.week_bounds("2026-09-21"), ("2026-09-21", "2026-09-27"))
        with self.assertRaises(ValueError):
            exchange.week_bounds("2026-02-30")

    def test_photo_materialization_rejects_traversal_before_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                exchange.materialize_photos({"schemaVersion": 1, "meals": [{"photos": [{"attachment": {"relativePath": "../bad.jpg"}, "data": ""}]}]}, Path(folder))
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_nested_week_photos_materialize_and_reject_duplicate_identity(self):
        data = b"fixture-photo-bytes"
        identity = str(uuid.uuid4())
        name = identity + ".jpg"
        asset = {"attachment": {"id": identity, "relativePath": name,
                 "byteCount": len(data), "sha256": exchange.hashlib.sha256(data).hexdigest()},
                 "data": base64.b64encode(data).decode()}
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "good"
            exchange.materialize_photos({"schemaVersion": 1, "meals": [{"photos": [asset]}]}, output)
            self.assertEqual((output / name).read_bytes(), data)
            with self.assertRaises(ValueError):
                exchange.materialize_photos({"schemaVersion": 1, "meals": [{"photos": [asset, asset]}]}, Path(folder) / "bad")
            self.assertFalse((Path(folder) / "bad").exists())


if __name__ == "__main__":
    unittest.main()
