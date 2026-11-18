#!/usr/bin/env python3
"""Watch the official pages listed as `source` in presets/presets.json.

For each page, pull out every size-like mention (e.g. "2048 px", "1080 x 1920", "20 MB")
and compare it with the fingerprint saved last time. If anything changed, write a report
for the workflow to open as a GitHub issue. The numbers in presets.json are never edited
automatically: a person checks the page and updates the file.
"""
import hashlib
import html
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
PRESETS = ROOT / "presets" / "presets.json"
FINGERPRINTS = ROOT / "presets" / "spec-fingerprints.json"
REPORT = ROOT / "spec-report.md"

SIZE_PATTERN = re.compile(
    r"\b\d{2,5}\s*(?:[x×]\s*\d{2,5}|px|pixels?|พิกเซล|MB|KB|megapixels?)\b",
    re.IGNORECASE,
)


def page_sizes(url: str) -> list[str]:
    req = urllib.request.Request(url, headers={"User-Agent": "presets-spec-check/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8", errors="replace")
    raw = re.sub(r"(?is)<(script|style)\b.*?</\1>", " ", raw)
    text = html.unescape(re.sub(r"<[^>]+>", " ", raw))
    text = re.sub(r"\s+", " ", text)
    return sorted({re.sub(r"\s+", " ", m.group(0)) for m in SIZE_PATTERN.finditer(text)})


def main() -> int:
    presets = json.loads(PRESETS.read_text())
    sources = sorted({
        t["source"]
        for p in presets["platforms"]
        for t in p["targets"]
        if t.get("source")
    })
    old = json.loads(FINGERPRINTS.read_text()) if FINGERPRINTS.exists() else {}
    new, changes, failures = {}, [], []

    for url in sources:
        try:
            sizes = page_sizes(url)
        except Exception as exc:  # network errors shouldn't wipe the old fingerprint
            failures.append(f"- {url}: {exc}")
            if url in old:
                new[url] = old[url]
            continue
        digest = hashlib.sha256("\n".join(sizes).encode()).hexdigest()
        new[url] = {"sha256": digest, "sizes": sizes}
        if url in old and old[url]["sha256"] != digest:
            before, after = set(old[url]["sizes"]), set(sizes)
            changes.append(
                f"### {url}\n"
                f"- เพิ่ม: {', '.join(sorted(after - before)) or '-'}\n"
                f"- หายไป: {', '.join(sorted(before - after)) or '-'}\n"
            )

    FINGERPRINTS.write_text(json.dumps(new, ensure_ascii=False, indent=2) + "\n")

    if changes:
        REPORT.write_text(
            "หน้าข้อมูลทางการมีตัวเลขขนาดภาพเปลี่ยนไป กรุณาตรวจแล้วแก้ `presets/presets.json` "
            "(อย่าลืมเปลี่ยน `updatedAt`)\n\n" + "\n".join(changes)
            + ("\n\nโหลดไม่ได้:\n" + "\n".join(failures) if failures else "")
        )
        print("changes found")
    else:
        print("no changes")
    if failures:
        print("\n".join(failures), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
