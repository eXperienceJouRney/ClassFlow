#!/usr/bin/env python3
"""仅供服务维护者在本机发放试用码，不提供公开注册或补充次数接口。"""
import argparse
import json
import os
from pathlib import Path
from quota import QuotaStore
from budget import CNYBudget


def main():
    parser = argparse.ArgumentParser(description="管理 ClassFlow AI 试用")
    sub = parser.add_subparsers(dest="command", required=True)
    add = sub.add_parser("add")
    add.add_argument("--name", required=True)
    add.add_argument("--uses", type=int, default=int(os.environ.get("CLASSFLOW_AI_FREE_USES", "3")))
    sub.add_parser("list")
    sub.add_parser("budget")
    args = parser.parse_args()
    store = QuotaStore(os.environ.get("CLASSFLOW_AI_DB", str(Path(__file__).parent / "var/quota.sqlite3")))
    if args.command == "add":
        print(store.issue_user(args.name, args.uses))
    elif args.command == "list":
        print(json.dumps(store.users(), ensure_ascii=False, indent=2))
    else:
        budget = CNYBudget(store.path, os.environ.get("CLASSFLOW_AI_BUDGET_CNY", "10.00"))
        print(json.dumps(budget.summary(), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
