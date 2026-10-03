#!/usr/bin/env python3
"""Phase 1: Rename epic files with collision handling."""
import subprocess
from pathlib import Path
from collections import defaultdict

EPICS = Path(__file__).parent

RENAME_MAP = {
    "V2.1": "V2.6", "V2.2": "V2.7", "V2.3": "V2.8", "V2.4": "V2.9", "V2.5": "V2.10",
    "V3.6": "V3.11", "V3.7": "V3.12", "V3.8": "V3.13", "V3.9": "V3.14",
    "V3.10": "V3.15", "V3.11": "V3.16",
    "V4.12": "V4.17", "V4.13": "V4.18", "V4.14": "V4.19", "V4.15": "V4.20",
    "V4.16": "V4.21", "V4.17": "V4.22", "V4.18": "V4.23", "V4.19": "V4.24", "V4.20": "V4.25",
    "V5.21": "V5.26", "V5.22": "V5.27", "V5.23": "V5.28", "V5.24": "V5.29",
    "V5.25": "V5.30", "V5.26": "V5.31", "V5.27": "V5.32", "V5.28": "V5.33", "V5.29": "V5.34",
    "V6.1": "V6.35", "V6.2": "V6.36", "V6.3": "V6.37", "V6.4": "V6.38",
    "V6.5": "V6.39", "V6.6": "V6.40",
    "V7.1": "V7.41", "V7.2": "V7.42", "V7.3": "V7.43", "V7.4": "V7.44",
    "V7.5": "V7.45", "V7.6": "V7.46", "V7.7": "V7.47",
    "V8.1": "V8.48", "V8.2": "V8.49", "V8.3": "V8.50", "V8.4": "V8.51",
    "V8.5": "V8.52", "V8.6": "V8.53",
    "V9.1": "V9.54", "V9.2": "V9.55", "V9.3": "V9.56", "V9.4": "V9.57",
    "V9.5": "V9.58", "V9.6": "V9.59",
}

groups = defaultdict(list)
for old_id, new_id in RENAME_MAP.items():
    ms = int(old_id.lstrip('V').split('.')[0])
    groups[ms].append((old_id, new_id))

for ms in sorted(groups):
    pairs = groups[ms]
    existing_targets = [nid for oid, nid in pairs if (EPICS / f"{nid}.md").exists()]
    if existing_targets:
        print(f"M{ms}: moving colliding targets to temp: {existing_targets}")
        for nid in existing_targets:
            subprocess.run(["git", "mv", str(EPICS / f"{nid}.md"), str(EPICS / f".tmp_{nid}.md")], check=True)
    for old_id, new_id in pairs:
        subprocess.run(["git", "mv", str(EPICS / f"{old_id}.md"), str(EPICS / f"{new_id}.md")], check=True)
    for nid in existing_targets:
        subprocess.run(["git", "mv", str(EPICS / f".tmp_{nid}.md"), str(EPICS / f"{nid}.md")], check=True)

count = len(list(EPICS.glob("V*.md")))
print(f"Done. Epic files: {count}")
assert count == 59
