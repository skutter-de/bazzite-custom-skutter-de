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


def send(fd, cmd, wait=2):
    os.write(fd, cmd.encode() + b"\r\n")
    time.sleep(wait)
    r, _, _ = select.select([fd], [], [], 2)
    data = b""
    if r:
        data = os.read(fd, 4096)
    return data


def main():
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
        data = send(fd, "AT+GTFCCLOCKGEN")
        m = re.search(rb"0x[0-9a-fA-F]+", data)
        if not m:
            time.sleep(0.5)
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
            data = send(fd, "AT+CFUN=1", wait=3)
            os.close(fd)
            if b"OK" in data:
                sys.exit(0)
            sys.exit(3)
        time.sleep(0.5)

    os.close(fd)
    sys.exit(4)


if __name__ == "__main__":
    main()
