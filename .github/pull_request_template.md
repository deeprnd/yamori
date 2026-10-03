<!--
Thanks for the PR. Please fill this out to speed up review.

Describe the change in terms of runtime behavior, backend routing,
determinism, audit trail, observability, and performance when relevant.

Tips:
- Link issues with "Closes #123" / "Fixes #123"
- Keep scope focused; split unrelated changes into separate PRs
-->

# Summary

<!-- What changed, why, and which component is affected? Keep it concise. -->

## Type of change

<!-- Check all that apply. -->

- [ ] ✨ New feature
- [ ] 🐛 Bug fix
- [ ] 🧹 Refactor (no functional change)
- [ ] ⚡ Performance improvement
- [ ] 📚 Documentation
- [ ] 🧪 Tests
- [ ] 🔧 Build/CI/DevEx
- [ ] 🛡️ Security fix
- [ ] ⏪ Revert

## Related work

<!-- Link issues, PRs, notes. -->

- Issue(s):
- Notes:

## Risk & impact

<!-- What can break? Call out backend routing changes, ABI contract impact,
determinism (provenance hash), audit/replay output, shared-memory effects,
or performance impact. -->

## How to test

<!-- Provide exact commands and a short result summary. Prefer existing
`just` targets or focused test invocations. -->

1.
2.
3.

## Runtime / ABI contract changes (if applicable)

- [ ] No runtime/ABI contract change
- [ ] C ABI signature changed and bindings are updated
- [ ] Backend routing / capability registry changed
- [ ] Shared-memory representation (Buffer/Array/Series/Table) changed
- [ ] Dependency graph schema changed
- [ ] Deterministic execution policy changed
- [ ] Audit trail / provenance hash changed
- [ ] Error normalization / !Error convention changed

## Generated code / artifacts (if applicable)

- [ ] No generated artifacts changed

## Build / config / docs changes (if applicable)

- [ ] No env/config change
- [ ] `justfile`/tooling updated
- [ ] README updated
- [ ] Other project docs updated

## Backend library changes (if applicable)

- [ ] No backend library changed
- [ ] New backend registered for an existing domain operation
- [ ] Backend plurality decision changed (e.g. OpenBLAS → BLIS for matmul)
- [ ] Backend integration (new domain: TA-Lib, QuantLib, BLAS/LAPACK, Cuba, FFTW, GSL)
- [ ] Backend version bump — ABI compatibility verified

# Checklist

## Implementation

- [ ] Scope is limited to the intended change
- [ ] Code follows project conventions and style guidelines
- [ ] No secrets/tokens/sensitive data included (keys, DB creds)
- [ ] Throughput, control, and isolation impact considered

## Tests

<!-- Check what applies and include links to CI runs if useful. -->

- [ ] Tests are not required for this change (explain below)
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] E2E tests added/updated
- [ ] Existing tests updated to reflect behavior changes
- [ ] `just tests-all` command executed successfully
- [ ] Relevant checks pass locally and/or in CI

### If tests were not added, explain why

<!-- e.g., docs-only change, no behavior change, covered by existing tests -->

## Determinism & reproducibility

- [ ] No determinism-relevant change
- [ ] Provenance hash (`BLAKE3(canonical(inputs) ‖ policy ‖ semver ‖ dataset manifest)`)
  updated and golden tests adjusted
- [ ] Deterministic execution policy changed (iter. multiplication, summation order,
  fixed iteration counts, no fast-math, counter-based RNG)
- [ ] Backend plurality selection changed

## Audit & observability

- [ ] No audit/observability impact
- [ ] Pipeline stage signals updated (ingest, resolve, adjust, derive, project,
  analyse, audit)
- [ ] Alerting severity taxonomy applied (critical/warning/info)
- [ ] Failure categories documented (!Error convention preserved)

## Security & privacy (if applicable)

- [ ] Capability/policy/input validation reviewed
- [ ] Dependency/tooling changes reviewed for risk
- [ ] No sensitive data exposure introduced

## Licensing / dependencies

- [ ] No license boundary changed
- [ ] Modified files use the correct Apache-2.0 / GPL-3.0-only / creative-content terms
- [ ] Existing copyright, SPDX, NOTICE, and attribution notices are preserved
- [ ] New third-party dependencies and their licenses are documented

## Release notes

- [ ] No release note needed
- [ ] Release note provided below

### Release note (if needed)

<!-- One sentence in user-facing language. -->