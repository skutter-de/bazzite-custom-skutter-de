#!/usr/bin/env python3
"""ModemManager fcc-unlock.d hook for Fibocom L860-GL / XMM7560 (Intel USB modem 8087:095a).

Called by ModemManager as: <script> <dbus-path> <port1> [<port2> ...]
Must exit 0 on success, non-zero on failure/no-op.
"""
import ctypes
import os
import re
import select
import sys
import termios
import time

LIB_PATH = "/usr/libexec/xmm-l860/libmodemauth.so"


def find_at_port(ports):
    for port in ports:
        type_path = f"/sys/class/wwan/{port}/type"
        try:
            with open(type_path) as f:
                if "AT" in f.read():
                    return port
        except OSError:
            pass
        if "at" in port.lower():
            return port
    return ports[0] if ports else None


# ModemManager kills fcc-unlock.d hooks that run longer than 5s
# (https://modemmanager.org/docs/modemmanager/fcc-unlock/) - budget well
# under that. The original version of this script blindly slept 2s before
# even checking for a response on every single AT command, which routinely
# pushed the full challenge/response exchange past 10-20s and got it
# silently killed (ModemManager only retries the fcc-unlock procedure once
# per boot on failure, so this reliably broke WWAN until the next reboot).
# The modem talks over a USB-CDC ACM port, not a slow UART - real
# round-trip latency is a few tens of ms, so a short poll loop is enough.
DEADLINE = 4.0


def send(fd, cmd, timeout=0.8):
    os.write(fd, cmd.encode() + b"\r\n")
    deadline = time.time() + timeout
    data = b""
    while time.time() < deadline:
        remaining = deadline - time.time()
        r, _, _ = select.select([fd], [], [], max(0, remaining))
        if not r:
            break
        chunk = os.read(fd, 4096)
        if not chunk:
            break
        data += chunk
        if b"OK" in data or b"ERROR" in data:
            break
    return data


def main():
    start = time.time()

    if len(sys.argv) < 3:
        sys.exit(1)

    ports = sys.argv[2:]
    at_port = find_at_port(ports)
    if not at_port:
        sys.exit(2)

    device = f"/dev/{at_port}"
    fd = os.open(device, os.O_RDWR | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    attrs[3] = attrs[3] & ~termios.ECHO & ~termios.ICANON
    termios.tcsetattr(fd, termios.TCSANOW, attrs)

    data = send(fd, "AT+CFUN?")
    if b"+CFUN: 1" in data:
        os.close(fd)
        sys.exit(0)

    lib = ctypes.CDLL(LIB_PATH)
    lib.ExecuteCustCmd.restype = None
    lib.ExecuteCustCmd.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_char_p]
    lib.compute_sha256.restype = ctypes.c_int
    lib.compute_sha256.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p]

    for attempt in range(9):
        if time.time() - start > DEADLINE:
            break

        data = send(fd, "AT+GTFCCLOCKGEN")
        m = re.search(rb"0x[0-9a-fA-F]+", data)
        if not m:
            continue
        challenge = int(m.group(0), 16)

        devcode_buf = ctypes.create_string_buffer(64)
        lib.ExecuteCustCmd(0, None, devcode_buf)
        resp_buf = ctypes.create_string_buffer(256)
        lib.compute_sha256(devcode_buf, challenge, resp_buf)
        response = int.from_bytes(resp_buf.raw[:4], "little")

        data = send(fd, f"AT+GTFCCLOCKVER={response}")
        if re.search(rb"\b1\b", data):
            send(fd, "AT+GTFCCLOCKMODEUNLOCK")
            data = send(fd, "AT+CFUN=1", timeout=1.5)
            os.close(fd)
            if b"OK" in data:
                sys.exit(0)
            sys.exit(3)

    os.close(fd)
    sys.exit(4)


if __name__ == "__main__":
    main()
