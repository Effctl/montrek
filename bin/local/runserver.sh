#!/bin/bash
# Load variables from .env file
if [ -f .env ]; then
	export $(grep -v '^#' .env | xargs)
else
	echo ".env file not found!"
	exit 1
fi

# Prefer a dedicated local dev port to avoid clashing with docker web.
RUNSERVER_PORT="${LOCAL_APP_PORT:-${APP_PORT:-}}"

# Check if required variables are set
if [[ -z "$RUNSERVER_PORT" ]]; then
	echo "One or more required environment variables are missing in .env:"
	echo "Set LOCAL_APP_PORT for local Django, or APP_PORT as a fallback."
	exit 1
fi

echo "Environment variables loaded successfully."
if [[ -n "${LOCAL_APP_PORT:-}" ]]; then
	echo "Using LOCAL_APP_PORT for local Django: $RUNSERVER_PORT"
else
	echo "Using APP_PORT for local Django: $RUNSERVER_PORT"
fi

cd montrek/ || exit 1
python manage.py migrate
python manage.py runserver "$RUNSERVER_PORT"
