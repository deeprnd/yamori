# Test: Coverage recipes
# Runs tests under kcov to produce line coverage summary.
#
# Requires: kcov (sudo apt-get install kcov)

test-cov-yamori:
	@cd `git rev-parse --show-toplevel` && bash {{ justfile_dir }}/../contrib/test/coverage-yamori.sh coverage-yamori

test-cov-yamori-linux-x86: test-cov-yamori

test-cov-yamori-linux-arm: test-cov-yamori-linux-x86
