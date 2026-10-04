# ── Security: Gitleaks ─────────────────────────────────────────────────────

security-gitleaks-check-yamori:
	gitleaks detect --no-git --verbose --source {{ justfile_dir }}/src \
	  --config {{ justfile_dir }}/contrib/security/gitleaks-yamori.toml
	gitleaks detect --no-git --verbose --source {{ justfile_dir }}/tests \
	  --config {{ justfile_dir }}/contrib/security/gitleaks-yamori.toml

security-gitleaks-check-all:
	just security-gitleaks-check-yamori

# ── Security: Sanitize (Zig ReleaseSafe) ────────────────────────────────────

security-sanitize-check-yamori:
	zig build test -Doptimize=ReleaseSafe

security-sanitize-check-all:
	just security-sanitize-check-yamori

# ── Security: All ──────────────────────────────────────────────────────────

security-check-all:
	bash {{ justfile_dir }}/../contrib/security/security.sh sanitize-check-all && \
	bash {{ justfile_dir }}/../contrib/security/security.sh gitleaks-check-yamori
