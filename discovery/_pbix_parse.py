"""Parse PBIR visuals + DataModel strings. Do not modify the PBIX."""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(r"c:\apache hop\hop_projects\hop-guajiranet\discovery\_pbix_unzip")
DEF = ROOT / "Report" / "definition"


def walk_fields(obj, acc):
    if isinstance(obj, dict):
        # PBIR field ref
        if "Entity" in obj and "Property" in obj:
            acc.append({"kind": "column", "table": obj.get("Entity"), "column": obj.get("Property")})
        if "Entity" in obj and "Property" not in obj and "Name" in obj:
            pass
        # Measure ref often { "Measure": { "Expression": { "SourceRef": ..., "Property": "..." } } }
        if "Measure" in obj and isinstance(obj["Measure"], dict):
            m = obj["Measure"]
            expr = m.get("Expression") or m
            src = None
            prop = None
            if isinstance(expr, dict):
                sr = expr.get("SourceRef") or {}
                if isinstance(sr, dict):
                    src = sr.get("Entity") or sr.get("Source")
                prop = expr.get("Property")
            if prop:
                acc.append({"kind": "measure", "table": src, "measure": prop})
        if obj.get("Property") and (obj.get("SourceRef") or obj.get("Expression")):
            sr = obj.get("SourceRef")
            if isinstance(sr, dict):
                entity = sr.get("Entity")
                acc.append({"kind": "field", "table": entity, "property": obj.get("Property")})
        for v in obj.values():
            walk_fields(v, acc)
    elif isinstance(obj, list):
        for i in obj:
            walk_fields(i, acc)


def extract_utf16_strings(data: bytes, min_len=4):
    # UTF-16LE sequences of printable chars
    chars = []
    i = 0
    out = []
    while i + 1 < len(data):
        c = data[i] | (data[i + 1] << 8)
        if 32 <= c < 127 or c in (0x00C1, 0x00E1, 0x00C9, 0x00E9, 0x00CD, 0x00ED, 0x00D3, 0x00F3, 0x00DA, 0x00FA, 0x00D1, 0x00F1):
            chars.append(chr(c))
        else:
            if len(chars) >= min_len:
                out.append("".join(chars))
            chars = []
        i += 2
    if len(chars) >= min_len:
        out.append("".join(chars))
    return out


def main():
    pages_meta = json.loads((DEF / "pages" / "pages.json").read_text(encoding="utf-8"))
    pages = []
    all_fields = []
    for pid in pages_meta["pageOrder"]:
        page = json.loads((DEF / "pages" / pid / "page.json").read_text(encoding="utf-8"))
        visuals = []
        vdir = DEF / "pages" / pid / "visuals"
        if vdir.exists():
            for vj in sorted(vdir.glob("*/visual.json")):
                vis = json.loads(vj.read_text(encoding="utf-8"))
                fields = []
                walk_fields(vis, fields)
                # unique
                seen = set()
                uf = []
                for f in fields:
                    key = tuple(sorted(f.items()))
                    if key not in seen:
                        seen.add(key)
                        uf.append(f)
                        all_fields.append({**f, "page": page.get("displayName"), "visual": vis.get("name")})
                visual_type = None
                try:
                    visual_type = vis["visual"]["visualType"]
                except Exception:
                    visual_type = vis.get("visualType") or vis.get("type")
                title = None
                try:
                    # common title path
                    t = vis["visual"]["visualContainerObjects"]["title"]
                except Exception:
                    t = None
                visuals.append({
                    "id": vis.get("name"),
                    "file": str(vj.relative_to(DEF)),
                    "visualType": visual_type,
                    "fields": uf,
                    "raw_keys": list(vis.keys()),
                })
        pages.append({
            "id": page.get("name"),
            "displayName": page.get("displayName"),
            "visibility": page.get("visibility"),
            "visualCount": len(visuals),
            "visuals": visuals,
        })

    dm = (ROOT / "DataModel").read_bytes()
    print("DataModel prefix utf16:", dm[:80].decode("utf-16-le", errors="replace")[:80])
    strings = extract_utf16_strings(dm, 3)
    # unique preserve order
    uniq = []
    seen_s = set()
    for s in strings:
        if s not in seen_s:
            seen_s.add(s)
            uniq.append(s)
    print("unique strings", len(uniq))
    keywords = [
        "dim ", "fact ", "tbl_", "Measure", "CALCULATE", "DISTINCTCOUNT", "SUM(",
        "RELATED", "DATE", "cliente", "servicio", "geografia", "tiempo", "facturacion",
        "Inicio", "Operacion", "documento", "neto", "sk_",
    ]
    interesting = [s for s in uniq if any(k.lower() in s.lower() for k in keywords) or s.startswith("[") or "=" in s[:20]]
    print("interesting", len(interesting))
    for s in interesting[:400]:
        if len(s) < 400:
            print("STR:", s)

    out = {
        "pages": pages,
        "all_fields": all_fields,
        "string_count": len(uniq),
    }
    Path(r"c:\apache hop\hop_projects\hop-guajiranet\discovery\_pbix_parse_out.json").write_text(
        json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    Path(r"c:\apache hop\hop_projects\hop-guajiranet\discovery\_pbix_strings.txt").write_text(
        "\n".join(uniq), encoding="utf-8"
    )
    print("wrote parse out")


if __name__ == "__main__":
    main()
