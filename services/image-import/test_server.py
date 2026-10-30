import base64
import copy
import io
import json
import os
import threading
import tempfile
import uuid
import time
from decimal import Decimal
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from unittest.mock import patch

import server
from quota import QuotaStore
from budget import CNYBudget, Pricing, BudgetError


def result():
    return {"schemaVersion": 1, "classes": [], "displayedWeek": None, "warnings": [], "courses": [{
        "name": "离散数学", "teacher": None, "location": "理科楼B201", "weekday": 1,
        "startPeriod": 1, "endPeriod": 2, "startTime": None, "endTime": None,
        "weeks": [1, 3, 5, 7, 9], "isCurrentWeek": None, "scope": "personal", "classIDs": [],
        "classGroup": None, "requiresReview": False, "notes": [], "sourceText": "离散数学 1-10周（单周）"}]}


def payload():
    # 仅验证传输契约；不是模型识别的真实图片夹具。
    return {"schemaVersion": 1, "imageBase64": base64.b64encode(b"\xff\xd8\xfftest").decode(),
            "mimeType": "image/jpeg", "selectedClass": None}


def upstream(value=None, status="completed"):
    return {"status": status, "usage": {"input_tokens": 2000, "output_tokens": 1000}, "output": [{"type": "message", "content": [
        {"type": "output_text", "text": json.dumps(value if value is not None else result())}]}]}


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.ledger = unittest.mock.Mock()
        for name, value in [("money_budget", self.ledger),
                            ("current_pricing", Pricing(Decimal("2"), Decimal("8"), time.time())),
                            ("current_cny_balance", Decimal("100"))]:
            patcher = patch.object(server, name, return_value=value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_request_uses_image_and_strict_schema_without_storage(self):
        p = payload()
        p["selectedClass"] = "计算机2603班"
        request = server.image_request(p)
        self.assertFalse(request["store"])
        self.assertTrue(request["text"]["format"]["strict"])
        self.assertEqual(request["text"]["format"]["schema"], server.SCHEMA)
        content = request["input"][0]["content"]
        self.assertEqual(json.loads(content[0]["text"])["selectedClass"], "计算机2603班")
        self.assertTrue(content[1]["image_url"].startswith("data:image/jpeg;base64,"))

    def test_provider_credentials_keep_their_own_default_destination(self):
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "", "OPENAI_API_KEY": "openai-test-key",
                                   "OPENAI_BASE_URL": "https://api.openai.com/v1", "OPENAI_MODEL": "gpt-6-astra"}):
            key, model, base = server.provider_config()
            self.assertEqual((key, model, base), ("openai-test-key", "gpt-6-astra", "https://api.openai.com/v1"))
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "deepseek-test-key", "OPENAI_API_KEY": "openai-test-key",
                                   "DEEPSEEK_BASE_URL": "https://api.deepseek.com", "DEEPSEEK_MODEL": "deepseek-flash"}):
            self.assertEqual(server.provider_config(), ("deepseek-test-key", "deepseek-flash", "https://api.deepseek.com"))

    def test_input_rejects_invalid_images_and_unexpected_fields(self):
        for changed in [{"imageBase64": "not base64"}, {"mimeType": "image/png"}, {"schemaVersion": True},
                        {"selectedClass": ""}, {"url": "https://example.com/private"}]:
            with self.subTest(changed=changed), self.assertRaises(server.ServiceError):
                server.image_request(payload() | changed)

    def test_schema_requires_all_fields_and_exact_types(self):
        server.validate(result(), server.SCHEMA)
        for transform in [lambda r: r["courses"][0].pop("weeks"),
                          lambda r: r["courses"][0].update(weekday=True),
                          lambda r: r["courses"][0].update(weeks=[0]),
                          lambda r: r.update(extra="unexpected"),
                          lambda r: r["courses"][0].update(scope="guessed")]:
            invalid = copy.deepcopy(result())
            transform(invalid)
            with self.assertRaises(ValueError):
                server.validate(invalid, server.SCHEMA)

    @patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-key", "DEEPSEEK_BASE_URL": "https://api.deepseek.com"})
    def test_completed_structured_result(self):
        opener = unittest.mock.Mock()
        opener.open.return_value = io.BytesIO(json.dumps(upstream()).encode())
        with patch.object(server.urllib.request, "build_opener", return_value=opener):
            self.assertEqual(server.recognize(payload()), result())
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.deepseek.com/responses")
        self.assertEqual(request.get_header("Authorization"), "Bearer test-only-key")

    @patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-key"})
    def test_refusals_incomplete_and_malformed_outputs_rejected(self):
        refused = {"status": "completed", "output": [{"type": "message", "content": [{"type": "refusal"}]}]}
        for response, status in [(upstream(status="incomplete"), 502), (refused, 422), (upstream({}), 502)]:
            opener = unittest.mock.Mock()
            opener.open.return_value = io.BytesIO(json.dumps(response).encode())
            with patch.object(server.urllib.request, "build_opener", return_value=opener):
                with self.assertRaises(server.ServiceError) as error:
                    server.recognize(payload())
                self.assertEqual(error.exception.status, status)

    @patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-key"})
    def test_provider_errors_do_not_expose_response_body(self):
        for upstream_status, expected in [(401, 503), (429, 429), (500, 502)]:
            opener = unittest.mock.Mock()
            opener.open.side_effect = urllib.error.HTTPError("https://api.openai.com", upstream_status,
                "secret-provider-message", {}, io.BytesIO(b"sensitive upstream detail"))
            with patch.object(server.urllib.request, "build_opener", return_value=opener):
                with self.assertRaises(server.ServiceError) as error:
                    server.recognize(payload())
                self.assertEqual(error.exception.status, expected)
                self.assertNotIn("secret", error.exception.message)

    @patch.dict(os.environ, {"DEEPSEEK_API_KEY": "", "OPENAI_API_KEY": ""})
    def test_missing_key_is_configuration_error(self):
        with self.assertRaises(server.ServiceError) as error:
            server.recognize(payload())
        self.assertEqual(error.exception.status, 503)

    @patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-key", "DEEPSEEK_BASE_URL": "https://api.deepseek.com", "DEEPSEEK_MODEL": "deepseek-flash"})
    def test_real_budget_settles_usage_even_if_courses_are_invalid(self):
        for response, expected_error in [(upstream(), False), (upstream({}), True)]:
            with tempfile.TemporaryDirectory() as folder:
                ledger = CNYBudget(os.path.join(folder, "money.sqlite3"))
                opener = unittest.mock.Mock()
                opener.open.return_value = io.BytesIO(json.dumps(response).encode())
                with patch.object(server, "money_budget", return_value=ledger), patch.object(server.urllib.request, "build_opener", return_value=opener):
                    if expected_error:
                        with self.assertRaises(server.ServiceError): server.recognize(payload())
                    else:
                        server.recognize(payload())
                self.assertEqual(ledger.summary()["chargedCeilingCNY"], "0.012000")
                self.assertEqual(ledger.summary()["heldCeilingCNY"], "0.000000")

    @patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-key", "DEEPSEEK_BASE_URL": "https://api.deepseek.com", "DEEPSEEK_MODEL": "deepseek-flash"})
    def test_budget_exhaustion_blocks_model_request_before_sending(self):
        self.ledger.reserve.side_effect = BudgetError(402, "预算已用完", "SHARED_BUDGET_EXHAUSTED")
        with patch.object(server.urllib.request, "build_opener") as opener:
            with self.assertRaises(BudgetError): server.recognize(payload())
            opener.assert_not_called()

    @patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-key", "DEEPSEEK_BASE_URL": "https://api.deepseek.com", "DEEPSEEK_MODEL": "deepseek-flash"})
    def test_timeout_keeps_reserved_money(self):
        opener = unittest.mock.Mock()
        opener.open.side_effect = TimeoutError()
        with patch.object(server.urllib.request, "build_opener", return_value=opener):
            with self.assertRaises(server.ServiceError): server.recognize(payload())
        self.ledger.mark_uncertain.assert_called_once()
        self.ledger.settle.assert_not_called()

    def test_http_auth_origin_and_success_contract(self):
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{httpd.server_port}/v1/timetable"
        try:
            with tempfile.TemporaryDirectory() as folder:
                store = QuotaStore(os.path.join(folder, "quota.sqlite3"))
                token = store.issue_user("HTTP fixture")
                with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-key"}), patch.object(server, "quota_store", return_value=store), patch.object(server, "recognize", return_value=result()) as recognize:
                    def send(headers, workflow):
                        return urllib.request.urlopen(urllib.request.Request(url, data=json.dumps(payload()).encode(),
                            headers={"Content-Type": "application/json", "X-ClassFlow-Import-ID": workflow} | headers), timeout=2)
                    for headers, expected in [({}, 401), ({"Authorization": "Bearer " + token, "Origin": "https://example.com"}, 403)]:
                        with self.assertRaises(urllib.error.HTTPError) as error:
                            send(headers, str(uuid.uuid4()))
                        self.assertEqual(error.exception.code, expected)
                        error.exception.close()
                    recognize.assert_not_called()
                    workflow = str(uuid.uuid4())
                    with send({"Authorization": "Bearer " + token}, workflow) as response:
                        self.assertEqual(response.headers["Cache-Control"], "no-store")
                        self.assertEqual(json.load(response), result())
                    with send({"Authorization": "Bearer " + token}, workflow) as response:
                        self.assertEqual(response.headers["X-ClassFlow-Trial-Remaining"], "2")
                        self.assertEqual(json.load(response), result())
                    recognize.assert_called_once()
                    for _ in range(2):
                        with send({"Authorization": "Bearer " + token}, str(uuid.uuid4())) as response:
                            self.assertEqual(response.status, 200)
                    with self.assertRaises(urllib.error.HTTPError) as error:
                        send({"Authorization": "Bearer " + token}, str(uuid.uuid4()))
                    self.assertEqual(error.exception.code, 402)
                    error.exception.close()
                    self.assertEqual(recognize.call_count, 3)
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join(timeout=2)

    def test_http_shared_budget_stop_preserves_personal_trial_count(self):
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as folder:
                store = QuotaStore(os.path.join(folder, "quota.sqlite3"))
                token = store.issue_user("budget fixture")
                error = BudgetError(402, "共享预算已用完", "SHARED_BUDGET_EXHAUSTED")
                with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-key"}), patch.object(server, "quota_store", return_value=store), patch.object(server, "recognize", side_effect=error):
                    request = urllib.request.Request(f"http://127.0.0.1:{httpd.server_port}/v1/timetable",
                        data=json.dumps(payload()).encode(), headers={"Content-Type": "application/json",
                        "Authorization": "Bearer " + token, "X-ClassFlow-Import-ID": str(uuid.uuid4())})
                    with self.assertRaises(urllib.error.HTTPError) as caught:
                        urllib.request.urlopen(request, timeout=2)
                    response = caught.exception
                    self.assertEqual(response.code, 402)
                    self.assertEqual(response.headers["X-ClassFlow-Trial-Remaining"], "3")
                    self.assertEqual(json.load(response)["code"], "SHARED_BUDGET_EXHAUSTED")
                    response.close()
                self.assertEqual(store.usage(token)["used"], 0)
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
