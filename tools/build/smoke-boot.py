#!/usr/bin/env python3
"""Capture actual BIOS/UEFI boot screens using QEMU and an isolated disk image."""
import argparse
import json
from pathlib import Path
import shutil
import socket
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('image', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--mode', choices=('bios', 'uefi'), required=True)
parser.add_argument('--boot-iso', action='store_true')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
qmp_path = args.output / 'qmp.sock'
qmp_path.unlink(missing_ok=True)
command = ['qemu-system-x86_64', '-accel', 'tcg', '-machine', 'q35',
           '-m', '1024', '-smp', '2', '-display', 'none', '-no-reboot',
           '-qmp', 'unix:{},server=on,wait=off'.format(qmp_path),
           '-serial', 'file:' + str(args.output / 'serial.log'),
           '-device', 'qemu-xhci',
           '-drive', 'if=none,id=stick,format=raw,file=' + str(args.image),
           '-device', 'usb-storage,drive=stick,bootindex=1']
if args.mode == 'uefi':
    variables = args.output / 'OVMF_VARS.fd'
    shutil.copyfile('/usr/share/OVMF/OVMF_VARS_4M.fd', variables)
    command += ['-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd',
                '-drive', 'if=pflash,format=raw,unit=1,file=' + str(variables)]

with (args.output / 'qemu.log').open('wb') as log:
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    try:
        for _ in range(100):
            if qmp_path.exists():
                break
            if process.poll() is not None:
                raise RuntimeError('QEMU exited: ' + str(args.output / 'qemu.log'))
            time.sleep(0.1)
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(15)
        connection.connect(str(qmp_path))
        stream = connection.makefile('rwb', buffering=0)
        json.loads(stream.readline())
        def qmp(name, **arguments):
            stream.write((json.dumps({'execute': name, 'arguments': arguments}) + '\n').encode())
            while True:
                response = json.loads(stream.readline())
                if 'error' in response:
                    raise RuntimeError(response['error'])
                if 'return' in response:
                    return response['return']
        qmp('qmp_capabilities')
        def capture(name, delay=2):
            time.sleep(delay)
            qmp('screendump', filename=str(args.output / (name + '.png')), format='png')
            print(args.mode + ': ' + name, flush=True)
        def key(name):
            qmp('human-monitor-command', **{'command-line': 'sendkey ' + name})
        capture('01-firmware', 1)
        capture('02-loading', 3)
        capture('03-menu', 16)
        if args.boot_iso:
            key('ret')
            capture('04-boot-options', 3)
            key('ret')
            capture('05-os-loading', 12)
            capture('06-os', 35)
        else:
            key('f1')
            capture('04-help')
            key('esc')
            key('f5')
            capture('05-tools')
            key('esc')
            key('f6')
            capture('06-custom-menu')
            key('ret')
            key('ctrl-d')
            capture('07-text-menu')
        qmp('quit')
        process.wait(timeout=10)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        qmp_path.unlink(missing_ok=True)
