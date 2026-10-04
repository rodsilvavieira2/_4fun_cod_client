#!/usr/bin/env python3
"""Gera desktop helper policy portable canonica (Windows/Linux).

Uso:
  generate_portable_policy.py --exe <exe> --helper <helper> \\
      --package-id <id> --key-id <keyId> --pubkey <base64> \\
      --platform windows|linux --output <policy.json>
      [--policy-id <id>] [--helper-service-id <id>]

Escreve JSON canonico (chaves ordenadas, sem espacos, sem newline final),
igual ao smoke do desktop_updater (example/tool/updater_smoke.dart).
Sem newline final: o nativo valida `EncodeCanonicalJson == file bytes`.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", required=True)
    ap.add_argument("--helper", required=True)
    ap.add_argument("--package-id", required=True)
    ap.add_argument("--key-id", required=True)
    ap.add_argument("--pubkey", required=True)
    ap.add_argument("--platform", required=True, choices=("windows", "linux"))
    ap.add_argument("--output", required=True)
    ap.add_argument("--policy-id", default="")
    ap.add_argument("--helper-service-id", default="com.example.desktop-updater.helper")
    args = ap.parse_args()

    exe = Path(args.exe)
    helper = Path(args.helper)
    out = Path(args.output)
    if not exe.is_file():
        print(f"exe nao encontrado: {exe}", file=sys.stderr)
        return 1
    if not helper.is_file():
        print(f"helper nao encontrado: {helper}", file=sys.stderr)
        return 1

    exe_sha = sha256_file(exe)
    helper_sha = sha256_file(helper)
    policy_id = args.policy_id or "com.example.desktop-updater.portable"

    if args.platform == "windows":
        strategies = [
            {"provider": "platformDirectory", "strategy": "directoryReplace"},
            {"provider": "platformFile", "strategy": "singleFileReplace"},
        ]
    else:
        strategies = [
            {"provider": "platformDirectory", "strategy": "directoryReplace"},
        ]

    policy = {
        "allowedApplicationSigner": {"kind": "sha256", "value": exe_sha},
        "allowedHelperSigner": {"kind": "sha256", "value": helper_sha},
        "allowedInstallRoots": [],
        "allowedStrategies": strategies,
        "allowedTargetClasses": ["sameUserWritable"],
        "applicationPackageId": args.package_id,
        "helperServiceId": args.helper_service_id,
        "minimumHelperProtocolVersion": 1,
        "policyId": policy_id,
        "policyVersion": 1,
        "releaseRootPublicKeys": [
            {
                "algorithm": "ed25519",
                "keyId": args.key_id,
                "publicKeyBase64": args.pubkey,
            }
        ],
    }
    canonical = json.dumps(policy, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    out.parent.mkdir(parents=True, exist_ok=True)
    # Sem newline final: validacao nativa e byte-exata.
    out.write_text(canonical, encoding="utf-8", newline="")
    print(canonical[:96] + "...")
    print(f"policy escrita: {out} (exe={exe_sha[:12]}.. helper={helper_sha[:12]}..)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
