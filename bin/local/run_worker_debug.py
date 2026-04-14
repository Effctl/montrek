#!/usr/bin/env python3
from __future__ import annotations

import os
import shlex
import socket
import sys
import time
from pathlib import Path


def env_flag(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def running_in_wsl() -> bool:
    for probe in (Path("/proc/version"), Path("/proc/sys/kernel/osrelease")):
        try:
            if "microsoft" in probe.read_text(encoding="utf-8").lower():
                return True
        except OSError:
            continue
    return False


def default_pycharm_hosts() -> list[str]:
    hosts = []
    explicit_host = os.getenv("PYCHARM_DEBUG_HOST")
    if explicit_host:
        hosts.append(explicit_host)
    else:
        hosts.append("127.0.0.1")
        if running_in_wsl():
            try:
                for line in (
                    Path("/etc/resolv.conf").read_text(encoding="utf-8").splitlines()
                ):
                    if line.startswith("nameserver "):
                        host = line.split()[1]
                        if host not in hosts:
                            hosts.append(host)
                        break
            except OSError:
                pass
    return hosts


def wait_for_pycharm_server(port: int) -> str:
    hosts = default_pycharm_hosts()
    print(
        f"Waiting for PyCharm debug server on port {port} (tried hosts: {', '.join(hosts)})...",
        flush=True,
    )
    while True:
        for host in hosts:
            try:
                with socket.create_connection((host, port), timeout=1):
                    print(
                        f"Connected to PyCharm debug server at {host}:{port}.",
                        flush=True,
                    )
                    return host
            except OSError:
                continue
        time.sleep(1)


def enable_pycharm_debugging(port: int) -> None:
    import pydevd_pycharm

    host = wait_for_pycharm_server(port)
    pydevd_pycharm.settrace(
        host,
        port=port,
        stdoutToServer=True,
        stderrToServer=True,
        suspend=env_flag("PYCHARM_DEBUG_SUSPEND", default=False),
        trace_only_current_thread=False,
    )


def celery_argv() -> list[str]:
    extra_args = shlex.split(os.getenv("LOCAL_WORKER_ARGS", ""))
    return [
        "celery",
        "-A",
        "montrek.celery_app",
        "worker",
        "-l",
        os.getenv("CELERY_WORKER_LOG_LEVEL", "info"),
        "--pool=solo",
        "--concurrency=1",
        *extra_args,
    ]


def main() -> int:
    port = int(os.getenv("PYCHARM_DEBUG_PORT", "5678"))

    if env_flag("WORKER_DEBUG_DRY_RUN"):
        print(f"pycharm_debug_port={port} argv={' '.join(celery_argv())}", flush=True)
        return 0

    enable_pycharm_debugging(port)

    sys.argv = celery_argv()
    print(f"Launching Celery worker: {' '.join(sys.argv)}", flush=True)
    from celery.__main__ import main as celery_main

    celery_main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
