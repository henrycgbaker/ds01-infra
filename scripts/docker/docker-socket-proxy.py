#!/usr/bin/env python3
"""
/opt/ds01-infra/scripts/docker/docker-socket-proxy.py
DS01 Docker Socket Proxy - Per-User Container Filtering

This proxy sits between users and the Docker socket, filtering container
listings to only show containers owned by the requesting user.

Features:
- Filters /containers/json responses by ownership
- Admins and service users see all containers
- Passes through all other requests unchanged
- Works with VS Code Dev Containers extension

Architecture:
  User/VS Code → Unix Socket (/var/run/docker-proxy/$USER.sock) → This Proxy → Docker Socket

Usage:
  # Start proxy for a specific user
  python3 docker-socket-proxy.py --user alice --socket /var/run/docker-proxy/alice.sock

  # Start proxy for all docker group users (systemd service mode)
  python3 docker-socket-proxy.py --all-users

  # Debug mode
  python3 docker-socket-proxy.py --user alice --debug
"""

import argparse
import asyncio
import grp
import json
import os
import pwd
import signal
import socket
import stat
import sys
import threading
from pathlib import Path
from typing import Dict, List, Optional, Set
from urllib.parse import parse_qs, urlparse
import http.client
import re

# Configuration
DOCKER_SOCKET = "/var/run/docker.sock"
PROXY_SOCKET_DIR = Path("/var/run/docker-proxy")
OWNERSHIP_DATA_FILE = Path("/var/lib/ds01/opa/container-owners.json")
RESOURCE_LIMITS_FILE = Path("/opt/ds01-infra/config/resource-limits.yaml")

# Debug flag
DEBUG = False


def log(msg: str, level: str = "INFO"):
    """Log message to stderr"""
    if level == "DEBUG" and not DEBUG:
        return
    print(f"[{level}] {msg}", file=sys.stderr)


def get_admin_users() -> Set[str]:
    """Get set of admin usernames from both sources"""
    admins = set()

    # Source 1: resource-limits.yaml
    try:
        import yaml
        with open(RESOURCE_LIMITS_FILE) as f:
            config = yaml.safe_load(f)
        members = config.get("groups", {}).get("admin", {}).get("members", [])
        admins.update(members)
    except Exception as e:
        log(f"Could not read resource-limits.yaml: {e}", "DEBUG")

    # Source 2: ds01-admin Linux group
    try:
        group_info = grp.getgrnam("ds01-admin")
        admins.update(group_info.gr_mem)
    except KeyError:
        log("ds01-admin group not found", "DEBUG")

    return admins


def get_service_users() -> Set[str]:
    """Get set of service usernames"""
    return {"ds01-dashboard", "root"}


def get_container_owners() -> Dict[str, str]:
    """Load container ownership data"""
    try:
        with open(OWNERSHIP_DATA_FILE) as f:
            data = json.load(f)
        owners = {}
        for container_id, info in data.get("containers", {}).items():
            if info.get("owner"):
                owners[container_id] = info["owner"]
        return owners
    except Exception as e:
        log(f"Could not read ownership data: {e}", "DEBUG")
        return {}


def should_show_container(container: Dict, username: str, admins: Set[str],
                          service_users: Set[str], owners: Dict[str, str]) -> bool:
    """Determine if container should be shown to user"""
    # Admins and service users see everything
    if username in admins or username in service_users:
        return True

    # Get container identifier
    container_id = container.get("Id", "")[:12]
    container_name = container.get("Names", [""])[0].lstrip("/")

    # Check direct ownership
    owner = owners.get(container_id) or owners.get(container_name)
    if owner == username:
        return True

    # Check labels for ownership
    labels = container.get("Labels", {}) or {}
    label_owner = labels.get("ds01.user") or labels.get("aime.mlc.USER")
    if label_owner == username:
        return True

    # Check devcontainer path
    local_folder = labels.get("devcontainer.local_folder", "")
    if local_folder.startswith(f"/home/{username}/"):
        return True

    return False


def filter_container_list(response_data: bytes, username: str) -> bytes:
    """Filter container list response to only show owned containers"""
    try:
        containers = json.loads(response_data)
        if not isinstance(containers, list):
            return response_data

        admins = get_admin_users()
        service_users = get_service_users()
        owners = get_container_owners()

        filtered = [c for c in containers
                   if should_show_container(c, username, admins, service_users, owners)]

        log(f"Filtered containers for {username}: {len(filtered)}/{len(containers)}", "DEBUG")
        return json.dumps(filtered).encode()
    except json.JSONDecodeError:
        return response_data
    except Exception as e:
        log(f"Error filtering containers: {e}", "DEBUG")
        return response_data


class DockerProxyHandler:
    """Handles proxying requests between client and Docker socket"""

    def __init__(self, username: str):
        self.username = username
        self.admins = get_admin_users()
        self.service_users = get_service_users()

    def is_container_list_request(self, request_line: str) -> bool:
        """Check if request is a container list (docker ps)"""
        return "GET" in request_line and "/containers/json" in request_line

    def proxy_request(self, client_socket: socket.socket):
        """Proxy a request from client to Docker and back"""
        try:
            # Read client request
            request = b""
            while True:
                chunk = client_socket.recv(4096)
                if not chunk:
                    return
                request += chunk
                if b"\r\n\r\n" in request:
                    break

            request_line = request.split(b"\r\n")[0].decode("utf-8", errors="replace")
            log(f"Request from {self.username}: {request_line}", "DEBUG")

            # Connect to Docker socket
            docker_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            docker_sock.connect(DOCKER_SOCKET)
            docker_sock.sendall(request)

            # Read response
            response = b""
            while True:
                chunk = docker_sock.recv(65536)
                if not chunk:
                    break
                response += chunk

            docker_sock.close()

            # Filter container list if needed
            if self.is_container_list_request(request_line):
                # Split headers and body
                if b"\r\n\r\n" in response:
                    headers, body = response.split(b"\r\n\r\n", 1)

                    # Handle chunked encoding
                    if b"Transfer-Encoding: chunked" in headers:
                        # Decode chunked body
                        decoded_body = self._decode_chunked(body)
                        filtered_body = filter_container_list(decoded_body, self.username)
                        # Re-encode as chunked
                        encoded_body = self._encode_chunked(filtered_body)
                        response = headers + b"\r\n\r\n" + encoded_body
                    else:
                        # Simple body - update Content-Length
                        filtered_body = filter_container_list(body, self.username)
                        # Update Content-Length header
                        headers = re.sub(
                            b"Content-Length: \\d+",
                            f"Content-Length: {len(filtered_body)}".encode(),
                            headers
                        )
                        response = headers + b"\r\n\r\n" + filtered_body

            client_socket.sendall(response)

        except Exception as e:
            log(f"Proxy error for {self.username}: {e}", "DEBUG")
        finally:
            client_socket.close()

    def _decode_chunked(self, data: bytes) -> bytes:
        """Decode chunked transfer encoding"""
        result = b""
        pos = 0
        while pos < len(data):
            # Find chunk size line
            end = data.find(b"\r\n", pos)
            if end == -1:
                break
            size_str = data[pos:end].decode("utf-8", errors="replace").split(";")[0]
            try:
                chunk_size = int(size_str, 16)
            except ValueError:
                break
            if chunk_size == 0:
                break
            pos = end + 2
            result += data[pos:pos + chunk_size]
            pos += chunk_size + 2
        return result

    def _encode_chunked(self, data: bytes) -> bytes:
        """Encode data as chunked transfer encoding"""
        return f"{len(data):x}\r\n".encode() + data + b"\r\n0\r\n\r\n"


class UserSocketProxy:
    """Manages a Unix socket proxy for a single user"""

    def __init__(self, username: str, socket_path: Path):
        self.username = username
        self.socket_path = socket_path
        self.handler = DockerProxyHandler(username)
        self.running = False
        self.server_socket = None

    def start(self):
        """Start the proxy socket"""
        # Remove existing socket
        if self.socket_path.exists():
            self.socket_path.unlink()

        # Create socket directory
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)

        # Create Unix socket
        self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_socket.bind(str(self.socket_path))
        self.server_socket.listen(5)

        # Set ownership and permissions
        try:
            user_info = pwd.getpwnam(self.username)
            os.chown(self.socket_path, user_info.pw_uid, user_info.pw_gid)
            os.chmod(self.socket_path, stat.S_IRUSR | stat.S_IWUSR)
        except KeyError:
            log(f"User {self.username} not found, socket will be root-owned")

        log(f"Proxy started for {self.username} at {self.socket_path}")
        self.running = True

        while self.running:
            try:
                self.server_socket.settimeout(1.0)
                client_socket, _ = self.server_socket.accept()
                # Handle in thread to not block
                thread = threading.Thread(
                    target=self.handler.proxy_request,
                    args=(client_socket,)
                )
                thread.daemon = True
                thread.start()
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    log(f"Accept error: {e}")

    def stop(self):
        """Stop the proxy"""
        self.running = False
        if self.server_socket:
            self.server_socket.close()
        if self.socket_path.exists():
            self.socket_path.unlink()
        log(f"Proxy stopped for {self.username}")


class MultiUserProxyManager:
    """Manages proxy sockets for multiple users"""

    def __init__(self):
        self.proxies: Dict[str, UserSocketProxy] = {}
        self.running = False

    def get_docker_users(self) -> List[str]:
        """Get list of users in docker group"""
        try:
            docker_group = grp.getgrnam("docker")
            return list(docker_group.gr_mem)
        except KeyError:
            log("docker group not found")
            return []

    def start_for_user(self, username: str):
        """Start proxy for a single user"""
        socket_path = PROXY_SOCKET_DIR / f"{username}.sock"
        proxy = UserSocketProxy(username, socket_path)
        self.proxies[username] = proxy

        thread = threading.Thread(target=proxy.start)
        thread.daemon = True
        thread.start()

    def start_all(self):
        """Start proxies for all docker group users"""
        self.running = True
        users = self.get_docker_users()

        if not users:
            log("No users in docker group")
            return

        log(f"Starting proxies for {len(users)} users")
        for username in users:
            self.start_for_user(username)

        # Keep running until stopped
        while self.running:
            # Check for new users periodically
            current_users = set(self.get_docker_users())
            proxied_users = set(self.proxies.keys())

            for new_user in current_users - proxied_users:
                log(f"New user detected: {new_user}")
                self.start_for_user(new_user)

            import time
            time.sleep(60)  # Check every minute

    def stop_all(self):
        """Stop all proxies"""
        self.running = False
        for proxy in self.proxies.values():
            proxy.stop()


def main():
    global DEBUG

    parser = argparse.ArgumentParser(
        description="DS01 Docker Socket Proxy - Per-user container filtering"
    )
    parser.add_argument(
        "--user", "-u",
        help="Run proxy for specific user"
    )
    parser.add_argument(
        "--socket", "-s",
        help="Socket path (default: /var/run/docker-proxy/<user>.sock)"
    )
    parser.add_argument(
        "--all-users",
        action="store_true",
        help="Run proxies for all docker group users"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug logging"
    )

    args = parser.parse_args()
    DEBUG = args.debug

    if args.debug:
        log("Debug mode enabled", "DEBUG")

    # Handle signals
    def signal_handler(signum, frame):
        log("Shutting down...")
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    if args.all_users:
        manager = MultiUserProxyManager()
        try:
            manager.start_all()
        except KeyboardInterrupt:
            manager.stop_all()
    elif args.user:
        socket_path = Path(args.socket) if args.socket else PROXY_SOCKET_DIR / f"{args.user}.sock"
        proxy = UserSocketProxy(args.user, socket_path)
        try:
            proxy.start()
        except KeyboardInterrupt:
            proxy.stop()
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
