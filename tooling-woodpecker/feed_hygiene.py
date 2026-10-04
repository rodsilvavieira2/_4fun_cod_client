#!/usr/bin/env python3
"""Higiene do app-archive.json antes do upsert.

- Dedup: mantem so o maior buildNumber por (platform, version).
- Fail-closed: nova VERSION nao pode ser < max semver ja publicado;
  novo BUILD_NUMBER precisa ser > max build da plataforma.
Uso:
  feed_hygiene.py --archive <json> --version <X.Y.Z> --build-number <N>
"""
import argparse
import json
import sys
from pathlib import Path


def parse_semver(v: str):
    v = v.strip()
    # ignora build metadata (+...) e pre-release (-...) para ordenacao basica
    v = v.split("+")[0]
    pre = ""
    if "-" in v:
        v, pre = v.split("-", 1)
    parts = []
    for p in v.split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return (tuple(parts[:3]), pre)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--archive", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--build-number", required=True, type=int)
    args = ap.parse_args()

    archive = Path(args.archive)
    if not archive.exists():
        print("feed novo: sem higiene previa")
        return 0
    data = json.loads(archive.read_text(encoding="utf-8"))
    items = data.get("items", [])

    # Dedup por (platform, version) mantendo maior build.
    best = {}
    for it in items:
        key = (it.get("platform", ""), it.get("version", ""))
        bn = it.get("buildNumber") if isinstance(it.get("buildNumber"), int) else -1
        if key not in best or bn > (best[key].get("buildNumber") if isinstance(best[key].get("buildNumber"), int) else -1):
            best[key] = it
    if len(best) != len(items):
        print(f"dedup: {len(items)} -> {len(best)} itens")
    items = list(best.values())

    # Valida monotonico por plataforma.
    for platform in ("linux", "windows"):
        plat = [i for i in items if i.get("platform") == platform]
        if not plat:
            continue
        max_ver = max((parse_semver(str(i.get("version", "0.0.0"))) for i in plat))
        max_build = max((i.get("buildNumber") if isinstance(i.get("buildNumber"), int) else -1 for i in plat))
        new_ver = parse_semver(args.version)
        if new_ver[0] < max_ver[0]:
            print(
                f"ERRO: publish fora de ordem em {platform}: "
                f"nova VERSION {args.version} < max publicado {max_ver[0]}. "
                f"Publique versao >= max ou limpe o feed.",
                file=sys.stderr,
            )
            return 2
        if args.build_number <= max_build:
            print(
                f"ERRO: BUILD_NUMBER {args.build_number} <= max publicado ({max_build}) "
                f"em {platform}. O desktop_updater compara so buildNumber: "
                f"use numero maior que {max_build}.",
                file=sys.stderr,
            )
            return 3

    data["items"] = sorted(items, key=lambda i: (i.get("platform", ""), parse_semver(str(i.get("version", ""))), i.get("buildNumber") or -1))
    data.pop("signature", None)
    archive.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"higiene ok: {len(items)} itens, VERSION={args.version} BUILD={args.build_number}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
