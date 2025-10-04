.PHONY: test test-aas test-sas test-resolvers test-resolver-example build clean

test: test-aas test-sas test-resolvers test-resolver-example

test-aas:
	cd aas && aptos move test

test-sas:
	cd sas && sui move test

test-resolvers:
	cd sas/resolvers && sui move test

test-resolver-example:
	cd aas/resolver_example && aptos move test

build:
	cd aas && aptos move build
	cd sas && sui move build
	cd sas/resolvers && sui move build
	cd aas/resolver_example && aptos move build

clean:
	rm -rf aas/build aas/resolver_example/build sas/build sas/resolvers/build
