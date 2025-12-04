#!/usr/bin/env python3
"""
/opt/ds01-infra/scripts/docker/docker-filter-proxy.py
DS01 Docker Filter Proxy - Container Visibility Filtering

A transparent proxy that sits on the Docker socket path and filters container
listings based on the connecting user's identity (detected via SO_PEERCRED).

This proxy:
- Replaces /var/run/docker.sock with a filtered socket
- Detects connecting user automatically via Unix socket credentials
- Filters /containers/json responses to only show owned containers
- Allows admins and service users to see all containers
- Passes all other requests through unchanged

Installation:
1. Move real Docker socket: mv /var/run/docker.sock /var/run/docker-real.sock
2. Update Docker daemon: Add "hosts": ["unix:///var/run/docker-real.sock"]
3. Start this proxy: python3 docker-filter-proxy.py
4. Proxy creates /var/run/docker.sock

Usage:
  # As systemd service (recommended)
  sudo systemctl start ds01-docker-filter

  # Manual start
  sudo python3 docker-filter-proxy.py

  # Debug mode
  sudo python3 docker-filter-proxy.py --debug
"""

import argparse
import grp
import json
import os
import pwd
import re
import signal
import socket
import stat
import struct
import sys
import threading
from pathlib import Path
from typing import Dict, Optional, Set

# Configuration
REAL_DOCKER_SOCKET = "/var/run/docker-real.sock"
PROXY_SOCKET = "/var/run/docker.sock"
OWNERSHIP_DATA_FILE = Path("/var/lib/ds01/opa/container-owners.json")
RESOURCE_LIMITS_FILE = Path("/opt/ds01-infra/config/resource-limits.yaml")

# Debug flag
DEBUG = False


def log(msg: str, level: str = "INFO"):
    """Log message to stderr"""
    if level == "DEBUG" and not DEBUG:
        return
    import datetime
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] [{level}] {msg}", file=sys.stderr, flush=True)


def get_peer_credentials(sock: socket.socket) -> Optional[tuple]:
    """Get UID/GID of the connecting process via SO_PEERCRED"""
    try:
        # SO_PEERCRED returns struct ucred: pid, uid, gid (each 4 bytes, total 12)
        SO_PEERCRED = 17  # Linux specific
        creds = sock.getsockopt(socket.SOL_SOCKET, SO_PEERCRED, struct.calcsize("3i"))
        pid, uid, gid = struct.unpack("3i", creds)
        return pid, uid, gid
    except Exception as e:
        log(f"Could not get peer credentials: {e}", "DEBUG")
        return None


def uid_to_username(uid: int) -> str:
    """Convert UID to username"""
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


def get_admin_users() -> Set[str]:
    """Get set of admin usernames"""
    admins = set()

    # Source 1: resource-limits.yaml
    try:
        import yaml
        with open(RESOURCE_LIMITS_FILE) as f:
            config = yaml.safe_load(f)
        members = config.get("groups", {}).get("admin", {}).get("members", [])
        admins.update(members)
    except Exception:
        pass

    # Source 2: ds01-admin Linux group
    try:
        group_info = grp.getgrnam("ds01-admin")
        admins.update(group_info.gr_mem)
    except KeyError:
        pass

    return admins


def get_admin_uids() -> Set[int]:
    """Get set of admin UIDs"""
    admin_uids = {0}  # root is always admin
    for username in get_admin_users():
        try:
            admin_uids.add(pwd.getpwnam(username).pw_uid)
        except KeyError:
            pass

    # Add ds01-dashboard service user
    try:
        admin_uids.add(pwd.getpwnam("ds01-dashboard").pw_uid)
    except KeyError:
        pass

    return admin_uids


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
    except Exception:
        return {}


def should_show_container(container: Dict, username: str, is_admin: bool,
                          owners: Dict[str, str]) -> bool:
    """Determine if container should be shown to user"""
    if is_admin:
        return True

    # Get container identifier
    container_id = container.get("Id", "")[:12]
    names = container.get("Names", [])
    container_name = names[0].lstrip("/") if names else ""

    # Check ownership data
    owner = owners.get(container_id) or owners.get(container_name)
    if owner == username:
        return True

    # Check labels
    labels = container.get("Labels", {}) or {}
    label_owner = labels.get("ds01.user") or labels.get("aime.mlc.USER")
    if label_owner == username:
        return True

    # Check devcontainer path
    local_folder = labels.get("devcontainer.local_folder", "")
    if local_folder.startswith(f"/home/{username}/"):
        return True

    return False


def filter_container_list(body: bytes, username: str, is_admin: bool) -> bytes:
    """Filter container list to only show owned containers"""
    if is_admin:
        return body

    try:
        containers = json.loads(body)
        if not isinstance(containers, list):
            return body

        owners = get_container_owners()
        filtered = [c for c in containers
                   if should_show_container(c, username, is_admin, owners)]

        log(f"Filtered containers for {username}: {len(filtered)}/{len(containers)}", "DEBUG")
        return json.dumps(filtered).encode()
    except json.JSONDecodeError:
        return body
    except Exception as e:
        log(f"Filter error: {e}", "DEBUG")
        return body


def extract_container_id_from_path(path: str) -> Optional[str]:
    """Extract container ID from Docker API path"""
    # Patterns like /containers/<id>/start, /containers/<id>/exec, etc.
    match = re.search(r'/containers/([a-zA-Z0-9_.-]+)/', path)
    if match:
        container_id = match.group(1)
        if container_id not in ('json', 'create'):
            return container_id
    # Pattern for DELETE /containers/<id>
    match = re.search(r'/containers/([a-zA-Z0-9_.-]+)$', path)
    if match:
        return match.group(1)
    return None


def is_restricted_operation(method: str, path: str) -> bool:
    """Check if this is an operation that requires ownership"""
    restricted_paths = [
        '/start', '/stop', '/kill', '/restart', '/pause', '/unpause',
        '/exec', '/attach', '/logs', '/wait', '/resize', '/export',
        '/changes', '/top', '/archive'
    ]
    # DELETE /containers/<id> is also restricted
    if method == "DELETE" and "/containers/" in path:
        return True
    return any(rp in path for rp in restricted_paths)


def check_container_ownership(container_id: str, username: str, is_admin: bool) -> tuple:
    """
    Check if user owns the container.
    Returns (allowed: bool, owner: str or None)
    """
    if is_admin:
        return True, None

    owners = get_container_owners()

    # Check by ID (short and full)
    owner = owners.get(container_id) or owners.get(container_id[:12])
    if owner:
        return owner == username, owner

    # Check by name
    owner = owners.get(container_id)
    if owner:
        return owner == username, owner

    # If container not in ownership data, allow (fail-open for safety)
    return True, None


def create_error_response(status_code: int, message: str) -> bytes:
    """Create an HTTP error response"""
    body = json.dumps({"message": message}).encode()
    response = f"HTTP/1.1 {status_code} Forbidden\r\n"
    response += f"Content-Type: application/json\r\n"
    response += f"Content-Length: {len(body)}\r\n"
    response += "\r\n"
    return response.encode() + body


def passthrough_bidirectional(client_sock: socket.socket, docker_sock: socket.socket):
    """
    Pass through data bidirectionally between client and Docker.
    Used for HTTP/2 (gRPC/BuildKit) connections that we can't parse.
    Uses threads for more reliable handling.
    """
    import select

    closed = threading.Event()

    def forward(src, dst, name):
        """Forward data from src to dst"""
        try:
            src.settimeout(300.0)  # 5 min timeout for builds
            while not closed.is_set():
                try:
                    data = src.recv(65536)
                    if not data:
                        log(f"Passthrough {name}: connection closed by peer", "DEBUG")
                        break
                    dst.sendall(data)
                except socket.timeout:
                    continue
                except Exception as e:
                    log(f"Passthrough {name} error: {e}", "DEBUG")
                    break
        finally:
            closed.set()

    # Start forwarding threads
    client_to_docker = threading.Thread(
        target=forward,
        args=(client_sock, docker_sock, "client->docker"),
        daemon=True
    )
    docker_to_client = threading.Thread(
        target=forward,
        args=(docker_sock, client_sock, "docker->client"),
        daemon=True
    )

    client_to_docker.start()
    docker_to_client.start()

    # Wait for either direction to close
    client_to_docker.join()
    docker_to_client.join(timeout=1.0)

    log("Passthrough complete", "DEBUG")


def handle_client(client_sock: socket.socket, admin_uids: Set[int]):
    """Handle a single client connection"""
    try:
        # Get connecting user
        creds = get_peer_credentials(client_sock)
        if creds:
            pid, uid, gid = creds
            username = uid_to_username(uid)
            is_admin = uid in admin_uids
            log(f"Connection from {username} (uid={uid}, pid={pid})", "DEBUG")
        else:
            username = "unknown"
            is_admin = False
            log("Connection from unknown user (no credentials)", "DEBUG")

        # Read initial data to detect protocol
        request = b""
        client_sock.settimeout(5.0)
        try:
            chunk = client_sock.recv(4096)
            if not chunk:
                return
            request = chunk
        except socket.timeout:
            return
        client_sock.settimeout(None)

        # Detect HTTP/2 connection preface: "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
        # BuildKit/gRPC uses HTTP/2
        if request.startswith(b"PRI * HTTP/2.0"):
            log(f"HTTP/2 connection from {username} - passing through", "DEBUG")
            # Connect to real Docker and pass through
            docker_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            docker_sock.connect(REAL_DOCKER_SOCKET)
            docker_sock.sendall(request)
            passthrough_bidirectional(client_sock, docker_sock)
            docker_sock.close()
            return

        # For HTTP/1.1, continue reading headers
        while b"\r\n\r\n" not in request:
            chunk = client_sock.recv(4096)
            if not chunk:
                break
            request += chunk

        if not request:
            return

        # Parse headers
        headers_end = request.index(b"\r\n\r\n") + 4
        headers_part = request[:headers_end]
        body_so_far = request[headers_end:]

        # Determine how to read the body
        content_length_match = re.search(rb"Content-Length:\s*(\d+)", headers_part, re.IGNORECASE)
        is_chunked_request = b"Transfer-Encoding: chunked" in headers_part

        if content_length_match:
            content_length = int(content_length_match.group(1))
            # Read remaining body based on Content-Length
            while len(body_so_far) < content_length:
                chunk = client_sock.recv(65536)
                if not chunk:
                    break
                body_so_far += chunk
            request = headers_part + body_so_far
        elif is_chunked_request:
            # Read chunked request body until terminator (0\r\n\r\n)
            client_sock.settimeout(30.0)  # Longer timeout for builds
            while not body_so_far.endswith(b"0\r\n\r\n"):
                try:
                    chunk = client_sock.recv(65536)
                    if not chunk:
                        break
                    body_so_far += chunk
                except socket.timeout:
                    log(f"Timeout reading chunked request from {username}", "DEBUG")
                    break
            client_sock.settimeout(None)
            request = headers_part + body_so_far
        # else: no body expected (GET, HEAD, etc.)

        if not request:
            return

        request_line = request.split(b"\r\n")[0].decode("utf-8", errors="replace")
        parts = request_line.split()
        method = parts[0] if parts else ""
        path = parts[1] if len(parts) > 1 else ""
        log(f"Request: {request_line} (user={username})", "DEBUG")

        # Check if this is a restricted operation on a specific container
        container_id = extract_container_id_from_path(path)
        if container_id and is_restricted_operation(method, path):
            allowed, owner = check_container_ownership(container_id, username, is_admin)
            if not allowed:
                log(f"DENIED: {username} tried to access container owned by {owner}")
                error_response = create_error_response(
                    403, f"Permission denied: container owned by {owner}"
                )
                client_sock.sendall(error_response)
                return

        # Check if this is a gRPC or session endpoint (BuildKit uses these for builds)
        # These require bidirectional streaming
        is_grpc = (path == '/grpc' or path.startswith('/grpc') or
                   path == '/session' or path.startswith('/session'))

        # Build operations also need bidirectional streaming for BuildKit
        is_build = '/build' in path

        # Other streaming operations (unidirectional docker->client)
        is_streaming_op = any(op in path for op in ['/exec/', '/attach/', '/logs'])

        # Connect to real Docker
        docker_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        docker_sock.connect(REAL_DOCKER_SOCKET)

        # Forward request to Docker
        docker_sock.sendall(request)

        if is_grpc or is_build:
            # gRPC and build operations require bidirectional streaming (BuildKit)
            log(f"Bidirectional streaming for: {path}", "DEBUG")
            passthrough_bidirectional(client_sock, docker_sock)
            docker_sock.close()
            return

        if is_streaming_op:
            # For streaming operations, pass through data bidirectionally
            log(f"Streaming operation: {path}", "DEBUG")
            docker_sock.settimeout(300.0)  # 5 min timeout for builds
            try:
                while True:
                    chunk = docker_sock.recv(65536)
                    if not chunk:
                        break
                    client_sock.sendall(chunk)
            except socket.timeout:
                log(f"Streaming timeout for {path}", "DEBUG")
            except Exception as e:
                log(f"Streaming error: {e}", "DEBUG")
            finally:
                docker_sock.close()
            return  # Already sent response directly

        # Read response - need to properly handle HTTP response
        response = b""
        docker_sock.settimeout(30.0)  # Longer timeout for container creation

        # First, read headers
        while b"\r\n\r\n" not in response:
            try:
                chunk = docker_sock.recv(4096)
                if not chunk:
                    break
                response += chunk
            except socket.timeout:
                log(f"Timeout reading response headers for {path}", "DEBUG")
                break

        # Parse headers to determine body length
        if b"\r\n\r\n" in response:
            header_end = response.index(b"\r\n\r\n") + 4
            headers_part = response[:header_end]
            body_so_far = response[header_end:]

            # Check for Content-Length
            content_length_match = re.search(rb"Content-Length:\s*(\d+)", headers_part, re.IGNORECASE)
            is_chunked = b"Transfer-Encoding: chunked" in headers_part

            if content_length_match:
                content_length = int(content_length_match.group(1))
                # Read remaining body
                docker_sock.settimeout(10.0)
                while len(body_so_far) < content_length:
                    try:
                        chunk = docker_sock.recv(65536)
                        if not chunk:
                            break
                        body_so_far += chunk
                    except socket.timeout:
                        log(f"Timeout reading response body for {path}", "DEBUG")
                        break
                response = headers_part + body_so_far
            elif is_chunked:
                # Read until we get the final chunk (0\r\n\r\n)
                docker_sock.settimeout(5.0)
                while not body_so_far.endswith(b"0\r\n\r\n"):
                    try:
                        chunk = docker_sock.recv(65536)
                        if not chunk:
                            break
                        body_so_far += chunk
                    except socket.timeout:
                        # For chunked, if we timeout, assume we have all data
                        break
                response = headers_part + body_so_far

        docker_sock.close()

        # Filter container list if needed
        is_container_list = method == "GET" and "/containers/json" in path

        if is_container_list and not is_admin:
            if b"\r\n\r\n" in response:
                header_end = response.index(b"\r\n\r\n")
                headers = response[:header_end]
                body = response[header_end + 4:]

                if b"Transfer-Encoding: chunked" in headers:
                    decoded_body = decode_chunked(body)
                    filtered_body = filter_container_list(decoded_body, username, is_admin)
                    new_body = encode_chunked(filtered_body)
                    response = headers + b"\r\n\r\n" + new_body
                else:
                    filtered_body = filter_container_list(body, username, is_admin)
                    headers = re.sub(
                        rb"Content-Length: \d+",
                        f"Content-Length: {len(filtered_body)}".encode(),
                        headers
                    )
                    response = headers + b"\r\n\r\n" + filtered_body

        # Send response to client
        client_sock.sendall(response)

    except Exception as e:
        log(f"Handler error: {e}")
    finally:
        try:
            client_sock.close()
        except Exception:
            pass


def decode_chunked(data: bytes) -> bytes:
    """Decode chunked transfer encoding"""
    result = b""
    pos = 0
    while pos < len(data):
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


def encode_chunked(data: bytes) -> bytes:
    """Encode as chunked transfer encoding"""
    return f"{len(data):x}\r\n".encode() + data + b"\r\n0\r\n\r\n"


def main():
    global DEBUG

    parser = argparse.ArgumentParser(
        description="DS01 Docker Filter Proxy",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        "--debug", "-d",
        action="store_true",
        help="Enable debug logging"
    )
    parser.add_argument(
        "--socket", "-s",
        default=PROXY_SOCKET,
        help=f"Proxy socket path (default: {PROXY_SOCKET})"
    )
    parser.add_argument(
        "--backend", "-b",
        default=REAL_DOCKER_SOCKET,
        help=f"Real Docker socket (default: {REAL_DOCKER_SOCKET})"
    )

    args = parser.parse_args()
    DEBUG = args.debug

    proxy_socket = args.socket
    backend_socket = args.backend

    # Validate backend exists
    if not Path(backend_socket).exists():
        log(f"Backend socket not found: {backend_socket}")
        log("Please configure Docker to listen on this socket")
        sys.exit(1)

    # Remove existing proxy socket
    if Path(proxy_socket).exists():
        Path(proxy_socket).unlink()

    # Create proxy socket
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(proxy_socket)
    server.listen(128)

    # Set permissions (world-accessible like original Docker socket)
    os.chmod(proxy_socket, stat.S_IRWXU | stat.S_IRWXG | stat.S_IRWXO)

    # Get admin UIDs at startup (refreshed periodically via ownership sync)
    admin_uids = get_admin_uids()

    log(f"DS01 Docker Filter Proxy started")
    log(f"  Proxy socket: {proxy_socket}")
    log(f"  Backend socket: {backend_socket}")
    log(f"  Admin UIDs: {admin_uids}")

    # Handle signals
    running = True

    def signal_handler(signum, frame):
        nonlocal running
        log("Shutting down...")
        running = False
        server.close()

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Periodically refresh admin list
    def refresh_admins():
        nonlocal admin_uids
        while running:
            import time
            time.sleep(60)
            if running:
                admin_uids = get_admin_uids()
                log(f"Refreshed admin UIDs: {admin_uids}", "DEBUG")

    refresh_thread = threading.Thread(target=refresh_admins, daemon=True)
    refresh_thread.start()

    # Accept connections
    while running:
        try:
            server.settimeout(1.0)
            client_sock, _ = server.accept()
            # Handle in thread
            thread = threading.Thread(
                target=handle_client,
                args=(client_sock, admin_uids),
                daemon=True
            )
            thread.start()
        except socket.timeout:
            continue
        except OSError:
            if running:
                raise
            break

    # Cleanup
    if Path(proxy_socket).exists():
        Path(proxy_socket).unlink()
    log("Proxy stopped")


if __name__ == "__main__":
    main()
