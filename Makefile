.PHONY: secure\:repo ruleset\:apply

secure\:repo:
	@bash ./secure-defaults-git.sh

ruleset\:apply:
	@if [ -z "$(REPO)" ]; then \
		echo "Set REPO=owner/repo before running this target"; \
		exit 1; \
	fi
	@gh api -X POST "repos/$(REPO)/rulesets" \
		-H "Accept: application/vnd.github+json" \
		--input default-protection.json
