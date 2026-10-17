#!/usr/bin/env python3
"""重建 ClassFlowWidget target 在 project.pbxproj 里的源文件登记记录（可重复运行）。

用法：
    python3 Scripts/sync-widget-target.py            # 就地改写
    python3 Scripts/sync-widget-target.py --check    # 只报告，不写文件
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROJECT_DIR = REPO / "apps" / "ios"
PBXPROJ = PROJECT_DIR / "ClassFlow.xcodeproj" / "project.pbxproj"

GROUP_ID = "000000000000000000000040"          # ClassFlowWidget 组
SOURCES_PHASE_ID = "000000000000000320000000"  # widget target 的 Sources phase
BUILD_FILE_PREFIX = "0000000000000003200000"   # + NN
FILE_REF_PREFIX = "0000000000000000000004"     # + NN

# 会被编进 widget target 的共享文件（相对工程目录的路径）。
SHARED_SOURCES = [
    *sorted(p.relative_to(PROJECT_DIR).as_posix() for p in (PROJECT_DIR / "ClassFlow" / "Models").glob("*.swift")),
    "ClassFlow/Services/AppData.swift",
    "ClassFlow/Services/AppDataStore.swift",
    "ClassFlow/Services/Inputs.swift",
    "ClassFlow/Services/WidgetSnapshotStore.swift",
    *sorted(p.relative_to(PROJECT_DIR).as_posix() for p in (PROJECT_DIR / "ClassFlow" / "Views" / "Widget").glob("*.swift")),
]

# 扩展自己的文件：组内相对路径。
WIDGET_SOURCES = sorted(
    p.name for p in (PROJECT_DIR / "ClassFlowWidget").glob("*.swift")
)

# 只进组、不进编译的文件。
WIDGET_RESOURCES = ["Info.plist", "ClassFlowWidget.entitlements"]


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def collect_sources() -> list[tuple[str, str, str]]:
    """→ [(kind, path, comment)]，kind 决定 sourceTree 与 path 的写法。"""
    entries: list[tuple[str, str, str]] = []

    for name in WIDGET_SOURCES:
        if not (PROJECT_DIR / "ClassFlowWidget" / name).is_file():
            fail(f"ClassFlowWidget/{name} 不存在")
        entries.append(("group", name, name))

    for path in SHARED_SOURCES:
        if not (PROJECT_DIR / path).is_file():
            fail(f"{path} 不存在")
        entries.append(("source_root", path, path))

    return entries


def build_sections(entries: list[tuple[str, str, str]]) -> tuple[str, str, list[str], list[str]]:
    build_files: list[str] = []
    file_refs: list[str] = []
    group_children: list[str] = []
    sources_phase: list[str] = []
    file_ref_ids: dict[str, str] = {}

    counter = 1
    for kind, path, comment in entries:
        build_id = f"{BUILD_FILE_PREFIX}{counter:02d}"
        ref_id = f"{FILE_REF_PREFIX}{counter:02d}"
        counter += 1

        if counter > 99:
            fail("文件太多，ID 位数不够（上限 99）")

        file_ref_ids[path] = ref_id

        build_files.append(
            f"\t\t{build_id} /* {comment} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {ref_id} /* {comment} */; }};"
        )

        # 路径必须加引号：OpenStep plist 的裸字符串不接受 `+` 之类的字符。
        if kind == "group":
            ref = (
                f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; '
                f'path = "{path}"; sourceTree = "<group>"; }}'
            )
        else:
            ref = (
                f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
                f'path = "{path}"; sourceTree = SOURCE_ROOT; }}'
            )
        file_refs.append(f"\t\t{ref_id} /* {path} */ = {ref};")

        group_children.append(f"\t\t\t\t{ref_id} /* {comment} */,")
        sources_phase.append(f"\t\t\t\t{build_id} /* {comment} in Sources */,")

    # Info.plist / entitlements 只进组、不参与编译，ID 从 98 起。
    for index, name in enumerate(WIDGET_RESOURCES, start=98):
        ref_id = f"{FILE_REF_PREFIX}{index:02d}"
        kind = "text.plist.xml" if name.endswith(".plist") else "text.plist.entitlements"
        file_refs.append(
            f'\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; '
            f'lastKnownFileType = {kind}; path = "{name}"; sourceTree = "<group>"; }};'
        )
        group_children.append(f"\t\t\t\t{ref_id} /* {name} */,")

    return (
        "\n".join(build_files),
        "\n".join(file_refs),
        group_children,
        sources_phase,
    )


def patch_section(text: str, header: str, drop_prefixes: list[str], new_lines: list[str]) -> str:
    """丢掉 section 里以 drop_prefixes 开头的旧行，再追加 new_lines；不得整段重建。"""
    pattern = re.compile(r"/\* Begin " + header + r" section \*/\n(.*?)/\* End " + header + r" section \*/", re.S)
    match = pattern.search(text)
    if not match:
        fail(f"工程文件里找不到 {header} section")

    kept = [
        line
        for line in match.group(1).splitlines()
        if not any(line.strip().startswith(prefix) for prefix in drop_prefixes)
    ]
    while kept and not kept[-1].strip():
        kept.pop()

    body = "\n".join([*kept, *new_lines])
    return text[: match.start()] + f"/* Begin {header} section */\n{body}\n/* End {header} section */" + text[match.end() :]


def replace_list(text: str, object_id: str, comment: str, key: str, items: list[str]) -> str:
    """替换某个对象里 `key = ( … );` 的条目列表。"""
    pattern = re.compile(
        r"(\t\t" + object_id + r" /\* " + re.escape(comment) + r" \*/ = \{.*?\n\t\t\t" + key + r" = \(\n)(.*?)(\t\t\t\);\n)",
        re.S,
    )
    match = pattern.search(text)
    if not match:
        fail(f"找不到 {comment} 的 {key} 列表")

    return text[: match.start(2)] + "\n".join(items) + "\n" + text[match.end(2) :]


def check_duplicate_ids(text: str) -> None:
    """提前拦截重复对象 ID：重复键会让工程文件成为非法 plist。"""
    ids = re.findall(r"^\t\t([0-9A-F]{24}) ", text, re.M)
    seen: set[str] = set()
    duplicates: set[str] = set()

    for object_id in ids:
        if object_id in seen:
            duplicates.add(object_id)
        seen.add(object_id)

    if duplicates:
        fail(f"工程文件里出现重复对象 ID：{', '.join(sorted(duplicates))}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只检查，不写文件")
    args = parser.parse_args()

    if not PBXPROJ.is_file():
        fail(f"找不到 {PBXPROJ}")

    entries = collect_sources()
    build_files, file_refs, group_children, sources_phase = build_sections(entries)
    print(f"widget target 源文件：{len(entries)} 个")
    print(f"  模型层 {len([e for e in entries if e[1].startswith('ClassFlow/Models/')])} 个")
    print(f"  服务层 {len([e for e in entries if e[1].startswith('ClassFlow/Services/')])} 个")
    print(f"  共享卡片 {len([e for e in entries if e[1].startswith('ClassFlow/Views/')])} 个")
    print(f"  扩展自身 {len(WIDGET_SOURCES)} 个")

    text = PBXPROJ.read_text(encoding="utf-8")
    original = text

    text = patch_section(text, "PBXBuildFile", [BUILD_FILE_PREFIX], build_files.splitlines())
    text = patch_section(text, "PBXFileReference", [FILE_REF_PREFIX], file_refs.splitlines())
    text = replace_list(text, GROUP_ID, "ClassFlowWidget", "children", group_children)
    text = replace_list(text, SOURCES_PHASE_ID, "Sources", "files", sources_phase)

    # 主 App 的 URL scheme（classflow://）来自这份 plist；须保留 GENERATE_INFOPLIST_FILE = YES。
    for config in ("000000000000000111000000", "000000000000000112000000"):
        marker = f"\t\t{config} /*"
        start = text.find(marker)
        if start < 0:
            fail(f"找不到 app target 的配置 {config}")

        end = text.find("\t\t};", start)
        block = text[start:end]
        # 不能用子串判断 INFOPLIST_FILE：GENERATE_INFOPLIST_FILE 里就含这串字符。
        if "\n\t\t\t\tINFOPLIST_FILE = " in block:
            continue

        updated = block.replace(
            "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n",
            "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n\t\t\t\tINFOPLIST_FILE = ClassFlow-Info.plist;\n",
            1,
        )
        if updated == block:
            fail(f"{config} 里没有 GENERATE_INFOPLIST_FILE，无法插入 INFOPLIST_FILE")
        text = text[:start] + updated + text[end:]

    if text == original:
        print("工程文件已经是最新状态，无需改动")
        return 0

    check_duplicate_ids(text)

    if args.check:
        print("工程文件需要更新（去掉 --check 就会写入）")
        return 1

    PBXPROJ.write_text(text, encoding="utf-8")
    print(f"已更新 {PBXPROJ.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
