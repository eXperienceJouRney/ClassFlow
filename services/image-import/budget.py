"""共享 DeepSeek 调用的人民币预算；先预占最坏费用，再按用量保守结算。"""
import json
import re
import sqlite3
import time
import urllib.error
import urllib.request
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_CEILING
from html.parser import HTMLParser
from pathlib import Path

MICROS = 1_000_000
MAX_BUDGET_CNY = Decimal("10.00")
PRICING_URL = "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/"
BALANCE_URL = "https://api.deepseek.com/user/balance"
# 官方当前上下文为 1M，向上留出余量，覆盖十进制与二进制 M 的表示。
MAX_INPUT_TOKENS = 1_100_000
MAX_OUTPUT_TOKENS = 8192


class BudgetError(Exception):
    def __init__(self, status, message, code="SHARED_BUDGET_UNAVAILABLE"):
        self.status, self.message, self.code = status, message, code


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class PricingRows(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], None, None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        if tag in ("td", "th") and self.row is not None:
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell is not None:
            self.row.append("".join(self.cell).strip())
            self.cell = None
        if tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None


@dataclass(frozen=True)
class Pricing:
    input_cny_per_million: Decimal
    output_cny_per_million: Decimal
    checked_at: float

    def ceiling_micros(self, inputs, outputs):
        # 每百万 token 的元价 × token 数，正好是微元；向上取整避免浮点误差。
        return int((Decimal(inputs) * self.input_cny_per_million
                    + Decimal(outputs) * self.output_cny_per_million).to_integral_value(rounding=ROUND_CEILING))

    def record(self):
        return {"inputCNYPerMillion": str(self.input_cny_per_million),
                "outputCNYPerMillion": str(self.output_cny_per_million),
                "checkedAt": self.checked_at, "source": PRICING_URL}


def parse_pricing(html):
    parser = PricingRows()
    parser.feed(html)
    header = next((i for i, row in enumerate(parser.rows)
                   if len(row) >= 3 and row[0] == "模型" and row[1].startswith("deepseek-flash")), None)
    if header is None:
        raise BudgetError(503, "无法核实 DeepSeek 人民币价格，已暂停共享 AI 调用")
    rates = {"cached": [], "input": [], "output": []}
    context_ok = False
    mode = None
    for row in parser.rows[header + 1:]:
        if not row:
            continue
        text = "".join(row)
        if row[0] == "上下文长度":
            context_ok = len(row) == 2 and row[1] == "1M"
        if "并发限制" in text:
            break
        if "缓存未命中" in text:
            mode = "input"
        elif "缓存命中" in text:
            mode = "cached"
        elif "百万tokens输出" in text:
            mode = "output"
        prices = [Decimal(match.group(1)) for cell in row
                  if (match := re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)元", cell))]
        if mode and prices and ("高峰时段" in text or "空闲时段" in text):
            rates[mode].append(prices[0])
    if not context_ok or any(len(values) != 2 for values in rates.values()):
        raise BudgetError(503, "DeepSeek 价格或上下文格式发生变化，需核对后再开放共享 AI")
    input_rate = max(rates["cached"] + rates["input"])
    output_rate = max(rates["output"])
    if not input_rate.is_finite() or not output_rate.is_finite() or min(input_rate, output_rate) <= 0:
        raise BudgetError(503, "DeepSeek 计费信息无效，已暂停共享 AI 调用")
    return Pricing(input_rate, output_rate, time.time())


def current_pricing():
    request = urllib.request.Request(PRICING_URL, headers={"User-Agent": "ClassFlow-budget-check/1.0"})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=12) as response:
            raw = response.read(2_000_001)
        if len(raw) > 2_000_000:
            raise ValueError()
        return parse_pricing(raw.decode("utf-8"))
    except BudgetError:
        raise
    except urllib.error.HTTPError as error:
        error.close()
        raise BudgetError(503, "暂时无法核实官方价格，已暂停共享 AI 调用") from None
    except (OSError, ValueError, UnicodeError):
        raise BudgetError(503, "暂时无法核实官方价格，已暂停共享 AI 调用") from None


def current_cny_balance(key):
    # 密钥仅用于官方 API 域名，价格文档请求不携带 Authorization。
    request = urllib.request.Request(BALANCE_URL, headers={"Authorization": "Bearer " + key, "Accept": "application/json"})
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=12) as response:
            raw = response.read(65537)
        if len(raw) > 65536:
            raise ValueError()
        value = json.loads(raw)
        balances = [b for b in value["balance_infos"] if b["currency"] == "CNY"]
        if value["is_available"] is not True or len(balances) != 1:
            raise ValueError()
        amount = Decimal(balances[0]["total_balance"])
        if not amount.is_finite() or amount < 0:
            raise ValueError()
        return amount
    except urllib.error.HTTPError as error:
        error.close()
        raise BudgetError(503, "无法确认共享 DeepSeek 账户人民币余额，请检查服务端配置") from None
    except (OSError, ValueError, KeyError, TypeError, InvalidOperation):
        raise BudgetError(503, "无法确认共享 DeepSeek 账户人民币余额，请检查服务端配置") from None


@dataclass(frozen=True)
class MoneyTicket:
    id: str
    reserved_micros: int
    pricing: Pricing


class CNYBudget:
    def __init__(self, path, limit_cny="10.00"):
        try:
            limit = Decimal(str(limit_cny))
            if not limit.is_finite() or limit < 0 or limit > MAX_BUDGET_CNY:
                raise ValueError()
            micros = int(limit * MICROS)
        except (ValueError, InvalidOperation):
            raise ValueError("共享预算必须在 0 至 10 元之间") from None
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connection() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS money_budget (
                    id INTEGER PRIMARY KEY CHECK(id=1), limit_micros INTEGER NOT NULL,
                    frozen INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS money_calls (
                    id TEXT PRIMARY KEY, reserved_micros INTEGER NOT NULL, charged_micros INTEGER,
                    state TEXT NOT NULL, input_tokens INTEGER, output_tokens INTEGER,
                    pricing TEXT NOT NULL, reason TEXT, created REAL NOT NULL, completed REAL);
            """)
        with self.transaction() as db:
            db.execute("INSERT OR IGNORE INTO money_budget(id,limit_micros) VALUES (1,?)", (micros,))
            # 重启、换 Key、调高环境变量都不会恢复已用额度或提高已保存的上限。
            db.execute("UPDATE money_budget SET limit_micros=MIN(limit_micros,?) WHERE id=1", (micros,))

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=15, isolation_level=None)
        db.row_factory = sqlite3.Row
        try:
            yield db
        finally:
            db.close()

    @contextmanager
    def transaction(self):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            try:
                yield db
                db.commit()
            except BaseException:
                db.rollback()
                raise

    def reserve(self, pricing, available_cny):
        if not 0 <= time.time() - pricing.checked_at <= 60:
            raise BudgetError(503, "计费核验已过期，请重试")
        reservation = pricing.ceiling_micros(MAX_INPUT_TOKENS, MAX_OUTPUT_TOKENS)
        if not available_cny.is_finite() or available_cny < Decimal(reservation) / MICROS:
            raise BudgetError(402, "共享账户余额不足以安全预留本次费用，请使用自己的 Key", "SHARED_BUDGET_EXHAUSTED")
        with self.transaction() as db:
            account = db.execute("SELECT * FROM money_budget WHERE id=1").fetchone()
            obligations = db.execute("SELECT COALESCE(SUM(CASE WHEN state='settled' THEN charged_micros ELSE reserved_micros END),0) FROM money_calls").fetchone()[0]
            if account["frozen"] or obligations + reservation > account["limit_micros"]:
                raise BudgetError(402, "共享 AI 的 10 元预算已达到安全限额，请使用自己的 Key", "SHARED_BUDGET_EXHAUSTED")
            identifier = str(uuid.uuid4())
            db.execute("INSERT INTO money_calls(id,reserved_micros,state,pricing,created) VALUES (?,?,'reserved',?,?)",
                       (identifier, reservation, json.dumps(pricing.record()), time.time()))
        return MoneyTicket(identifier, reservation, pricing)

    def settle(self, ticket, usage):
        valid = isinstance(usage, dict)
        inputs = usage.get("input_tokens") if valid else None
        outputs = usage.get("output_tokens") if valid else None
        valid = type(inputs) is int and type(outputs) is int and 0 <= inputs <= MAX_INPUT_TOKENS and 0 <= outputs <= MAX_OUTPUT_TOKENS
        if not valid:
            self.mark_uncertain(ticket, "missing_or_invalid_usage")
            if type(inputs) is int and type(outputs) is int:
                with self.transaction() as db:
                    db.execute("UPDATE money_budget SET frozen=1 WHERE id=1")
            raise BudgetError(503, "模型未返回可核实用量，费用已保守预留，请服务维护者核对")
        charge = ticket.pricing.ceiling_micros(inputs, outputs)
        if charge > ticket.reserved_micros:
            self.mark_uncertain(ticket, "usage_above_reservation")
            with self.transaction() as db:
                db.execute("UPDATE money_budget SET frozen=1 WHERE id=1")
            raise BudgetError(503, "模型用量超出已核准上限，已暂停共享 AI")
        with self.transaction() as db:
            db.execute("UPDATE money_calls SET state='settled', charged_micros=?, input_tokens=?, output_tokens=?, completed=? WHERE id=? AND state='reserved'",
                       (charge, inputs, outputs, time.time(), ticket.id))

    def mark_uncertain(self, ticket, reason="unconfirmed_upstream_charge"):
        with self.transaction() as db:
            db.execute("UPDATE money_calls SET state='uncertain', reason=?, completed=? WHERE id=? AND state='reserved'",
                       (reason, time.time(), ticket.id))

    def summary(self):
        with self.connection() as db:
            account = db.execute("SELECT * FROM money_budget WHERE id=1").fetchone()
            charged, held, calls = db.execute("""SELECT
                COALESCE(SUM(CASE WHEN state='settled' THEN charged_micros ELSE 0 END),0),
                COALESCE(SUM(CASE WHEN state!='settled' THEN reserved_micros ELSE 0 END),0), COUNT(*) FROM money_calls""").fetchone()
            def cny(micros):
                return str((Decimal(micros) / MICROS).quantize(Decimal("0.000001")))
            return {"limitCNY": cny(account["limit_micros"]), "chargedCeilingCNY": cny(charged),
                    "heldCeilingCNY": cny(held), "remainingCNY": cny(max(0, account["limit_micros"] - charged - held)),
                    "modelRequests": calls}
