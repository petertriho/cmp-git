.PHONY: test format format-check lint

test:
	nvim --headless -u NONE -l tests/run.lua

format:
	stylua lua tests

format-check:
	stylua --check lua tests

lint:
	selene --allow-warnings lua tests
