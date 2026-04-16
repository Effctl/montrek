SECURE_WRAPPER := bash bin/secrets/secure-wrapper.sh
UV_PYTHON = $(shell pyenv which python 2>/dev/null || command -v python3 || command -v python)
TMUX_LOCAL_DEV_SESSION ?= montrek-local-dev
export UV_PYTHON

.PHONY: help
help: # Show help for each of the Makefile recipes.
	@grep -E '^[a-zA-Z0-9 -]+:.*#'  Makefile | sort | while read -r l; do printf "\033[1;32m$$(echo $$l | cut -f 1 -d':')\033[00m:$$(echo $$l | cut -f 2- -d'#')\n"; done

.PHONY: local-init
local-init: # Install local python environment and necessary packages
	@$(SECURE_WRAPPER) bin/local/init.sh

.PHONY: local-runserver
local-runserver: # Run the montrek django app locally (non-docker).
	@$(SECURE_WRAPPER) bin/local/runserver.sh

.PHONY: local-infra-up
local-infra-up: # Start the local infrastructure in dev mode (database and redis in docker)
	@echo "Starting local infrastructure in dev mode (Redis + DB in docker)..."
	@set -a; [ -f .env ] && . ./.env; set +a; \
	docker compose -f docker-compose.yml -f "$${LOCAL_DEV_COMPOSE_FILE:-docker-compose.local-dev.yml}" up -d redis db

.PHONY: local-infra-down
local-infra-down: # Stop the local infrastructure in dev mode (database and redis in docker)
	@echo "Stopping local infrastructure in dev mode (Redis + DB in docker)..."
	@set -a; [ -f .env ] && . ./.env; set +a; \
	docker compose -f docker-compose.yml -f "$${LOCAL_DEV_COMPOSE_FILE:-docker-compose.local-dev.yml}" stop redis db

.PHONY: local-worker-debug
local-worker-debug: # Run the montrek worker in debug mode locally (non-docker).
	@set -a; [ -f .env ] && . ./.env; set +a; \
	echo "Starting Celery worker with PyCharm debugging on port $${PYCHARM_DEBUG_PORT:-5678} using $$UV_PYTHON (unbuffered stdout, solo pool)..."; \
	PYTHONUNBUFFERED=1 "$$UV_PYTHON" -Xfrozen_modules=off bin/local/run_worker_debug.py

.PHONY: local-preflight
local-preflight: # Check local dev ports and fail fast if they are in use.
	@set -a; [ -f .env ] && . ./.env; set +a; \
	APP_PORT_TO_CHECK="$${LOCAL_APP_PORT:-$${APP_PORT:-8000}}"; \
	echo "Checking local ports: app=$$APP_PORT_TO_CHECK"; \
	if lsof -tiTCP:"$$APP_PORT_TO_CHECK" -sTCP:LISTEN >/dev/null 2>&1; then \
		echo "Port $$APP_PORT_TO_CHECK is already in use by PID(s): $$(lsof -tiTCP:$$APP_PORT_TO_CHECK -sTCP:LISTEN | tr '\n' ' ')"; \
		exit 1; \
	fi

.PHONY: local-stop
local-stop: # Stop local tmux session and dockerized web processes that can conflict with local dev.
	@echo "Stopping local dev tmux session (if running)..."
	@tmux has-session -t "$(TMUX_LOCAL_DEV_SESSION)" 2>/dev/null && tmux kill-session -t "$(TMUX_LOCAL_DEV_SESSION)" || true
	@set -a; [ -f .env ] && . ./.env; set +a; \
	APP_PORT_TO_STOP="$${LOCAL_APP_PORT:-$${APP_PORT:-8000}}"; \
	echo "Stopping local listeners on port $$APP_PORT_TO_STOP (if running)..."; \
	for p in "$$APP_PORT_TO_STOP"; do \
		pids="$$(lsof -tiTCP:$$p -sTCP:LISTEN 2>/dev/null | tr '\n' ' ')"; \
		if [ -n "$$pids" ]; then \
			echo "Killing PID(s) on port $$p: $$pids"; \
			kill $$pids >/dev/null 2>&1 || true; \
		fi; \
	done
	@echo "Stopping containerized web services that can conflict with local Django..."
	@docker compose stop web nginx flower celery_beat sequential_worker parallel_worker fast_worker >/dev/null 2>&1 || true

.PHONY: install-worker-debugger
install-worker-debugger: # Install debugger helpers used by local-worker-debug.
	@echo "Installing PyCharm debugger helper into local Python environment with uv using $$UV_PYTHON..."
	@uv pip install --python "$$UV_PYTHON" --upgrade pydevd-pycharm
	@"$$UV_PYTHON" -c "import sys, pydevd_pycharm; print('python:', sys.executable); print('pydevd_pycharm import:', pydevd_pycharm.__name__)"
	@echo "PyCharm debugger helper installation complete."

.PHONY: local-dev
local-dev: # Use pyenv montrek-3.12.0 and start full local dev
	@echo "▶ Setting pyenv local version to montrek-3.12.0..."
	@pyenv local montrek-3.12.0
	@$(eval UV_PYTHON = $(shell pyenv which python))
	@echo "▶ Using UV_PYTHON=$(UV_PYTHON)"
	@$(MAKE) local-stop
	@echo "▶ Syncing local Python virtual environment..."
	@$(MAKE) sync-local-python-env
	@echo "▶ Installing PyCharm debugger helper..."
	@$(MAKE) install-worker-debugger
	@echo "▶ Running local preflight checks..."
	@$(MAKE) local-preflight
	@echo "▶ Launching full local development environment..."
	@tmux new-session -d -s "$(TMUX_LOCAL_DEV_SESSION)" \; \
		send-keys '$(MAKE) local-infra-up' C-m \; \
		split-window -v \; \
		send-keys '$(MAKE) local-runserver' C-m \; \
		split-window -h \; \
		send-keys '$(MAKE) local-worker-debug' C-m
	@tmux attach-session -t "$(TMUX_LOCAL_DEV_SESSION)"

.PHONY: sync-local-python-env
sync-local-python-env: # Regenerate requirements.txt from all requirements.in files.
	@$(SECURE_WRAPPER) bin/local/sync-python-env.sh

.PHONY: sync-local-venv
sync-local-venv: # Ensure .venv exists and sync it from requirements.txt.
	@if [ -d ".venv" ] && [ ! -x ".venv/bin/python" ]; then \
		echo "Detected broken .venv (missing .venv/bin/python). Recreating..."; \
		rm -rf .venv; \
	fi
	@if [ ! -x ".venv/bin/python" ]; then \
		echo "Creating .venv with $(UV_PYTHON)..."; \
		uv venv .venv --python "$(UV_PYTHON)"; \
	fi
	@uv pip sync requirements.txt --python .venv/bin/python
	@.venv/bin/python -V
	@.venv/bin/python -c "import IPython, ipykernel; print('IPython', IPython.__version__); print('ipykernel', ipykernel.__version__)"

.PHONY: sync-local-python-env-and-venv
sync-local-python-env-and-venv: sync-local-python-env sync-local-venv # Regenerate requirements.txt and then sync .venv from it in one run.

.PHONY: install-notebook-kernel
install-notebook-kernel: sync-local-venv # Register a Jupyter kernel from project .venv with correct PYTHONPATH and auto Django setup.
	@echo "▶ Ensuring ipykernel is installed in .venv..."
	@bash -lc '. .venv/bin/activate && python -m pip install --upgrade ipykernel'
	@echo "▶ Installing Jupyter kernel 'montrek-3.12.0' from .venv..."
	@bash -lc '. .venv/bin/activate && python -m ipykernel install --user --name montrek-3.12.0 --display-name "Python (montrek .venv)"'
	@echo "▶ Configuring kernel.json (PYTHONPATH + DJANGO_SETTINGS_MODULE)..."
	@bash -lc '. .venv/bin/activate && python -c "\
import json, pathlib; \
kf = pathlib.Path.home() / '.local/share/jupyter/kernels/montrek-3.12.0/kernel.json'; \
k = json.loads(kf.read_text()); \
k.setdefault('env', {}).update({'PYTHONPATH': '$(CURDIR)/montrek', 'DJANGO_SETTINGS_MODULE': 'montrek.settings'}); \
kf.write_text(json.dumps(k, indent=2)); \
print(f'  kernel.json -> {kf}'); \
print(f'  PYTHONPATH  -> ' + k['env']['PYTHONPATH']); \
"'
	@echo "▶ Installing IPython startup script for automatic django.setup()..."
	@mkdir -p "$(HOME)/.ipython/profile_default/startup"
	@if [ -f "$(CURDIR)/bin/local/00-django-setup.py" ]; then \
		cp "$(CURDIR)/bin/local/00-django-setup.py" "$(HOME)/.ipython/profile_default/startup/00-django-setup.py"; \
		echo "  startup script → $(HOME)/.ipython/profile_default/startup/00-django-setup.py"; \
	else \
		echo "  startup script source not found at $(CURDIR)/bin/local/00-django-setup.py (skipping copy)"; \
	fi
	@echo "Done. In PyCharm: stop the Jupyter server, then re-open the notebook and select 'Python (montrek .venv)'."

.PHONY: local-sonarqube-scan
local-sonarqube-scan: # Run a SonarQube scan and open in SonarQube (Add NO_TESTS=true to skip tests)
	@$(SECURE_WRAPPER) bin/local/sonarqube_scan.sh NO_TESTS=$(NO_TESTS) $(filter-out $@,$(MAKECMDGOALS))

.PHONY: docker-up
docker-up: # Start all docker containers in detached mode.
	@$(SECURE_WRAPPER) bin/docker/run.sh up -d

.PHONY: docker-down
docker-down: # Stop all docker containers.
	@$(SECURE_WRAPPER) bin/docker/run.sh down

.PHONY: docker-restart
docker-restart: # Shut the docker compose container down and up again
	@$(SECURE_WRAPPER) bin/docker/restart.sh

.PHONY: docker-logs
docker-logs: # Show docker compose logs
	@$(SECURE_WRAPPER) bin/docker/logs.sh $(filter-out $@,$(MAKECMDGOALS))

.PHONY: docker-build
docker-build: # Build the docker images
	@$(SECURE_WRAPPER) bin/docker/build.sh

.PHONY: docker-db-backup
docker-db-backup: # Make a backup of the docker database.
	@$(SECURE_WRAPPER) bin/docker/db.sh backup

.PHONY: docker-db-restore
docker-db-restore: # Restore the docker database from a backup.
	@$(SECURE_WRAPPER) bin/docker/db.sh restore

.PHONY: docker-django-manage
docker-django-manage: # Run Django management commands inside the docker container.
	@$(SECURE_WRAPPER) bin/docker/django-manage.sh $(filter-out $@,$(MAKECMDGOALS))

.PHONY: docker-cleanup
docker-cleanup: # Remove unused docker artifacts.
	@$(SECURE_WRAPPER) bin/docker/cleanup.sh

.PHONY: git-clone-repository
git-clone-repository: # Clone a montrek repository (expects a repository name like 'mt_economic_common').
	@$(SECURE_WRAPPER) bin/git/clone-repository.sh $(filter-out $@,$(MAKECMDGOALS))

.PHONY: git-update-repositories
git-update-repositories: # Update all montrek repositories to the latest git tags.
	@$(SECURE_WRAPPER) bin/git/update-repositories-to-latest-tags.sh

.PHONY: git-build-montrek-container
git-build-montrek-container: # Build the container to run montrek in docker or github actions
	@$(SECURE_WRAPPER) bin/git/build-montrek-container.sh

.PHONY: server-generate-https-certs
server-generate-https-certs: # Generate HTTPS certificates for the montrek django app.
	@$(SECURE_WRAPPER) bin/server/generate-https-certs.sh

.PHONY: server-update
server-update: # Stop all docker containers, update the repositories to the latest git tags, and start the containers again.
	@$(SECURE_WRAPPER) bin/server/update.sh

.PHONY: secrets-encrypt
secrets-encrypt: # Encrypt the .env file with a generated password
	@bash bin/secrets/encrypt.sh $(filter-out $@,$(MAKECMDGOALS))
.PHONY: secrets-decrypt
secrets-decrypt: # Decrypt the .env file
	@bash bin/secrets/decrypt.sh $(filter-out $@,$(MAKECMDGOALS))
.PHONY: secrets-edit-env
secrets-edit-env: # Edit the .env file
	@$(SECURE_WRAPPER) bin/secrets/edit-env.sh
%:
	@:
