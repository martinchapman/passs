.PHONY: prettier test

prettier:
	shfmt -w *.sh test/*.sh

test:
	result=0; for f in test/*_test.sh; do sh "$$f" || result=1; done; exit $$result
