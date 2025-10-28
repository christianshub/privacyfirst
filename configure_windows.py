#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, sys, subprocess, shutil, time, argparse, getpass, ctypes, winreg, signal

# ---------------- utils ----------------
def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except Exception:
        return False

def run(cmd, check=True, timeout=None, shell=None):
    """Run cmd (list or str), return CompletedProcess; raise on error if check."""
    if shell is None:
        shell = isinstance(cmd, str)
    print(f"-> {cmd}")
    p = subprocess.Popen(cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        out, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            p.terminate()
            time.sleep(1)
            p.kill()
        except Exception:
            pass
        raise RuntimeError(f"Timed out: {cmd}")
    if check and p.returncode != 0:
        print(out); print(err)
        raise RuntimeError(f"Command failed ({p.returncode}): {cmd}")
    return subprocess.CompletedProcess(cmd, p.returncode, out, err)

def ensure_dir(path):
    os.makedirs(path, exist_ok=True)

def reg_delete_tree(hive, path):
    try:
        key = winreg.OpenKey(hive, path, 0, winreg.KEY_ALL_ACCESS)
    except FileNotFoundError:
        return
    # delete children
    while True:
        try:
            sub = winreg.EnumKey(key, 0)
            reg_delete_tree(hive, path + "\\" + sub)
        except OSError:
            break
    winreg.CloseKey(key)
    try:
        winreg.DeleteKey(hive, path)
    except FileNotFoundError:
        pass

def reg_set(hive, path, name, value, kind=winreg.REG_SZ):
    key = winreg.CreateKeyEx(hive, path, 0, winreg.KEY_SET_VALUE)
    winreg.SetValueEx(key, name, 0, kind, value)
    winreg.CloseKey(key)

# ---------------- cleanup (idempotent) ----------------
def kill_processes():
    print("\n=== Killing OpenSSH-related processes ===")
    for exe in ("sshd.exe","ssh-agent.exe","ssh.exe"):
        run(f'taskkill /f /im {exe}', check=False)

def remove_services():
    print("\n=== Removing services (sshd, ssh-agent) ===")
    for svc in ("sshd","ssh-agent"):
        run(f"sc stop {svc}", check=False)
        time.sleep(1)
        run(f"sc delete {svc}", check=False)

def remove_firewall_rules():
    print("\n=== Removing firewall rules ===")
    run(r'netsh advfirewall firewall delete rule name="OpenSSH Server (sshd)"', check=False)
    run(r'netsh advfirewall firewall delete rule name="Allow ICMPv4 Echo In"', check=False)

def uninstall_choco_package():
    print("\n=== Uninstalling Chocolatey openssh package (if present) ===")
    if shutil.which("choco"):
        run("choco uninstall openssh -y", check=False)
    else:
        print("Chocolatey not found (skipping uninstall).")

def remove_folders():
    print("\n=== Deleting OpenSSH folders ===")
    for path in [
        r"C:\ProgramData\ssh",
        r"C:\Program Files\OpenSSH",
        r"C:\Program Files\OpenSSH-Win64",
    ]:
        if os.path.isdir(path):
            print(f"Removing {path}")
            shutil.rmtree(path, ignore_errors=True)

def remove_registry():
    print("\n=== Cleaning OpenSSH registry keys ===")
    reg_delete_tree(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\OpenSSH")  # DefaultShell, etc.

def remove_builtin_capability(try_remove=True):
    print("\n=== Removing built-in Windows OpenSSH capability (best-effort) ===")
    if not try_remove:
        print("Skipped by request.")
        return
    # DISM is flaky on some builds; give it a short timeout and move on if stuck.
    try:
        run(r'dism /online /Remove-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0', check=False, timeout=45)
        run(r'dism /online /Remove-Capability /CapabilityName:OpenSSH.Client~~~~0.0.1.0', check=False, timeout=45)
    except RuntimeError as e:
        print(f"DISM timed out/failed (continuing): {e}")

# ---------------- install & configure ----------------
def ensure_choco():
    print("\n=== Ensuring Chocolatey ===")
    if shutil.which("choco"):
        print("Chocolatey OK.")
        return
    ps = r"""Set-ExecutionPolicy Bypass -Scope Process -Force;
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"""
    run(["powershell","-NoProfile","-ExecutionPolicy","Bypass","-Command",ps])
    if not shutil.which("choco"):
        raise RuntimeError("Chocolatey installation failed")

def install_openssh():
    print("\n=== Installing Win32-OpenSSH via Chocolatey ===")
    params = "/SSHServerFeature /SSHAgentFeature /Path"
    # --force in case remnants confuse choco
    run(f'choco install openssh -y --force --params "\'{params}\'"')
    # Ensure helper scripts ran
    install_ps = r"C:\Program Files\OpenSSH-Win64\install-sshd.ps1"
    if os.path.exists(install_ps):
        run(["powershell","-NoProfile","-ExecutionPolicy","Bypass","-File",install_ps], check=False)

def generate_host_keys():
    print("\n=== Generating host keys ===")
    keygen = shutil.which("ssh-keygen") or r"C:\Program Files\OpenSSH-Win64\ssh-keygen.exe"
    if os.path.exists(keygen):
        run([keygen,"-A"], check=False)

def register_and_start_services():
    print("\n=== Enabling and starting services ===")
    # Ensure auto-start
    run("sc config ssh-agent start= auto", check=False)
    run("sc config sshd start= auto", check=False)
    # Start agent first
    run("sc start ssh-agent", check=False)
    time.sleep(1)
    run("sc start sshd", check=False)

def set_default_shell():
    print("\n=== Setting default SSH shell ===")
    pwsh7 = r"C:\Program Files\PowerShell\7\pwsh.exe"
    ps5   = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    shell = pwsh7 if os.path.exists(pwsh7) else ps5
    reg_set(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\OpenSSH", "DefaultShell", shell, winreg.REG_SZ)
    print(f"DefaultShell: {shell}")

def write_sshd_config():
    print("\n=== Writing sshd_config (password auth enabled) ===")
    cfg_dir = r"C:\ProgramData\ssh"
    cfg     = os.path.join(cfg_dir, "sshd_config")
    ensure_dir(cfg_dir)
    content = """Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::
PubkeyAuthentication yes
PasswordAuthentication yes
StrictModes yes
Subsystem sftp sftp-server.exe
UseDNS no
"""
    with open(cfg, "w", encoding="ascii", newline="\r\n") as f:
        f.write(content)
    # restart
    run("sc stop sshd", check=False); time.sleep(1); run("sc start sshd", check=False)

def open_firewall(also_public=False, allow_icmp=False):
    print("\n=== Opening Windows Firewall for SSH ===")
    profiles = "Any" if also_public else "Domain,Private"
    run(r'netsh advfirewall firewall delete rule name="OpenSSH Server (sshd)"', check=False)
    run(fr'netsh advfirewall firewall add rule name="OpenSSH Server (sshd)" dir=in action=allow protocol=TCP localport=22 profile={profiles}')
    if allow_icmp:
        run(r'netsh advfirewall firewall delete rule name="Allow ICMPv4 Echo In"', check=False)
        run(fr'netsh advfirewall firewall add rule name="Allow ICMPv4 Echo In" dir=in action=allow enable=yes protocol=ICMPv4:8,any profile={profiles}', check=False)
    print(f"Firewall: SSH open on profiles: {profiles}")

def set_auto_logon(user, domain, password_plain):
    print("\n=== Configuring Windows auto-logon ===")
    key = r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    reg_set(winreg.HKEY_LOCAL_MACHINE, key, "AutoAdminLogon", "1", winreg.REG_SZ)
    reg_set(winreg.HKEY_LOCAL_MACHINE, key, "DefaultUserName", user, winreg.REG_SZ)
    reg_set(winreg.HKEY_LOCAL_MACHINE, key, "DefaultPassword", password_plain, winreg.REG_SZ)
    reg_set(winreg.HKEY_LOCAL_MACHINE, key, "DefaultDomainName", domain, winreg.REG_SZ)
    # one-time autologon (raise/remove/bump if needed)
    reg_set(winreg.HKEY_LOCAL_MACHINE, key, "AutoLogonCount", 1, winreg.REG_DWORD)
    print(f"Auto-logon set for {domain}\\{user} (WARNING: plaintext password in Winlogon key — OK for test VMs).")

def verify_sshd():
    print("\n=== Verifying sshd ===")
    q = run("sc query sshd", check=False)
    print(q.stdout)
    if "RUNNING" not in q.stdout.upper():
        print("sshd not running — showing listeners on :22")
        run(r'netstat -ano | findstr /R /C:":22 .*LISTENING"', check=False)
        sys.exit(2)

# ---------------- main ----------------
def main():
    if os.name != "nt":
        print("Windows only."); sys.exit(1)
    if not is_admin():
        print("Please run in an elevated (Administrator) shell."); sys.exit(1)

    ap = argparse.ArgumentParser(description="Idempotent OpenSSH setup on Windows (wipe+install+configure)")
    ap.add_argument("--user", required=True, help="User for Windows auto-logon and SSH login")
    ap.add_argument("--domain", default=os.environ.get("COMPUTERNAME",""), help="Domain/computer for autologon (default: this computer)")
    ap.add_argument("--password", help="Autologon password (if omitted you'll be prompted)")
    ap.add_argument("--also-public", action="store_true", help="Also open SSH on Public firewall profile")
    ap.add_argument("--allow-icmp", action="store_true", help="Allow inbound ping")
    ap.add_argument("--skip-dism", action="store_true", help="Skip DISM removal of built-in capability (avoids 24H2 hangs)")
    args = ap.parse_args()

    pw = args.password or getpass.getpass(f"Enter password for {args.domain}\\{args.user}: ")

    # Full wipe — always safe to re-run
    kill_processes()
    remove_services()
    remove_firewall_rules()
    uninstall_choco_package()
    remove_folders()
    remove_registry()
    remove_builtin_capability(try_remove=(not args.skip_dism))

    # Fresh install + config
    ensure_choco()
    install_openssh()
    generate_host_keys()
    register_and_start_services()
    set_default_shell()
    write_sshd_config()
    open_firewall(also_public=args.also_public, allow_icmp=args.allow_icmp)
    set_auto_logon(args.user, args.domain, pw)
    verify_sshd()

    print("\n=== Done ===")
    print("Clean OpenSSH installed, password logins ON, firewall open (LAN by default), auto-logon set.")
    print("You can now SSH:  ssh {}@<vm-ip>".format(args.user))
    print("Reboot once to validate autologon.")

if __name__ == "__main__":
    main()
