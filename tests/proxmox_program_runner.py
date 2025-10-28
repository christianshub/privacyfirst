
import argparse
import base64
import os
import socket
import threading
import time
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

import requests
import winrm

requests.packages.urllib3.disable_warnings()

DEFAULT_FILES = [
    "PrivacyFirst.exe",
    "PrivacyFirst.dll",
    "PrivacyCore.dll",
    "PrivacyFirst.deps.json",
    "PrivacyFirst.runtimeconfig.json",
]


def parse_args():
    parser = argparse.ArgumentParser(description="Deploy and run PrivacyFirst in a Proxmox VM via WinRM")
    parser.add_argument("--proxmox-host", required=True)
    parser.add_argument("--proxmox-user", required=True)
    parser.add_argument("--proxmox-password", required=True)
    parser.add_argument("--vmid", type=int, required=True)
    parser.add_argument("--snapshot", default="baseline")
    parser.add_argument("--vm-ip", required=True)
    parser.add_argument("--vm-user", required=True)
    parser.add_argument("--vm-password", required=True)
    parser.add_argument("--build-path", default=r"c:\repos\privacyfirst\x64\Release")
    parser.add_argument("--files", nargs="*", default=DEFAULT_FILES)
    parser.add_argument("--executable", default="PrivacyFirst.exe")
    parser.add_argument("--remote-dir", default=r"C:\PrivacyFirstPipeline")
    parser.add_argument("--http-port", type=int, default=9910)
    parser.add_argument("--shutdown-vm", action="store_true")
    return parser.parse_args()


def get_local_ip(target_host: str) -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect((target_host, 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


class ArtifactServer(threading.Thread):
    def __init__(self, directory: str, bind_ip: str, port: int):
        super().__init__(daemon=True)
        handler = type('Handler', (SimpleHTTPRequestHandler,), {'directory': directory})
        self._server = ThreadingHTTPServer((bind_ip, port), handler)

    def run(self):
        self._server.serve_forever()

    def stop(self):
        self._server.shutdown()
        self._server.server_close()


class ProxmoxClient:
    def __init__(self, host: str, user: str, password: str):
        self.base = f"https://{host}:8006/api2/json"
        self.session = requests.Session()
        self.session.verify = False
        self.user = user
        self.password = password
        self.host = host
        self.csrf = None

    def login(self):
        resp = self.session.post(
            f"{self.base}/access/ticket",
            data={"username": self.user, "password": self.password}
        )
        resp.raise_for_status()
        payload = resp.json()["data"]
        self.session.cookies.set("PVEAuthCookie", payload["ticket"], domain=self.host, path="/")
        self.csrf = payload["CSRFPreventionToken"]

    def headers(self):
        return {"CSRFPreventionToken": self.csrf} if self.csrf else {}

    def get(self, path: str, **kwargs):
        resp = self.session.get(f"{self.base}{path}", headers=self.headers(), **kwargs)
        resp.raise_for_status()
        return resp.json()["data"]

    def post(self, path: str, *, json_body=None, data_body=None, params=None):
        kwargs = {"headers": self.headers()}
        if json_body is not None:
            kwargs["json"] = json_body
        if data_body is not None:
            kwargs["data"] = data_body
        if params is not None:
            kwargs["params"] = params
        resp = self.session.post(f"{self.base}{path}", **kwargs)
        resp.raise_for_status()
        return resp.json()["data"] if resp.content else None


def wait_for_task(client: ProxmoxClient, node: str, upid: str, timeout: int = 600):
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = client.get(f"/nodes/{node}/tasks/{upid}/status")
        if status.get("status") == "stopped":
            exitstatus = status.get("exitstatus", "OK")
            if exitstatus != "OK":
                raise RuntimeError(f"Proxmox task failed: {exitstatus}")
            return
        time.sleep(2)
    raise TimeoutError("Proxmox task timed out")


def ensure_running(client: ProxmoxClient, node: str, vmid: int, timeout: int = 120):
    status = client.get(f"/nodes/{node}/qemu/{vmid}/status/current")
    if status["status"] != "running":
        client.post(f"/nodes/{node}/qemu/{vmid}/status/start")
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = client.get(f"/nodes/{node}/qemu/{vmid}/status/current")
        if status["status"] == "running":
            return
        time.sleep(3)
    raise TimeoutError("VM failed to reach running state")


def wait_for_winrm(ip: str, user: str, password: str, timeout: int = 120):
    endpoint = f"http://{ip}:5985/wsman"
    deadline = time.time() + timeout
    last_err = None
    while time.time() < deadline:
        try:
            session = winrm.Session(endpoint, auth=(user, password), transport='ntlm')
            # light heartbeat command
            result = session.run_cmd('cmd', ['/c', 'echo ok'])
            if result.status_code == 0:
                return session
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            time.sleep(3)
    raise RuntimeError(f"WinRM not ready: {last_err}")


def build_powershell(host_ip: str, port: int, remote_dir: str, files, executable: str) -> str:
    file_list = ', '.join(f"'{f}'" for f in files)
    template = """
$ErrorActionPreference = 'Stop'
$dest = '{remote_dir}'
if (-not (Test-Path $dest)) {{ New-Item -ItemType Directory -Path $dest -Force | Out-Null }}
$files = @({file_list})
$baseUrl = 'http://{host}:{port}'
foreach ($file in $files) {{
    $source = "$baseUrl/$file"
    Invoke-WebRequest -Uri $source -OutFile (Join-Path $dest $file) -UseBasicParsing -ErrorAction Stop
}}
$exePath = Join-Path $dest '{executable}'
if (-not (Test-Path $exePath)) {{ throw "Executable not found: $exePath" }}
$stdout = Join-Path $dest 'stdout.txt'
$stderr = Join-Path $dest 'stderr.txt'
if (Test-Path $stdout) {{ Remove-Item $stdout -Force }}
if (Test-Path $stderr) {{ Remove-Item $stderr -Force }}
$proc = Start-Process -FilePath $exePath -WorkingDirectory $dest -PassThru -Wait -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$result = [PSCustomObject]@{{
    ExitCode = $proc.ExitCode
    StdOut = if (Test-Path $stdout) {{ Get-Content $stdout -Raw }} else ''
    StdErr = if (Test-Path $stderr) {{ Get-Content $stderr -Raw }} else ''
}}
$result | ConvertTo-Json -Depth 5
"""
    return template.format(host=host_ip, port=port, remote_dir=remote_dir, file_list=file_list, executable=executable)


def main():
    args = parse_args()

    if not os.path.isdir(args.build_path):
        raise FileNotFoundError(f"Build path not found: {args.build_path}")

    artifacts = [f for f in args.files if os.path.isfile(os.path.join(args.build_path, f))]
    if not artifacts:
        raise FileNotFoundError("No artifacts from the list were found in the build directory")

    client = ProxmoxClient(args.proxmox_host, args.proxmox_user, args.proxmox_password)
    client.login()

    node = client.get("/nodes")[0]["node"]
    print(f"Using Proxmox node {node}")

    print("Rolling back snapshot...")
    upid = client.post(f"/nodes/{node}/qemu/{args.vmid}/snapshot/{args.snapshot}/rollback")
    wait_for_task(client, node, upid)
    print("Snapshot rollback complete")

    print("Ensuring VM is running...")
    ensure_running(client, node, args.vmid)
    print("Waiting for WinRM...")
    session = wait_for_winrm(args.vm_ip, args.vm_user, args.vm_password)
    print("WinRM session ready")

    host_ip = get_local_ip(args.proxmox_host)
    print(f"Serving artifacts from {host_ip}:{args.http_port}")
    server = ArtifactServer(args.build_path, host_ip, args.http_port)
    server.start()
    time.sleep(1)

    script = build_powershell(host_ip, args.http_port, args.remote_dir, artifacts, args.executable)

    try:
        result = session.run_ps(script)
    finally:
        server.stop()

    stdout = result.std_out.decode(errors='ignore') if isinstance(result.std_out, bytes) else str(result.std_out)
    stderr = result.std_err.decode(errors='ignore') if isinstance(result.std_err, bytes) else str(result.std_err)
    exit_code = result.status_code

    print("Exit code:", exit_code)
    print("STDOUT:\n" + stdout)
    print("STDERR:\n" + stderr)


    if args.shutdown_vm:
        client.post(f"/nodes/{node}/qemu/{args.vmid}/status/shutdown")
        print("Shutdown requested")


if __name__ == '__main__':
    main()
