shell := /usr/bin/env bash

run-contract-test:
	$(shell) main.sh

debug-test:
	$(shell) -x main.sh
