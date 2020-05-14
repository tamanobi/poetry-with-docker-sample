.PHONY: isort black test flake8 say

format: isort black

isort:
	isort -rc .

black:
	black

flake8:
	flake8 --config .flake8

test:
	pytest .

say:
	python -m scripts.main say $(ARGS)
