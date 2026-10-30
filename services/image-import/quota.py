"""服务端试用额度：独立试用码、事务预占、流程幂等与共享调用上限。"""
import hashlib
import json
import secrets
import sqlite3
import time
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path


class QuotaError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


@dataclass(frozen=True)
class Ticket:
    user_id: str
    workflow: str
    stage: str
    cached_result: dict | None = None


class QuotaStore:
    def __init__(self, path, total_call_limit=100, per_user_daily_limit=12):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.total_call_limit = total_call_limit
        self.per_user_daily_limit = per_user_daily_limit
        with self.connection() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
                    free_limit INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1);
                CREATE TABLE IF NOT EXISTS jobs (
                    user_id TEXT NOT NULL REFERENCES users(id), workflow TEXT NOT NULL, image_hash TEXT NOT NULL,
                    charged INTEGER NOT NULL DEFAULT 0, selected_class TEXT, expires REAL NOT NULL,
                    PRIMARY KEY(user_id, workflow));
                CREATE TABLE IF NOT EXISTS steps (
                    user_id TEXT NOT NULL, workflow TEXT NOT NULL, stage TEXT NOT NULL,
                    state TEXT NOT NULL, attempts INTEGER NOT NULL, result TEXT,
                    PRIMARY KEY(user_id, workflow, stage),
                    FOREIGN KEY(user_id, workflow) REFERENCES jobs(user_id, workflow) ON DELETE CASCADE);
                CREATE TABLE IF NOT EXISTS attempts (user_id TEXT NOT NULL, day INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS attempts_user_day ON attempts(user_id, day);
            """)

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        try:
            yield db
        finally:
            db.close()

    @contextmanager
    def transaction(self):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            try:
                db.execute("DELETE FROM jobs WHERE expires < ?", (time.time(),))
                yield db
                db.commit()
            except BaseException:
                db.rollback()
                raise

    def issue_user(self, name, free_uses=3):
        if not name.strip() or not 0 <= free_uses <= 100:
            raise ValueError("姓名不能为空，试用次数须在 0...100 内")
        token = secrets.token_urlsafe(32)
        with self.transaction() as db:
            db.execute("INSERT INTO users(id, token_hash, name, free_limit) VALUES (?,?,?,?)",
                       (str(uuid.uuid4()), hashlib.sha256(token.encode()).hexdigest(), name.strip(), free_uses))
        return token

    def user(self, db, token):
        if not token or len(token) > 2048:
            raise QuotaError(401, "请填写个人试用码")
        user = db.execute("SELECT * FROM users WHERE token_hash=? AND active=1",
                          (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
        if user is None:
            raise QuotaError(401, "试用码无效或已停用")
        return user

    def usage(self, token):
        with self.transaction() as db:
            user = self.user(db, token)
            reserved = db.execute("SELECT COUNT(*) FROM jobs WHERE user_id=? AND charged=0", (user["id"],)).fetchone()[0]
            return {"limit": user["free_limit"], "used": user["used"],
                    "remaining": max(0, user["free_limit"] - user["used"] - reserved)}

    def begin(self, token, workflow, image_hash, selected_class):
        try:
            if str(uuid.UUID(workflow)) != workflow.lower():
                raise ValueError()
        except (ValueError, AttributeError, TypeError):
            raise QuotaError(400, "缺少有效的图片识别流程编号") from None
        stage = "inspect" if selected_class is None else "class:" + selected_class
        with self.transaction() as db:
            user = self.user(db, token)
            user_id = user["id"]
            job = db.execute("SELECT * FROM jobs WHERE user_id=? AND workflow=?", (user_id, workflow)).fetchone()
            if job and job["image_hash"] != image_hash:
                raise QuotaError(409, "同一次识别不能更换图片，请重新选择图片")
            if job is None:
                if selected_class is not None:
                    raise QuotaError(409, "识别已过期，请重新识别并选择班级")
                reserved = db.execute("SELECT COUNT(*) FROM jobs WHERE user_id=? AND charged=0", (user_id,)).fetchone()[0]
                if user["used"] + reserved >= user["free_limit"]:
                    raise QuotaError(402, "免费 AI 次数已用完，请使用自己的 DeepSeek API Key")
                db.execute("INSERT INTO jobs(user_id,workflow,image_hash,expires) VALUES (?,?,?,?)",
                           (user_id, workflow, image_hash, time.time() + 1800))
            if selected_class is not None:
                initial = db.execute("SELECT result FROM steps WHERE user_id=? AND workflow=? AND stage='inspect' AND state='succeeded'",
                                     (user_id, workflow)).fetchone()
                if initial is None or selected_class not in {c["name"] for c in json.loads(initial["result"])["classes"]}:
                    raise QuotaError(400, "请从本次识别到的班级中选择")
                if job["selected_class"] not in (None, selected_class):
                    raise QuotaError(409, "本次已识别其他班级，请开始新的识别流程")
                db.execute("UPDATE jobs SET selected_class=? WHERE user_id=? AND workflow=?", (selected_class, user_id, workflow))
            previous = db.execute("SELECT * FROM steps WHERE user_id=? AND workflow=? AND stage=?", (user_id, workflow, stage)).fetchone()
            if previous and previous["state"] == "succeeded":
                return Ticket(user_id, workflow, stage, json.loads(previous["result"]))
            if previous and previous["state"] == "running":
                raise QuotaError(409, "这张图片正在识别，请稍后重试")
            if previous and previous["attempts"] >= 3:
                raise QuotaError(429, "本次识别重试过多，请稍后开始新的识别")
            total = db.execute("SELECT COUNT(*) FROM attempts").fetchone()[0]
            if total >= self.total_call_limit:
                raise QuotaError(429, "试用服务总额度已用完，可使用自己的 DeepSeek API Key")
            day = int(time.time() // 86400)
            daily = db.execute("SELECT COUNT(*) FROM attempts WHERE user_id=? AND day=?", (user_id, day)).fetchone()[0]
            if daily >= self.per_user_daily_limit:
                raise QuotaError(429, "今日 AI 请求过多，请稍后重试或使用自己的 Key")
            db.execute("INSERT INTO attempts(user_id,day) VALUES (?,?)", (user_id, day))
            db.execute("""INSERT INTO steps(user_id,workflow,stage,state,attempts) VALUES (?,?,?,'running',1)
                ON CONFLICT(user_id,workflow,stage) DO UPDATE SET state='running', attempts=attempts+1, result=NULL""",
                (user_id, workflow, stage))
            return Ticket(user_id, workflow, stage)

    def succeed(self, ticket, result):
        if not result["classes"] and not result["courses"]:
            self.fail(ticket)
            return
        with self.transaction() as db:
            job = db.execute("SELECT charged FROM jobs WHERE user_id=? AND workflow=?", (ticket.user_id, ticket.workflow)).fetchone()
            if job is None:
                raise QuotaError(409, "本次识别已过期，请重试")
            if not job["charged"]:
                db.execute("UPDATE users SET used=used+1 WHERE id=?", (ticket.user_id,))
                db.execute("UPDATE jobs SET charged=1 WHERE user_id=? AND workflow=?", (ticket.user_id, ticket.workflow))
            db.execute("UPDATE steps SET state='succeeded', result=? WHERE user_id=? AND workflow=? AND stage=?",
                       (json.dumps(result, ensure_ascii=False), ticket.user_id, ticket.workflow, ticket.stage))

    def fail(self, ticket):
        with self.transaction() as db:
            db.execute("UPDATE steps SET state='failed', result=NULL WHERE user_id=? AND workflow=? AND stage=?",
                       (ticket.user_id, ticket.workflow, ticket.stage))
            db.execute("DELETE FROM jobs WHERE user_id=? AND workflow=? AND charged=0", (ticket.user_id, ticket.workflow))

    def users(self):
        with self.connection() as db:
            return [dict(row) for row in db.execute("SELECT name,free_limit,used,active FROM users ORDER BY name")]
