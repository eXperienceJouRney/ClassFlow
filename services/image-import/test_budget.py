import concurrent.futures
import io
import json
import os
import tempfile
import time
import unittest
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch, Mock
import budget


PRICING_HTML = """<table><tr><th>模型</th><th>deepseek-flash(1)</th><th>deepseek-v4-pro</th></tr>
<tr><td>上下文长度</td><td>1M</td></tr>
<tr><td>价格</td><td>百万tokens输入（缓存命中）</td><td>空闲时段</td><td>0.02元</td><td>0.15元</td></tr>
<tr><td>高峰时段</td><td>0.04元</td><td>0.30元</td></tr>
<tr><td>百万tokens输入（缓存未命中）</td><td>空闲时段</td><td>1元</td><td>4.5元</td></tr>
<tr><td>高峰时段</td><td>2元</td><td>9元</td></tr>
<tr><td>百万tokens输出</td><td>空闲时段</td><td>4元</td><td>13.5元</td></tr>
<tr><td>高峰时段</td><td>8元</td><td>27元</td></tr>
<tr><td>并发限制</td><td>2500</td><td>500</td></tr></table>"""


class MoneyBudgetTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "quota.sqlite3"
        self.ledger = budget.CNYBudget(self.path)
        self.pricing = budget.parse_pricing(PRICING_HTML)

    def tearDown(self):
        self.folder.cleanup()

    def reserve(self):
        return self.ledger.reserve(self.pricing, Decimal("109.84"))

    def test_rates_use_peak_uncached_ceiling_and_whole_context_bound(self):
        self.assertEqual(self.pricing.input_cny_per_million, Decimal("2"))
        self.assertEqual(self.pricing.output_cny_per_million, Decimal("8"))
        self.assertEqual(self.reserve().reserved_micros, 2265536)

    def test_cumulative_cap_blocks_parallel_overspend(self):
        def reserve(_):
            try: return self.reserve()
            except budget.BudgetError as error: return error.status
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            values = list(pool.map(reserve, range(6)))
        self.assertEqual(sum(not isinstance(value, int) for value in values), 4)
        self.assertEqual(values.count(402), 2)
        summary = self.ledger.summary()
        self.assertEqual(summary["heldCeilingCNY"], "9.062144")
        self.assertLessEqual(Decimal(summary["heldCeilingCNY"]), Decimal("10"))

    def test_usage_settlement_returns_only_unused_reservation(self):
        ticket = self.reserve()
        self.ledger.settle(ticket, {"input_tokens": 2000, "output_tokens": 1000})
        self.ledger.settle(ticket, {"input_tokens": 2000, "output_tokens": 1000})
        self.ledger.mark_uncertain(ticket)
        self.assertEqual(self.ledger.summary(), {"limitCNY": "10.000000", "chargedCeilingCNY": "0.012000",
            "heldCeilingCNY": "0.000000", "remainingCNY": "9.988000", "modelRequests": 1})

    def test_restart_preserves_spent_and_uncertain_reservations(self):
        settled = self.reserve()
        self.ledger.settle(settled, {"input_tokens": 2000, "output_tokens": 1000})
        uncertain = self.reserve()
        self.ledger.mark_uncertain(uncertain)
        reloaded = budget.CNYBudget(self.path)
        self.assertEqual(reloaded.summary()["chargedCeilingCNY"], "0.012000")
        self.assertEqual(reloaded.summary()["heldCeilingCNY"], "2.265536")
        self.assertEqual(reloaded.summary()["remainingCNY"], "7.722464")

    def test_missing_or_invalid_usage_cannot_refund_reserved_money(self):
        for usage in [None, {}, {"input_tokens": True, "output_tokens": 10}, {"input_tokens": 10, "output_tokens": 8193}]:
            with self.subTest(usage=usage):
                ticket = self.reserve()
                before = self.ledger.summary()
                with self.assertRaises(budget.BudgetError): self.ledger.settle(ticket, usage)
                self.assertEqual(self.ledger.summary()["heldCeilingCNY"], before["heldCeilingCNY"])

    def test_limit_cannot_exceed_ten_or_reset_by_reconfiguration(self):
        for value in ["10.01", "100", "NaN", "Infinity", "-1"]:
            with self.assertRaises(ValueError): budget.CNYBudget(self.path, value)
        budget.CNYBudget(self.path, "8.00")
        self.assertEqual(budget.CNYBudget(self.path, "10").summary()["limitCNY"], "8.000000")

    def test_price_changes_are_rechecked_and_unknown_formats_stop(self):
        raised = budget.parse_pricing(PRICING_HTML.replace("2元", "20元"))
        with self.assertRaises(budget.BudgetError): self.ledger.reserve(raised, Decimal("100"))
        for text in ["unavailable", PRICING_HTML.replace("1M", "2M"), PRICING_HTML.replace("deepseek-flash", "other-model")]:
            with self.assertRaises(budget.BudgetError): budget.parse_pricing(text)

    def test_expired_verification_and_insufficient_wallet_stop_before_reserving(self):
        expired = budget.Pricing(Decimal("2"), Decimal("8"), time.time() - 100)
        with self.assertRaises(budget.BudgetError): self.ledger.reserve(expired, Decimal("100"))
        with self.assertRaises(budget.BudgetError): self.ledger.reserve(self.pricing, Decimal("0.01"))
        self.assertEqual(self.ledger.summary()["modelRequests"], 0)

    def test_usage_above_verified_model_bound_pauses_new_shared_calls(self):
        ticket = self.reserve()
        with self.assertRaises(budget.BudgetError):
            self.ledger.settle(ticket, {"input_tokens": budget.MAX_INPUT_TOKENS + 1, "output_tokens": 1})
        with self.assertRaises(budget.BudgetError): self.reserve()
        self.assertEqual(self.ledger.summary()["heldCeilingCNY"], "2.265536")

    def test_balance_requires_cny_and_does_not_follow_redirects(self):
        for data, valid in [({"is_available": True, "balance_infos": [{"currency": "CNY", "total_balance": "109.84"}]}, True),
                            ({"is_available": True, "balance_infos": [{"currency": "USD", "total_balance": "100"}]}, False),
                            ({"is_available": True, "balance_infos": [{"currency": "CNY", "total_balance": "NaN"}]}, False)]:
            opener = Mock()
            opener.open.return_value = io.BytesIO(json.dumps(data).encode())
            with patch.object(budget.urllib.request, "build_opener", return_value=opener):
                if valid: self.assertEqual(budget.current_cny_balance("test-key"), Decimal("109.84"))
                else:
                    with self.assertRaises(budget.BudgetError): budget.current_cny_balance("test-key")
            self.assertEqual(opener.open.call_args.args[0].full_url, "https://api.deepseek.com/user/balance")
        self.assertIsNone(budget.NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.com"))


if __name__ == "__main__":
    unittest.main()
