import concurrent.futures
import json
import tempfile
import unittest
import uuid
from pathlib import Path
from quota import QuotaStore, QuotaError


class QuotaTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "quota.sqlite3"
        self.store = QuotaStore(self.path)
        self.token = self.store.issue_user("fixture", 3)
        self.result = {"classes": [], "courses": [{"name": "fixture"}]}

    def tearDown(self):
        self.folder.cleanup()

    def begin(self, workflow=None, selected=None, digest="image-a"):
        return self.store.begin(self.token, workflow or str(uuid.uuid4()), digest, selected)

    def test_success_deducts_once_and_survives_restart(self):
        flow = str(uuid.uuid4())
        ticket = self.begin(flow)
        self.store.succeed(ticket, self.result)
        self.store.succeed(ticket, self.result)
        cached = self.begin(flow)
        self.assertEqual(cached.cached_result, self.result)
        other = QuotaStore(self.path)
        self.assertEqual(other.usage(self.token), {"limit": 3, "used": 1, "remaining": 2})
        self.assertNotIn(self.token, self.path.read_bytes().decode(errors="ignore"))

    def test_class_inspection_and_preview_share_one_trial(self):
        flow = str(uuid.uuid4())
        initial = {"classes": [{"id": "软件1班", "name": "软件1班"}, {"id": "软件2班", "name": "软件2班"}], "courses": []}
        self.store.succeed(self.begin(flow), initial)
        ticket = self.begin(flow, selected="软件1班")
        self.store.succeed(ticket, self.result)
        self.assertEqual(self.store.usage(self.token)["used"], 1)
        with self.assertRaises(QuotaError) as error:
            self.begin(flow, selected="软件2班")
        self.assertEqual(error.exception.status, 409)

    def test_failures_and_empty_results_release_unconsumed_reservation(self):
        ticket = self.begin()
        self.assertEqual(self.store.usage(self.token)["remaining"], 2)
        self.store.fail(ticket)
        self.assertEqual(self.store.usage(self.token)["remaining"], 3)
        self.store.succeed(self.begin(), {"classes": [], "courses": []})
        self.assertEqual(self.store.usage(self.token)["used"], 0)

    def test_user_trials_are_independent_and_fourth_is_rejected(self):
        for _ in range(3):
            self.store.succeed(self.begin(), self.result)
        with self.assertRaises(QuotaError) as error:
            self.begin()
        self.assertEqual(error.exception.status, 402)
        token2 = self.store.issue_user("other fixture")
        self.assertEqual(self.store.usage(token2)["remaining"], 3)

    def test_parallel_requests_cannot_overspend_last_trial(self):
        token = self.store.issue_user("last trial fixture", 1)
        def reserve(_):
            try:
                return self.store.begin(token, str(uuid.uuid4()), "image", None)
            except QuotaError as error:
                return error.status
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            values = list(pool.map(reserve, range(4)))
        self.assertEqual(sum(not isinstance(v, int) for v in values), 1)
        self.assertEqual(values.count(402), 3)

    def test_same_workflow_cannot_change_image_or_run_twice(self):
        flow = str(uuid.uuid4())
        self.begin(flow)
        for digest in ["image-a", "image-b"]:
            with self.assertRaises(QuotaError) as error:
                self.begin(flow, digest=digest)
            self.assertEqual(error.exception.status, 409)

    def test_failed_attempts_are_subject_to_global_spending_cap(self):
        capped = QuotaStore(self.path, total_call_limit=1)
        ticket = capped.begin(self.token, str(uuid.uuid4()), "image", None)
        capped.fail(ticket)
        with self.assertRaises(QuotaError) as error:
            capped.begin(self.token, str(uuid.uuid4()), "image", None)
        self.assertEqual(error.exception.status, 429)
        self.assertEqual(capped.usage(self.token)["used"], 0)

    def test_invalid_credentials_and_unknown_classes_are_rejected(self):
        with self.assertRaises(QuotaError) as error:
            self.store.usage("made-up-token")
        self.assertEqual(error.exception.status, 401)
        with self.assertRaises(QuotaError):
            self.begin("invalid-id")
        flow = str(uuid.uuid4())
        self.store.succeed(self.begin(flow), {"classes": [{"name": "软件1班"}], "courses": []})
        with self.assertRaises(QuotaError):
            self.begin(flow, selected="不存在的班级")


if __name__ == "__main__":
    unittest.main()
