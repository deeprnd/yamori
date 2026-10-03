# ── Quality: Format ────────────────────────────────────────────────────────────

quality-format-check-zig:
    bash {{ justfile_dir }}/contrib/quality/quality.sh format-check-zig

quality-format-fix-zig:
    bash {{ justfile_dir }}/contrib/quality/quality.sh format-fix-zig

# ── Quality: Lint ──────────────────────────────────────────────────────────────

quality-lint-check-zig:
    bash {{ justfile_dir }}/contrib/quality/quality.sh lint-check-zig

quality-lint-check-yaml:
    bash {{ justfile_dir }}/contrib/quality/quality.sh lint-check-yaml

quality-lint-check-spell:
    bash {{ justfile_dir }}/contrib/quality/quality.sh lint-check-spell

# ── Quality: All ───────────────────────────────────────────────────────────────

quality-check-all:
    bash {{ justfile_dir }}/contrib/quality/quality.sh format-check-zig && \
    bash {{ justfile_dir }}/contrib/quality/quality.sh lint-check-zig && \
    bash {{ justfile_dir }}/contrib/quality/quality.sh lint-check-yaml && \
    bash {{ justfile_dir }}/contrib/quality/quality.sh lint-check-spell
