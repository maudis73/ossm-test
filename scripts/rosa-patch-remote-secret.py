#!/usr/bin/env python3
"""Patch istioctl remote-secret YAML for ROSA: drop CA, set insecure-skip-tls-verify (PoC)."""
import base64
import sys

import yaml


def main() -> None:
    if len(sys.argv) != 4:
        print(
            "usage: rosa-patch-remote-secret.py <kubeconfigKey> <in.yaml> <out.yaml>",
            file=sys.stderr,
        )
        sys.exit(2)
    kc_key, in_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(in_path, encoding="utf-8") as f:
        docs = list(yaml.safe_load_all(f))

    secret_doc = next((d for d in docs if d and d.get("kind") == "Secret"), None)
    if not secret_doc:
        print("ERROR: No Secret found in istioctl output", file=sys.stderr)
        sys.exit(1)

    meta = secret_doc.setdefault("metadata", {})
    if meta.get("namespace") in (None, "default"):
        meta["namespace"] = "istio-system"

    is_string_data = False
    kc_yaml = None
    if "stringData" in secret_doc and kc_key in secret_doc["stringData"]:
        kc_yaml = secret_doc["stringData"][kc_key]
        is_string_data = True
    elif "data" in secret_doc and kc_key in secret_doc["data"]:
        kc_yaml = base64.b64decode(secret_doc["data"][kc_key]).decode()
        is_string_data = False
    else:
        print(f"ERROR: Cannot find key {kc_key!r} in secret stringData/data", file=sys.stderr)
        sys.exit(1)

    kc = yaml.safe_load(kc_yaml)
    for cluster in kc.get("clusters", []):
        cfg = cluster.get("cluster", {})
        cfg.pop("certificate-authority-data", None)
        cfg["insecure-skip-tls-verify"] = True

    fixed = yaml.dump(kc, default_flow_style=False)
    if is_string_data:
        secret_doc["stringData"][kc_key] = fixed
    else:
        secret_doc["data"][kc_key] = base64.b64encode(fixed.encode()).decode()

    with open(out_path, "w", encoding="utf-8") as f:
        yaml.dump(secret_doc, f, default_flow_style=False)


if __name__ == "__main__":
    main()
