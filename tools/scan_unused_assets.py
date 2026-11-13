#!/usr/bin/env python3
"""KONG 资源/文件引用扫描（静态检查，不启动 Godot）。

用法：python3 tools/scan_unused_assets.py
输出：Markdown 报告（stdout）。

边界：
- 只扫描 git 跟踪的文件；构建产物/.godot 缓存不计入仓库。
- 静态引用来自 .gd/.tscn/.tres/.cfg/.godot/.json/.py/.sh；文档引用单独统计。
- 代码里用字符串拼接的资源（assets/Cards、assets/animalese）标记为动态，不直接判为未使用。
- .import/.uid 不参与“未使用”判断（它们是导入元数据）。
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF_EXTS = {".gd", ".tscn", ".tres", ".cfg", ".godot", ".json", ".py", ".sh"}
DOC_EXTS = {".md", ".txt"}
ASSET_EXT_EXCLUDE = (".import", ".uid")
# 引擎导入依赖：静态扫描看不到 GLB/场景导入器对源贴图的引用（误删会让模型加载失败）。
KNOWN_IMPORT_DEPS = {
    "assets/3Dmodels/champion_crown_TexturesCom_Metal_BrassPolished_1K_albedo.png",
}
REF_RE = re.compile(r"res://[^\s\"'<>\)\]\}]+")
CLASS_RE = re.compile(r"^\s*class_name\s+([A-Za-z0-9_]+)", re.M)


def tracked_files() -> list[str]:
    out = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True)
    return [line for line in out.splitlines() if line]


def read_text(path: str) -> str:
    try:
        with open(os.path.join(ROOT, path), encoding="utf-8", errors="ignore") as fh:
            return fh.read()
    except OSError:
        return ""


def is_dynamic_ref(txt: str) -> bool:
    return ("%s" in txt or "%d" in txt or "format(" in txt or "CARD_DIR" in txt)


def main() -> None:
    files = [f for f in tracked_files() if os.path.isfile(os.path.join(ROOT, f))]
    texts = {f: read_text(f) for f in files if os.path.splitext(f)[1].lower() in REF_EXTS | DOC_EXTS}

    refs: dict[str, set[str]] = defaultdict(set)
    for src, txt in texts.items():
        for match in REF_RE.finditer(txt):
            refs[match.group(0).rstrip(".,;")].add(src)

    dynamic_prefixes: set[str] = set()
    for txt in texts.values():
        if "assets/Cards/" in txt and is_dynamic_ref(txt):
            dynamic_prefixes.add("assets/Cards/")
        if "assets/animalese" in txt:
            dynamic_prefixes.add("assets/animalese/")

    assets = [f for f in files if f.startswith("assets/") and not f.endswith(ASSET_EXT_EXCLUDE)]
    sizes = {f: os.path.getsize(os.path.join(ROOT, f)) for f in files if os.path.exists(os.path.join(ROOT, f))}

    unused: list[str] = []
    doc_only: list[tuple[str, list[str]]] = []
    dynamic: list[str] = []
    import_deps: list[str] = []
    for asset in assets:
        if asset in KNOWN_IMPORT_DEPS:
            import_deps.append(asset)
            continue
        srcs = refs.get("res://" + asset, set())
        runtime = [s for s in srcs if os.path.splitext(s)[1].lower() in REF_EXTS]
        docs = [s for s in srcs if os.path.splitext(s)[1].lower() in DOC_EXTS]
        if any(asset.startswith(prefix) for prefix in dynamic_prefixes):
            dynamic.append(asset)
        elif not srcs:
            unused.append(asset)
        elif not runtime and docs:
            doc_only.append((asset, sorted(docs)))

    print("# KONG 资源引用扫描\n")
    print(f"- 跟踪文件：{len(files)}；资产：{len(assets)}；文本源：{len(texts)}")
    print(f"- 动态目录（不直接删除）：{', '.join(sorted(dynamic_prefixes)) or '无'}\n")

    print("## 零运行时引用的资产\n")
    print("| 大小 | 文件 |")
    print("| ---: | --- |")
    for asset in sorted(unused, key=lambda f: -sizes.get(f, 0)):
        print(f"| {sizes.get(asset, 0):,} | `{asset}` |")

    print("\n## 只有文档引用的资产\n")
    if not doc_only:
        print("（无）")
    for asset, srcs in sorted(doc_only, key=lambda item: -sizes.get(item[0], 0)):
        print(f"- `{asset}` ← {', '.join(f'`{s}`' for s in srcs[:4])}")

    print("\n## 引擎导入依赖（静态扫描不可见，保留）\n")
    if not import_deps:
        print("（无）")
    for asset in sorted(import_deps):
        print(f"- {sizes.get(asset, 0):,} 字节：`{asset}`（被 GLB/场景导入器引用）")

    print("\n## 动态目录（需按代码规则核对，不要整目录删除）\n")
    for prefix in sorted(dynamic_prefixes):
        fs = sorted([a for a in assets if a.startswith(prefix)], key=lambda f: -sizes.get(f, 0))
        print(f"- `{prefix}`：{len(fs)} 个文件，{sum(sizes.get(f, 0) for f in fs):,} 字节")

    print("\n## 重复文件（≥10KB，同一内容）\n")
    hashes: dict[str, list[str]] = defaultdict(list)
    for f in files:
        if f.startswith(("addons/", "docs/")) or sizes.get(f, 0) < 10_000:
            continue
        path = os.path.join(ROOT, f)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "rb") as fh:
                hashes[hashlib.md5(fh.read()).hexdigest()].append(f)
        except OSError:
            pass
    found = False
    for fs in hashes.values():
        if len(fs) > 1:
            found = True
            print(f"- {sizes.get(fs[0], 0):,} 字节：{', '.join(f'`{f}`' for f in fs)}")
    if not found:
        print("（无）")

    print("\n## 仅沙盒/测试引用的资产（运行时未使用）\n")
    dev_only: list[tuple[str, list[str]]] = []
    for asset in assets:
        if any(asset.startswith(prefix) for prefix in dynamic_prefixes):
            continue
        srcs = refs.get("res://" + asset, set())
        runtime = [s for s in srcs if os.path.splitext(s)[1].lower() in REF_EXTS]
        if runtime and all(("sandbox" in s or s.startswith("tests/")) for s in runtime):
            dev_only.append((asset, sorted(runtime)))
    if not dev_only:
        print("（无）")
    for asset, srcs in sorted(dev_only, key=lambda item: -sizes.get(item[0], 0)):
        print(f"- {sizes.get(asset, 0):,} 字节：`{asset}` ← {', '.join(f'`{s}`' for s in srcs[:4])}")

    print("\n## 引用了但文件不存在（运行时路径，已过滤注释/中文标点）\n")
    safe_ref = re.compile(r"res://[A-Za-z0-9_./%+\-]+$")
    missing = False
    for ref, srcs in sorted(refs.items()):
        if not safe_ref.fullmatch(ref) or not ref.startswith("res://assets/"):
            continue
        if os.path.exists(os.path.join(ROOT, ref[6:])):
            continue
        runtime = [s for s in srcs if os.path.splitext(s)[1].lower() in REF_EXTS]
        if runtime:
            missing = True
            print(f"- `{ref}` ← {', '.join(f'`{s}`' for s in runtime[:4])}")
    if not missing:
        print("（无）")

    print("\n## 未被引用的脚本 / 场景\n")
    class_names = {}
    for f in files:
        if f.endswith(".gd"):
            match = CLASS_RE.search(texts.get(f, ""))
            if match:
                class_names[f] = match.group(1)

    def referenced(f: str) -> bool:
        if refs.get("res://" + f):
            return True
        name = class_names.get(f)
        if name:
            pattern = re.compile(r"\b" + re.escape(name) + r"\b")
            if any(src != f and pattern.search(txt) for src, txt in texts.items()):
                return True
        base = os.path.basename(f)
        return any(src != f and base in txt for src, txt in texts.items())

    for kind, ext in (("脚本", ".gd"), ("场景", ".tscn")):
        items = [f for f in files if f.endswith(ext) and not referenced(f)]
        print(f"\n### 未引用{kind}\n")
        if not items:
            print("（无）")
        for f in items:
            print(f"- `{f}`")


if __name__ == "__main__":
    main()
