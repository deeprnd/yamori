#!/usr/bin/env python3
"""Phases 2-5: Update all references after file renames."""
import re
import sys
from pathlib import Path

EPICS = Path("/home/vicgenin/work/git/yamori/doc/strategy/roadmap/epics")
MILESTONES = Path("/home/vicgenin/work/git/yamori/doc/strategy/roadmap/milestones")
TEMPLATES = Path("/home/vicgenin/work/git/yamori/doc/strategy/templates")
README = EPICS / "README.md"

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

OLD_IDS = sorted(RENAME_MAP.keys(), key=lambda x: (int(x.lstrip('V').split('.')[0]), int(x.lstrip('V').split('.')[1])))
PATTERN = r'\b(' + '|'.join(re.escape(old) for old in OLD_IDS) + r')\b'

def replace_ids(content: str) -> str:
    def replacer(m: re.Match) -> str:
        result: str = RENAME_MAP.get(m.group(0), m.group(0))
        return result
    return re.sub(PATTERN, replacer, content)

def _sort_key(p: Path) -> tuple[int, int]:
    """Sort key for Vx.y.md filenames."""
    stem = str(p.stem).lstrip('V')
    parts = stem.split('.')
    return (int(parts[0]), int(parts[1]))

def _sort_key(p: Path) -> tuple[int, int]:
    """Sort key for Vx.y.md filenames."""
    stem = str(p.stem).lstrip('V')
    parts = stem.split('.')
    return (int(parts[0]), int(parts[1]))

def update_epics():
    """Phase 2: Update all renamed epic file contents."""
    print("=== PHASE 2: Update Epic File Contents ===")
    files = sorted(EPICS.glob("V*.md"), key=_sort_key)
    updated = 0
    
    for filepath in files:
        with open(filepath, 'r') as f:
            content = f.read()
        
        old_content = content
        
        # Replace all Vx.y references
        content = replace_ids(content)
        
        # Update the title line to match filename
        new_id = filepath.stem
        # Find current title and replace with correct ID
        for line in content.split('\n'):
            m = re.match(r'^#\s+(V\d+\.\d+):', line)
            if m:
                old_id = m.group(1)
                title_body = line[len(f"# {old_id}:"):].strip()
                content = content.replace(f"# {old_id}: {title_body}", f"# {new_id}: {title_body}", 1)
                content = content.replace(f"# {old_id}:", f"# {new_id}:", 1)
                break
        
        if content != old_content:
            with open(filepath, 'w') as f:
                f.write(content)
            updated += 1
            print(f"  Updated: {filepath.name}")
    
    print(f"  Total updated: {updated}/{len(files)}")
    print("  Phase 2 complete.\n")

def verify_epic_refs():
    """Phase 2b: Verify no old-style references remain in epic files."""
    print("=== PHASE 2b: Verify Epic File References ===")
    files = sorted(EPICS.glob("V*.md"), key=lambda p: (int(p.stem.split('.')[0]), int(p.stem.split('.')[1])))
    old_refs = 0
    
    for filepath in files:
        with open(filepath, 'r') as f:
            content = f.read()
        for old_id in OLD_IDS:
            if re.search(r'\b' + re.escape(old_id) + r'\b', content):
                print(f"  STALE: {filepath.name} still contains {old_id}")
                old_refs += 1
    
    if old_refs == 0:
        print("  All old IDs replaced in epic files.")
    print("  Phase 2b complete.\n")
    return old_refs

def update_milestones():
    """Phase 3: Update milestone files."""
    print("=== PHASE 3: Update Milestone Files ===")
    files = sorted(MILESTONES.glob("m*.md"), key=lambda p: int(p.stem[1:]))
    updated = 0
    
    for filepath in files:
        with open(filepath, 'r') as f:
            content = f.read()
        
        old_content = content
        content = replace_ids(content)
        
        if content != old_content:
            with open(filepath, 'w') as f:
                f.write(content)
            updated += 1
            print(f"  Updated: {filepath.name}")
    
    print(f"  Total updated: {updated}/{len(files)}")
    print("  Phase 3 complete.\n")
    return updated

def update_readme():
    """Phase 4: Update epics README.md."""
    print("=== PHASE 4: Update README.md ===")
    with open(README, 'r') as f:
        content = f.read()
    
    old_content = content
    content = replace_ids(content)
    
    # Fix M7/M8 swap + V8.7 removal
    lines = content.split('\n')
    new_lines = []
    in_m7_section = False
    in_m8_section = False
    m7_desc_fixed = False
    m8_desc_fixed = False
    
    for line in lines:
        if '## Milestone 7' in line or '### Milestone 7' in line:
            in_m7_section = True
            in_m8_section = False
        elif '## Milestone 8' in line or '### Milestone 8' in line:
            in_m7_section = False
            in_m8_section = True
        elif line.startswith('## Milestone'):
            in_m7_section = False
            in_m8_section = False
        
        # Fix M7: QuantLib → BLAS/LAPACK
        if in_m7_section and 'QuantLib' in line and not m7_desc_fixed:
            line = line.replace('QuantLib', 'BLAS/LAPACK')
            m7_desc_fixed = True
            print(f"  Fixed M7 description (QuantLib → BLAS/LAPACK)")
        
        # Fix M8: BLAS/LAPACK → Cuba/FFTW
        if in_m8_section and 'BLAS/LAPACK' in line and not m8_desc_fixed:
            line = line.replace('BLAS/LAPACK', 'Cuba/FFTW')
            m8_desc_fixed = True
            print(f"  Fixed M8 description (BLAS/LAPACK → Cuba/FFTW)")
        
        # Remove V8.7 lines (phantom entry)
        if 'V8.7' in line:
            if re.match(r'\s*-\s*\[.*\].*V8\.7', line) or '|V8.7' in line:
                print(f"  Removing phantom V8.7 entry")
                continue
        
        new_lines.append(line)
    
    content = '\n'.join(new_lines)
    
    if content != old_content:
        with open(README, 'w') as f:
            f.write(content)
        print("  README.md updated.")
    else:
        print("  README.md: no content changes.")
    
    print("  Phase 4 complete.\n")

def update_templates():
    """Phase 4b: Update template files."""
    print("=== PHASE 4b: Update Template Files ===")
    template_files = [
        TEMPLATES / "epic-template.md",
        TEMPLATES / "milestone-template.md",
        TEMPLATES / "release-template.md",
        TEMPLATES / "story-template.md",
    ]
    
    updated = 0
    for filepath in template_files:
        if not filepath.exists():
            print(f"  Skipping (not found): {filepath.name}")
            continue
        
        with open(filepath, 'r') as f:
            content = f.read()
        
        old_content = content
        content = replace_ids(content)
        
        if content != old_content:
            with open(filepath, 'w') as f:
                f.write(content)
            updated += 1
            print(f"  Updated: {filepath.name}")
    
    print(f"  Total updated: {updated}/{len(template_files)}")
    print("  Phase 4b complete.\n")

def verify_all():
    """Phase 5: Verification."""
    print("=== PHASE 5: Verification ===")
    errors = 0
    
    # 1. Check all 59 epic files exist
    existing = sorted(EPICS.glob("V*.md"), key=lambda p: (int(p.stem.split('.')[0]), int(p.stem.split('.')[1])))
    print(f"  Epic files: {len(existing)}")
    if len(existing) != 59:
        print(f"  ERROR: Expected 59, got {len(existing)}")
        errors += 1
    
    # 2. Every epic file title should match filename
    for filepath in existing:
        with open(filepath, 'r') as f:
            first_line = f.readline().strip()
        expected = f"# {filepath.stem}:"
        if not first_line.startswith(expected):
            print(f"  TITLE MISMATCH: {filepath.name} → '{first_line}' (expected '{expected}')")
            errors += 1
    
    # 3. No old-style Vx.y references in epic files
    stale = 0
    for filepath in existing:
        with open(filepath, 'r') as f:
            content = f.read()
        for old_id in OLD_IDS:
            if re.search(r'\b' + re.escape(old_id) + r'\b', content):
                print(f"  STALE REF: {filepath.name} contains {old_id}")
                stale += 1
    
    if stale == 0:
        print("  No stale Vx.y references in epic files.")
    else:
        errors += stale
    
    # 4. No old-style Vx.y references in milestone files
    stale_ms = 0
    for ms_file in MILESTONES.glob("m*.md"):
        with open(ms_file, 'r') as f:
            content = f.read()
        for old_id in OLD_IDS:
            if re.search(r'\b' + re.escape(old_id) + r'\b', content):
                print(f"  STALE REF: {ms_file.name} contains {old_id}")
                stale_ms += 1
    
    if stale_ms == 0:
        print("  No stale Vx.y references in milestone files.")
    else:
        errors += stale_ms
    
    # 5. README links should resolve
    with open(README, 'r') as f:
        readme = f.read()
    
    broken_links = []
    for match in re.finditer(r'\]\(V(\d+\.\d+)\.md\)', readme):
        eid = match.group(1)
        if eid not in RENAME_MAP and not eid.startswith("V1."):
            link_path = EPICS / f"{eid}.md"
            if not link_path.exists():
                broken_links.append(eid)
    
    if broken_links:
        print(f"  BROKEN README LINKS: {broken_links}")
        errors += len(broken_links)
    else:
        print("  All README links resolve.")
    
    # 6. No V8.7 phantom entry
    if re.search(r'\bV8\.7\b', readme):
        print("  WARNING: V8.7 still referenced in README")
    
    print(f"\n  Verification {'PASSED' if errors == 0 else 'FAILED'} (errors: {errors})")
    print("  Phase 5 complete.\n")
    
    return errors

if __name__ == "__main__":
    print("Starting Phases 2-5 of epic rename...\n")
    
    update_epics()
    verify_epic_refs()
    update_milestones()
    update_readme()
    update_templates()
    errors = verify_all()
    
    if errors == 0:
        print("All phases complete successfully!")
    else:
        print(f"{errors} verification errors found. Review output above.")
        sys.exit(1)
