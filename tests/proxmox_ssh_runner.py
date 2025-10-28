import argparse
import base64
import json
import os
import time
import re

import paramiko
import proxmoxer

ARTIFACTS_DEFAULT = [
    "PrivacyFirst.exe",
    "PrivacyFirst.dll",
    "PrivacyCore.dll",
    "PrivacyFirst.deps.json",
    "PrivacyFirst.runtimeconfig.json",
]


def parse_args():
    parser = argparse.ArgumentParser(description="Deploy PrivacyFirst artifacts to a Proxmox VM via SSH")
    parser.add_argument("--proxmox-host", required=True)
    parser.add_argument("--proxmox-user", required=True)
    parser.add_argument("--proxmox-password", required=True)
    parser.add_argument("--vmid", type=int, required=True)
    parser.add_argument("--snapshot", default="baseline")
    parser.add_argument("--vm-ip", required=True)
    parser.add_argument("--vm-user", required=True)
    parser.add_argument("--vm-password", required=True)
    parser.add_argument("--build-path", default=r"c:\repos\privacyfirst\x64\Release")
    parser.add_argument("--remote-dir")
    parser.add_argument("--files", nargs="*", default=ARTIFACTS_DEFAULT)
    parser.add_argument("--executable", default="PrivacyFirst.exe")
    parser.add_argument("--program-args", nargs=argparse.REMAINDER, help="Arguments passed to the executable")
    parser.add_argument("--command-timeout", type=int, default=300, help="Seconds to wait for the remote process")
    parser.add_argument("--detach", action="store_true", help="Launch the executable and return without waiting for exit")
    parser.add_argument("--post-launch-wait", type=int, default=10, help="Seconds to wait after launch when detaching")
    parser.add_argument(
        "--keep-alive-seconds",
        type=int,
        default=0,
        help="Sleep on the controller side to keep the VM running before exiting",
    )
    parser.add_argument(
        "--auto-shutdown-seconds",
        type=int,
        default=120,
        help="Automatically shut down the VM after this many seconds (set to 0 to skip)",
    )
    parser.add_argument("--shutdown-vm", action="store_true", help="Force VM shutdown when automation completes")
    return parser.parse_args()


def wait_for_task(proxmox, node, upid, timeout=600):
    deadline = time.time() + timeout
    last_status = None
    while time.time() < deadline:
        status = proxmox.nodes(node).tasks(upid).status.get()
        state = status.get("status")
        if state != last_status:
            print(f"  Proxmox task state: {state}")
            last_status = state
        if state == "stopped":
            exitstatus = status.get("exitstatus", "OK")
            if exitstatus != "OK":
                raise RuntimeError(f"Proxmox task failed: {exitstatus}")
            return
        time.sleep(2)
    raise TimeoutError("Proxmox task timed out")


def ensure_vm_running(proxmox, node, vmid, timeout=180):
    status = proxmox.nodes(node).qemu(vmid).status.current.get()["status"]
    if status != "running":
        print(f"  VM currently {status}, sending start command ...")
        proxmox.nodes(node).qemu(vmid).status.start.post()
    deadline = time.time() + timeout
    last_status = status
    while time.time() < deadline:
        status = proxmox.nodes(node).qemu(vmid).status.current.get()["status"]
        if status != last_status:
            print(f"  VM status: {status}")
            last_status = status
        if status == "running":
            return
        time.sleep(5)
    raise TimeoutError("VM failed to reach running state")


def wait_for_ssh(host, username, password, timeout=300):
    deadline = time.time() + timeout
    last_error = None
    attempt = 0
    while time.time() < deadline:
        try:
            attempt += 1
            print(f"  Attempting SSH connection (try {attempt}) ...")
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(host, username=username, password=password, timeout=15)
            return client
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            time.sleep(5)
    raise RuntimeError(f"SSH not ready: {last_error}")


def to_sftp_path(path):
    normalized = path.replace("\\", "/")
    if len(normalized) >= 2 and normalized[1] == ":":
        normalized = f"/{normalized}"
    elif not normalized.startswith("/"):
        normalized = f"/{normalized}"
    return normalized


def ensure_remote_dir(sftp, remote_dir):
    sftp_path = to_sftp_path(remote_dir)
    segments = [seg for seg in sftp_path.strip("/").split("/") if seg]
    if not segments:
        return

    prefix = ""
    start_index = 0
    if segments[0].endswith(":"):
        prefix = f"/{segments[0]}"
        start_index = 1
        try:
            sftp.stat(prefix)
        except IOError:
            pass

    for segment in segments[start_index:]:
        prefix = f"{prefix}/{segment}" if prefix else f"/{segment}"
        try:
            sftp.stat(prefix)
        except IOError:
            sftp.mkdir(prefix)


def deploy_artifacts(ssh_client, build_path, files, remote_dir):
    with ssh_client.open_sftp() as sftp:
        ensure_remote_dir(sftp, remote_dir)
        for name in files:
            local_path = os.path.join(build_path, name)
            if not os.path.isfile(local_path):
                raise FileNotFoundError(f"Artifact missing: {local_path}")
            remote_win_path = os.path.join(remote_dir, name)
            remote_path = to_sftp_path(remote_win_path)
            print(f"Uploading {name} ...")
            sftp.put(local_path, remote_path)


def encode_args_for_ps(args):
    json_blob = json.dumps(args or [])
    return base64.b64encode(json_blob.encode("utf-8")).decode("ascii")


def parse_privacyfirst_output(stdout: str, stderr: str):
    summary = {}
    combined = "\n".join(filter(None, [stdout, stderr]))
    if not combined:
        return summary

    match = re.search(r"Execution complete:\s*(\d+)\s+succeeded,\s*(\d+)\s+failed", combined)
    if match:
        succeeded = int(match.group(1))
        failed = int(match.group(2))
        summary["execution_summary"] = {
            "succeeded": succeeded,
            "failed": failed,
        }
        summary["overall_status"] = "pass" if failed == 0 else "fail"

    warnings = re.findall(r"\[WARN\]\s*(.+)", combined)
    errors = re.findall(r"\[ERROR\]\s*(.+)", combined)
    if warnings:
        summary["warnings"] = warnings
    if errors:
        summary["errors"] = errors
        summary.setdefault("overall_status", "fail")

    if "You must install .NET to run this application." in combined:
        summary["missing_runtime"] = True
        summary.setdefault("overall_status", "fail")
    if "Failed to resolve hostfxr.dll" in combined:
        summary["runtime_error"] = "hostfxr_missing"
        summary.setdefault("overall_status", "fail")
    return summary


def run_remote_executable(
    ssh_client,
    remote_dir,
    executable,
    program_args,
    timeout=300,
    detach=False,
    post_launch_wait=10,
):
    args_b64 = encode_args_for_ps(program_args)
    timeout_ms = -1 if timeout <= 0 else int(timeout) * 1000
    detach_flag = "$true" if detach else "$false"
    post_launch = max(0, int(post_launch_wait))
    ps_script = f"""
$ErrorActionPreference = 'Stop'
$dest = '{remote_dir}'
$exePath = Join-Path $dest '{executable}'
if (-not (Test-Path $exePath)) {{ throw "Executable not found: $exePath" }}
$argsJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('{args_b64}'))
$argList = @()
if ($argsJson) {{
    $parsed = $argsJson | ConvertFrom-Json
    foreach ($item in $parsed) {{ $argList += [string]$item }}
}}
$argumentText = ''
if ($argList.Count -gt 0) {{
    $escaped = foreach ($arg in $argList) {{ '"' + ($arg -replace '"', '""') + '"' }}
    $argumentText = [string]::Join(' ', $escaped)
}}
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exePath
if ($argumentText) {{ $psi.Arguments = $argumentText }}
$psi.WorkingDirectory = $dest
$psi.RedirectStandardOutput = { '$false' if detach else '$true' }
$psi.RedirectStandardError = { '$false' if detach else '$true' }
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$process = [System.Diagnostics.Process]::Start($psi)
$timeoutMs = {timeout_ms}
$result = $null
$timedOut = $false
if ({detach_flag}) {{
    $waitSeconds = {post_launch}
    if ($waitSeconds -gt 0) {{
        Start-Sleep -Seconds $waitSeconds
    }}
    $stillRunning = $false
    try {{
        $stillRunning = -not $process.HasExited
    }} catch {{
        $stillRunning = $false
    }}
    $message = if ($stillRunning) {{
        "Process launched (PID {{0}}) and still running after {{1}} seconds." -f $process.Id, $waitSeconds
    }} else {{
        "Process exited quickly with code {{0}}." -f $process.ExitCode
    }}
    $result = [PSCustomObject]@{{
        ExitCode = 0
        StdOut = $message
        StdErr = ''
        ProcessId = $process.Id
        StillRunning = $stillRunning
        TimedOut = $false
    }}
}} else {{
    if ($timeoutMs -gt 0) {{
        $completed = $process.WaitForExit($timeoutMs)
        if (-not $completed) {{
            try {{ $process.Kill() }} catch {{ }}
            $process.WaitForExit()
            $timedOut = $true
        }}
    }} else {{
        $process.WaitForExit()
    }}
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $result = [PSCustomObject]@{{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
        ProcessId = $process.Id
        StillRunning = $false
        TimedOut = $timedOut
    }}
}}
try {{
    $process.Dispose()
}} catch {{}} 
$result | ConvertTo-Json -Depth 5
"""
    encoded = base64.b64encode(ps_script.encode("utf-16le")).decode("ascii")
    command = f"powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand {encoded}"

    stdin, stdout, stderr = ssh_client.exec_command(command)
    out = stdout.read().decode(errors="ignore").strip()
    err = stderr.read().decode(errors="ignore").strip()
    exit_status = stdout.channel.recv_exit_status()
    if err:
        print("[powershell stderr]\n" + err)
    if exit_status != 0 and not out:
        raise RuntimeError(f"Remote PowerShell exited with {exit_status}: {err}")
    try:
        result = json.loads(out)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Failed to parse remote result: {out}") from exc
    result["ExitStatus"] = exit_status
    return result


def main():
    args = parse_args()

    if not os.path.isdir(args.build_path):
        raise FileNotFoundError(f"Build path not found: {args.build_path}")

    remote_dir = args.remote_dir
    if not remote_dir:
        remote_dir = os.path.join(r"C:\Users", args.vm_user, "Documents", "PrivacyFirstPipeline")
        print(f"Remote directory not provided, defaulting to {remote_dir}")

    artifacts = [name for name in args.files if os.path.isfile(os.path.join(args.build_path, name))]
    if not artifacts:
        raise FileNotFoundError("No artifacts found to deploy.")

    proxmox = proxmoxer.ProxmoxAPI(
        args.proxmox_host,
        user=args.proxmox_user,
        password=args.proxmox_password,
        verify_ssl=False,
    )

    node = proxmox.nodes.get()[0]["node"]
    print(f"Using Proxmox node {node}")

    print("Rolling back snapshot ...")
    task = proxmox.nodes(node).qemu(args.vmid).snapshot(args.snapshot).rollback.post()
    upid = task["data"] if isinstance(task, dict) else task
    wait_for_task(proxmox, node, upid)
    print("Snapshot rollback complete")

    print("Ensuring VM is running ...")
    ensure_vm_running(proxmox, node, args.vmid)

    print("Waiting for SSH ...")
    ssh_client = wait_for_ssh(args.vm_ip, args.vm_user, args.vm_password)
    print("SSH session established")

    try:
        print("Deploying artifacts ...")
        deploy_artifacts(ssh_client, args.build_path, artifacts, remote_dir)
        print("Launching remote executable ...")
        result = run_remote_executable(
            ssh_client,
            remote_dir,
            args.executable,
            args.program_args or [],
            timeout=args.command_timeout,
            detach=args.detach,
            post_launch_wait=args.post_launch_wait,
        )
    finally:
        ssh_client.close()

    print("Exit code:", result.get("ExitCode"))
    print("STDOUT:\n" + (result.get("StdOut") or ""))
    print("STDERR:\n" + (result.get("StdErr") or ""))
    if "ProcessId" in result:
        print("ProcessId:", result.get("ProcessId"))
        if "StillRunning" in result:
            print("StillRunning:", result.get("StillRunning"))
        if "TimedOut" in result:
            print("TimedOut:", result.get("TimedOut"))
    if "InstallerExitCode" in result and result.get("InstallerExitCode") is not None:
        print("InstallerExitCode:", result.get("InstallerExitCode"))
    if "ApplicationExitCode" in result and result.get("ApplicationExitCode") is not None:
        print("ApplicationExitCode:", result.get("ApplicationExitCode"))
    if "ApplicationPath" in result and result.get("ApplicationPath"):
        print("ApplicationPath:", result.get("ApplicationPath"))

    summary = parse_privacyfirst_output(result.get("StdOut") or "", result.get("StdErr") or "")
    if "TimedOut" in result:
        summary["timed_out"] = bool(result.get("TimedOut"))
    if summary:
        print("Parsed Summary:")
        print(json.dumps(summary, indent=2))
    elif "Logs" in result:
        print("Logs:")
        for line in result.get("Logs") or []:
            print("  " + line)

    if args.keep_alive_seconds > 0:
        remaining = args.keep_alive_seconds
        print(f"Keeping session alive for {remaining} seconds ...")
        while remaining > 0:
            chunk = 30 if remaining > 30 else remaining
            time.sleep(chunk)
            remaining -= chunk
            if remaining > 0:
                print(f"  {remaining} seconds remaining ...")
        print("Keep-alive period complete.")

    shutdown_delay = args.auto_shutdown_seconds
    if shutdown_delay > 0:
        print(f"Auto-shutdown in {shutdown_delay} seconds ...")
        remaining = shutdown_delay
        while remaining > 0:
            chunk = 30 if remaining > 30 else remaining
            time.sleep(chunk)
            remaining -= chunk
            if remaining > 0:
                print(f"  {remaining} seconds remaining before shutdown ...")
        print("Initiating VM shutdown ...")
        proxmox.nodes(node).qemu(args.vmid).status.shutdown.post()
    elif args.shutdown_vm:
        print("Shutting down VM ...")
        proxmox.nodes(node).qemu(args.vmid).status.shutdown.post()


if __name__ == "__main__":
    main()
