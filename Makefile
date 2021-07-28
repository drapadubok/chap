.ONESHELL:
export SHELL:=/bin/bash

VIRTUALENV = venv_src
PYTHON=$(VIRTUALENV)/bin/python3.7
COMMIT_HASH := $(shell git rev-parse HEAD | cut -c 1-7)

devenv: create_virtualenv install_modules
.PHONY: devenv

create_virtualenv:
	python3.7 -m venv $(VIRTUALENV)
	bash setup_venv.sh
	$(PYTHON) -m pip install --upgrade pip
.PHONY: create_virtualenv

install_modules:
	$(PYTHON) -m pip install -r scripts/requirements.txt --use-deprecated=legacy-resolver
.PHONY: install_modules

docker_build:
	cd chap; DOCKER_BUILDKIT=1 docker build --progress=plain -t chap .
	docker tag chap drapabubok/chap:latest
	docker tag chap drapabubok/chap:$(COMMIT_HASH)
	docker push drapabubok/chap:latest
	docker push drapabubok/chap:$(COMMIT_HASH)
