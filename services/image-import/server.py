#!/usr/bin/env python3
"""ClassFlow 图片识别开发代理；仅使用 Python 3 标准库，不记录图片或模型正文。"""
import base64
import binascii
import hashlib
import json
import os
import socket
import stat
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from quota import QuotaStore, QuotaError
from budget import CNYBudget, BudgetError, current_pricing, current_cny_balance

ROOT = Path(__file__).resolve().parent
RESOURCE_ROOT = ROOT.parent.parent / "apps/ios/ClassFlow/Resources/AI"
SCHEMA = json.loads((RESOURCE_ROOT / "TimetableAIResponse.schema.json").read_text())
PROMPT = (RESOURCE_ROOT / "TimetableAIPrompt.txt").read_text()
MAX_BODY = 12 * 1024 * 1024
MAX_RESULT = 2 * 1024 * 1024
SLOTS = threading.BoundedSemaphore(2)
_quota_store = None
_quota_lock = threading.Lock()
_money_budget = None
_money_lock = threading.Lock()


def shared_deepseek_key():
    # 显式的空环境变量会禁用本机文件，便于测试及停用；密钥文件不进入源码或补丁。
    if "DEEPSEEK_API_KEY" in os.environ:
        return os.environ["DEEPSEEK_API_KEY"].strip()
    path = Path(os.environ.get("DEEPSEEK_API_KEY_FILE", str(ROOT / "var/deepseek.key")))
    if not path.exists():
        return ""
    if path.is_symlink() or stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise BudgetError(503, "服务端密钥文件权限不正确")
    key = path.read_text().strip()
    if not key or len(key) > 2048 or any(not c.isascii() or c.isspace() for c in key):
        raise BudgetError(503, "服务端密钥文件格式不正确")
    return key


def provider_config():
    deepseek_key = shared_deepseek_key()
    openai_key = os.environ.get("OPENAI_API_KEY", "").strip()
    # 两家的默认地址与凭据分别配对，不能将旧 OpenAI Key 误发给 DeepSeek。
    if deepseek_key or not openai_key:
        return (deepseek_key, os.environ.get("DEEPSEEK_MODEL", "deepseek-flash"),
                os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com"))
    return (openai_key, os.environ.get("OPENAI_MODEL", "gpt-6-astra"),
            os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1"))


def quota_store():
    global _quota_store
    with _quota_lock:
        if _quota_store is None:
            _quota_store = QuotaStore(os.environ.get("CLASSFLOW_AI_DB", str(ROOT / "var/quota.sqlite3")),
                total_call_limit=int(os.environ.get("CLASSFLOW_AI_TOTAL_CALL_LIMIT", "100")),
                per_user_daily_limit=int(os.environ.get("CLASSFLOW_AI_DAILY_CALL_LIMIT", "12")))
    return _quota_store


def money_budget():
    global _money_budget
    with _money_lock:
        if _money_budget is None:
            _money_budget = CNYBudget(quota_store().path, os.environ.get("CLASSFLOW_AI_BUDGET_CNY", "10.00"))
    return _money_budget


class ServiceError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def validate(value, schema):
    """校验本项目使用的 JSON Schema 子集，拒绝模型格式错误或缺字段的结果。"""
    if "anyOf" in schema:
        for alternative in schema["anyOf"]:
            try:
                validate(value, alternative)
                return
            except ValueError:
                pass
        raise ValueError("No matching type")
    kinds = schema["type"]
    kinds = kinds if isinstance(kinds, list) else [kinds]
    kinds_by_type = {str: "string", int: "integer", bool: "boolean", list: "array", dict: "object", type(None): "null"}
    if kinds_by_type.get(type(value)) not in kinds:
        raise ValueError("Incorrect type")
    if "enum" in schema and value not in schema["enum"]:
        raise ValueError("Incorrect enum")
    if value is None:
        return
    if isinstance(value, dict):
        properties = schema["properties"]
        if set(value) != set(schema["required"]) or set(value) - set(properties):
            raise ValueError("Missing or unexpected properties")
        for key, child in value.items():
            validate(child, properties[key])
    if isinstance(value, list):
        if len(value) > schema.get("maxItems", 10000):
            raise ValueError("Too many items")
        for child in value:
            validate(child, schema["items"])
    if isinstance(value, str) and not schema.get("minLength", 0) <= len(value) <= schema.get("maxLength", MAX_RESULT):
        raise ValueError("Incorrect string length")
    if type(value) is int and not schema.get("minimum", value) <= value <= schema.get("maximum", value):
        raise ValueError("Out of range")


def image_request(payload):
    if not isinstance(payload, dict) or set(payload) != {"schemaVersion", "imageBase64", "mimeType", "selectedClass"}:
        raise ServiceError(400, "请求格式不正确")
    if type(payload["schemaVersion"]) is not int or payload["schemaVersion"] != 1:
        raise ServiceError(400, "接口版本不支持")
    selected = payload["selectedClass"]
    if selected is not None and (not isinstance(selected, str) or not selected.strip() or len(selected) > 100):
        raise ServiceError(400, "所选班级不正确")
    encoded = payload["imageBase64"]
    if not isinstance(encoded, str) or len(encoded) > 11200000:
        raise ServiceError(413, "图片过大")
    try:
        image = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise ServiceError(400, "无法读取图片") from None
    mime = payload["mimeType"]
    valid = (mime == "image/jpeg" and image.startswith(b"\xff\xd8\xff")) or (
        mime == "image/png" and image.startswith(b"\x89PNG\r\n\x1a\n")) or (
        mime == "image/webp" and image.startswith(b"RIFF") and image[8:12] == b"WEBP")
    if not valid or not image or len(image) > 8 * 1024 * 1024:
        raise ServiceError(400, "图片格式不支持")
    request = {"model": provider_config()[1], "store": False,
            "max_output_tokens": 8192, "instructions": PROMPT,
            "input": [{"role": "user", "content": [
                {"type": "input_text", "text": json.dumps({"selectedClass": selected}, ensure_ascii=False)},
                {"type": "input_image", "image_url": f"data:{mime};base64,{encoded}", "detail": "high"}]}],
            "text": {"format": {"type": "json_schema", "name": "classflow_timetable", "strict": True, "schema": SCHEMA}}}
    if request["model"].startswith("deepseek-"):
        request["reasoning"] = {"effort": "none"}
    return request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def recognize(payload):
    request_body = image_request(payload)
    key, _, configured_base = provider_config()
    if not key:
        raise ServiceError(503, "请在服务端配置模型密钥")
    base = configured_base.rstrip("/")
    url = urllib.parse.urlsplit(base)
    if not url.hostname or url.username or url.password or url.query or url.fragment or not (
        url.scheme == "https" or (url.scheme == "http" and url.hostname in {"localhost", "127.0.0.1", "::1"})
    ):
        raise ServiceError(503, "服务端模型地址配置不正确")
    # 10 元限制只覆盖已核对人民币计费的官方 Flash，其他提供方不得借此路径绕过预算。
    if base not in {"https://api.deepseek.com", "https://api.deepseek.com/v1"} or request_body["model"] != "deepseek-flash":
        raise BudgetError(503, "共享预算仅支持 DeepSeek 官方 deepseek-flash，请检查服务端配置")
    request = urllib.request.Request(base + "/responses", data=json.dumps(request_body).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"}, method="POST")
    ledger = money_budget()
    pricing = current_pricing()
    balance = current_cny_balance(key)
    money_ticket = ledger.reserve(pricing, balance)
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=90) as response:
            raw = response.read(MAX_RESULT + 1)
        if len(raw) > MAX_RESULT:
            raise ValueError("Oversized response")
        response = json.loads(raw)
        # 拒绝、截断、课程格式错误也可能产生费用，须在校验课程之前结算用量。
        ledger.settle(money_ticket, response.get("usage"))
        if response.get("status") != "completed":
            raise ServiceError(502, "模型未完整返回结果，请重试")
        content = [c for item in response.get("output", []) if item.get("type") == "message" for c in item.get("content", [])]
        if any(c.get("type") == "refusal" for c in content):
            raise ServiceError(422, "模型未能识别该图片，请更换图片或使用本地识别")
        text = "".join(c["text"] for c in content if c.get("type") == "output_text")
        result = json.loads(text)
        validate(result, SCHEMA)
        return result
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        if status == 429:
            raise ServiceError(429, "模型服务繁忙，请稍后重试") from None
        if status in (401, 403):
            raise ServiceError(503, "服务端模型凭据不可用") from None
        raise ServiceError(502, "模型服务暂不可用") from None
    except (TimeoutError, socket.timeout):
        raise ServiceError(504, "模型识别超时") from None
    except (urllib.error.URLError, OSError):
        raise ServiceError(502, "无法连接模型服务") from None
    except (ValueError, KeyError, TypeError, AttributeError):
        raise ServiceError(502, "模型返回的数据格式不正确") from None
    finally:
        # 已结算记录不会被改写；任何未确认用量的调用保留完整费用上界。
        ledger.mark_uncertain(money_ticket)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/v1/usage":
            try:
                usage = quota_store().usage(self.token())
                return self.reply(200, usage)
            except QuotaError as error:
                return self.reply(error.status, {"error": error.message})
        if self.path != "/health":
            return self.reply(404, {"error": "未找到接口"})
        try:
            self.reply(200, {"schemaVersion": 1, "configured": bool(provider_config()[0]), "sharedBudgetCNY": "10.00"})
        except BudgetError as error:
            self.reply(error.status, {"error": error.message, "code": error.code})

    def do_POST(self):
        if self.path != "/v1/timetable":
            return self.reply(404, {"error": "未找到接口"})
        if self.headers.get("Origin"):
            return self.reply(403, {"error": "此开发服务不接受浏览器跨站请求"})
        token = self.token()
        try:
            quota_store().usage(token)
        except QuotaError as error:
            return self.reply(error.status, {"error": error.message})
        if not SLOTS.acquire(blocking=False):
            return self.reply(429, {"error": "服务繁忙"})
        try:
            if self.headers.get_content_type() != "application/json" or self.headers.get("Transfer-Encoding"):
                raise ServiceError(400, "请求格式不正确")
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                raise ServiceError(400, "请求长度不正确") from None
            if not 0 < length <= MAX_BODY:
                raise ServiceError(413, "请求过大")
            self.connection.settimeout(15)
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ServiceError(400, "请求不完整")
            payload = json.loads(raw)
            image_request(payload)
            if not provider_config()[0]:
                raise ServiceError(503, "请在服务端配置模型密钥")
            image_hash = hashlib.sha256(base64.b64decode(payload["imageBase64"])).hexdigest()
            store = quota_store()
            ticket = store.begin(token, self.headers.get("X-ClassFlow-Import-ID", ""), image_hash, payload["selectedClass"])
            if ticket.cached_result is not None:
                result = ticket.cached_result
            else:
                try:
                    result = recognize(payload)
                    store.succeed(ticket, result)
                except BaseException:
                    store.fail(ticket)
                    raise
            self.reply(200, result, usage=store.usage(token))
        except QuotaError as error:
            self.reply(error.status, {"error": error.message}, usage=quota_store().usage(token))
        except BudgetError as error:
            self.reply(error.status, {"error": error.message, "code": error.code}, usage=quota_store().usage(token))
        except ServiceError as error:
            self.reply(error.status, {"error": error.message})
        except (ValueError, UnicodeError):
            self.reply(400, {"error": "请求格式不正确"})
        except (BrokenPipeError, ConnectionResetError, socket.timeout):
            pass
        finally:
            SLOTS.release()

    def token(self):
        authorization = self.headers.get("Authorization", "")
        return authorization[7:] if authorization.startswith("Bearer ") else ""

    def reply(self, status, value, usage=None):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if usage:
            for field in ("limit", "used", "remaining"):
                self.send_header("X-ClassFlow-Trial-" + field.title(), str(usage[field]))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


def main():
    host = os.environ.get("CLASSFLOW_AI_HOST", "127.0.0.1")
    port = int(os.environ.get("CLASSFLOW_AI_PORT", "8787"))
    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    configured = bool(provider_config()[0])
    print(f"ClassFlow AI proxy listening on {host}:{port}; model key configured: {configured}; per-user trials enabled", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
