#!/usr/bin/env just

set export

justfile_dir := "."

import "just/security.just"
import "just/quality.just"

# ── Build ───────────────────────────────────────────────────────────────────

default:
	@just --list

help:
	@just --list

build:
	zig build

install:
	zig build install

# ── Test ────────────────────────────────────────────────────────────────────

test:
	zig build test

# ── Security ───────────────────────────────────────────────────────────────

# Full security check: sanitize + gitleaks
security:
	just security-check-all

# ── Cleanup ─────────────────────────────────────────────────────────────────

clean:
	rm -rf zig-out zig-cache build
