import argparse
import base64
import json
import os
import socket
import subprocess
import sys
import threading
import time
import urllib3
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

import requests

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

DEFAULT_FILES = [
    "PrivacyFirst.exe",
    "PrivacyFirst.dll",
    "PrivacyCore.dll",
    "PrivacyFirst.deps.json",
    "PrivacyFirst.runtimeconfig.json",
]


def parse_args():
    parser = argparse.ArgumentParser(description="Run PrivacyFirst binary inside Proxmox VM via guest agent")
    parser.add_argument("--proxmox-host", required=True)
    parser.add_argument("--proxmox-user", required=True)
    parser.add_argument("--proxmox-password", required=True)
    parser.add_argument("--vmid", type=int, required=True)
    parser.add_argument("--snapshot", default="baseline")
    parser.add_argument("--build-path", default=r"c:\\repos\\privacyfirst\\x64\\Release")
    parser.add_argument("--files", nargs="*", default=DEFAULT_FILES)
    parser.add_argument("--executable", default="PrivacyFirst.exe")
    parser.add_argument("--remote-dir", default=r"C:\\PrivacyFirstPipeline")
    parser.add_argument("--shutdown-vm", action="store_true")
    parser.add_argument("--http-port", type=int, default=9910)
    return parser.parse_args()


def get_local_ip(target):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect((target, 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


class ArtifactServer(threading.Thread):
    def __init__(self, directory, bind_ip, port):
        super().__init__(daemon=True)
        self.directory = directory
        self.port = port
        self.bind_ip = bind_ip
        handler = type('Handler', (SimpleHTTPRequestHandler,), {'directory': directory})
        self._server = ThreadingHTTPServer((bind_ip, port), handler)

    def run(self):
        self._server.serve_forever()

    def stop(self):
        self._server.shutdown()
        self._server.server_close()


class ProxmoxClient:
    def __init__(self, host, user, password):
        self.base = f"https://{host}:8006/api2/json"
        self.session = requests.Session()
        self.session.verify = False
        self.user = user
        self.password = password
        self.host = host
        self.csrf = None

    def login(self):
        data = {"username": self.user, "password": self.password}
        resp = self.session.post(f"{self.base}/access/ticket", data=data)
        resp.raise_for_status()
        payload = resp.json()["data"]
        ticket = payload["ticket"]
        self.csrf = payload["CSRFPreventionToken"]
        self.session.cookies.set("PVEAuthCookie", ticket, domain=self.host, path="/")

    def _headers(self):
        return {"CSRFPreventionToken": self.csrf} if self.csrf else {}

    def get(self, path, **kwargs):
        resp = self.session.get(f"{self.base}{path}", headers=self._headers(), **kwargs)
        resp.raise_for_status()
        return resp.json()["data"]

    def post(self, path, *, json_body=None, data_body=None, params=None):
        kwargs = {"headers": self._headers()}
        if json_body is not None:
            kwargs["json"] = json_body
        if data_body is not None:
            kwargs["data"] = data_body
        if params is not None:
            kwargs["params"] = params
        resp = self.session.post(f"{self.base}{path}", **kwargs)
        resp.raise_for_status()
        return resp.json()["data"] if resp.content else None


def wait_for_task(client, node, upid, timeout=600):
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


def ensure_running(client, node, vmid, timeout=120):
    status = client.get(f"/nodes/{node}/qemu/{vmid}/status/current")
    if status["status"] != "running":
        client.post(f"/nodes/{node}/qemu/{vmid}/status/start")
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = client.get(f"/nodes/{node}/qemu/{vmid}/status/current")
        if status["status"] == "running":
            return
        time.sleep(2)
    raise TimeoutError("VM failed to reach running state")


def wait_for_agent(client, node, vmid, timeout=90):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            client.post(f"/nodes/{node}/qemu/{vmid}/agent/ping")
            return
        except requests.HTTPError:
            time.sleep(2)
    raise TimeoutError("Guest agent not responding")

def run_winrm_enable_script(proxmox_host: str, proxmox_user: str, proxmox_password: str, vmid: int):
    ssh_user = proxmox_user.split('@')[0] if '@' in proxmox_user else proxmox_user
    enable_script = """
$ErrorActionPreference = 'Stop'
Enable-PSRemoting -Force
winrm set winrm/config/service @{AllowUnencrypted="true"}
winrm set winrm/config/service/auth @{Basic="true"}
Set-NetFirewallRule -Name WINRM-HTTP-In-TCP -Enabled True
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
"""
    encoded = base64.b64encode(enable_script.encode('utf-16le')).decode()
    command = f"qm guest exec {vmid} -- powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand {encoded}"
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(proxmox_host, username=ssh_user, password=proxmox_password, timeout=60)
        stdin, stdout, stderr = ssh.exec_command(command)
        stdout.channel.recv_exit_status()
        out = stdout.read().decode(errors='ignore')
        err = stderr.read().decode(errors='ignore')
    finally:
        ssh.close()
    if err.strip():
        print('WinRM prep stderr:', err.strip())





def run_guest_command(client, node, vmid, command, args, timeout=300):
    payload = {
        "command": command,
        "extra-args": args,
    }
    resp = client.post(f"/nodes/{node}/qemu/{vmid}/agent/exec", json_body=payload)
    pid = resp["pid"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        status = client.get(f"/nodes/{node}/qemu/{vmid}/agent/exec-status", params={"pid": pid})
        if status.get("exited"):
            out_data = status.get("out-data")
            err_data = status.get("err-data")
            stdout = base64.b64decode(out_data).decode(errors="ignore") if out_data else ""
            stderr = base64.b64decode(err_data).decode(errors="ignore") if err_data else ""
            exitcode = status.get("exitcode")
            return exitcode, stdout, stderr
        time.sleep(2)
    raise TimeoutError("Guest command timed out")


def main():
    args = parse_args()
    if not os.path.isdir(args.build_path):
        raise FileNotFoundError(f"Build path not found: {args.build_path}")

    files = [f for f in args.files if os.path.exists(os.path.join(args.build_path, f))]
    if not files:
        raise FileNotFoundError("None of the specified artifacts were found in the build directory")

    client = ProxmoxClient(args.proxmox_host, args.proxmox_user, args.proxmox_password)
    client.login()

    node = client.get("/nodes")[0]["node"]

    upid = client.post(f"/nodes/{node}/qemu/{args.vmid}/snapshot/{args.snapshot}/rollback")
    wait_for_task(client, node, upid)

    ensure_running(client, node, args.vmid)
    wait_for_agent(client, node, args.vmid)

    host_ip = get_local_ip(args.proxmox_host)
    print(f"Using host IP {host_ip}")

    server = ArtifactServer(args.build_path, host_ip, args.http_port)
    server.start()
    time.sleep(1)

    ps_files = ', '.join(f"'{f}'" for f in files)
    ps_script = f"""
Continue = 'Stop'
 = '{args.remote_dir}'
if (-not (Test-Path )) {{ New-Item -ItemType Directory -Path  -Force | Out-Null }}
 = @({ps_files})
 = 'http://{host_ip}:{args.http_port}'
foreach ( in ) {{
     = "/"
    Invoke-WebRequest -Uri  -OutFile (Join-Path  ) -UseBasicParsing -ErrorAction Stop
}}
 = Join-Path  '{args.executable}'
if (-not (Test-Path )) {{ throw "Executable not found: " }}
 = Start-Process -FilePath  -WorkingDirectory  -PassThru -Wait -NoNewWindow -RedirectStandardOutput (Join-Path  'stdout.txt') -RedirectStandardError (Join-Path  'stderr.txt')
 = [PSCustomObject]@{{
    ExitCode = .ExitCode
    StdOut = Get-Content (Join-Path  'stdout.txt') -Raw
    StdErr = Get-Content (Join-Path  'stderr.txt') -Raw
}}
 | ConvertTo-Json -Depth 5
"""

    encoded = base64.b64encode(ps_script.encode('utf-16le')).decode()
    args_list = [
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-EncodedCommand", encoded,
    ]

    try:
        exitcode, stdout, stderr = run_guest_command(client, node, args.vmid, "powershell.exe", args_list)
    finally:
        server.stop()

    print("Exit code:", exitcode)
    print("STDOUT:\n" + stdout)
    print("STDERR:\n" + stderr)

    if args.shutdown_vm:
        client.post(f"/nodes/{node}/qemu/{args.vmid}/status/shutdown")
        print("Shutdown requested")


if __name__ == "__main__":
    main()
