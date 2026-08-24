#!/usr/bin/env python3
import binascii
import os
import struct
import sys

IH_MAGIC = 0x27051956
IH_OS_LINUX = 5
IH_ARCH_ARM = 2
IH_TYPE_SCRIPT = 6
IH_COMP_NONE = 0
IMAGE_PARAM_INVAL = 0xFFFFFFFF


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(f"usage: {sys.argv[0]} <boot.cmd> <boot.scr> [name]")

    source_script_path = sys.argv[1]
    output_image_path = sys.argv[2]
    image_name_bytes = (sys.argv[3] if len(sys.argv) > 3 else "boot script").encode()[
        :31
    ]

    raw_lines = open(source_script_path, "rb").read().splitlines()

    # Filter out empty lines and comment lines
    stripped_script_bytes = (
        b"\n".join(
            line
            for line in raw_lines
            if line.strip() and not line.lstrip().startswith(b"#")
        )
        + b"\n"
    )

    # Rockchip U-Boot requires [len][0xFFFFFFFF] prefix before script payload
    payload_bytes = (
        struct.pack(">II", len(stripped_script_bytes), IMAGE_PARAM_INVAL)
        + stripped_script_bytes
    )

    source_modification_time = int(os.stat(source_script_path).st_mtime)
    payload_crc32 = binascii.crc32(payload_bytes) & 0xFFFFFFFF

    def build_header(header_crc32: int) -> bytes:
        return struct.pack(
            ">7I4B32s",
            IH_MAGIC,
            header_crc32,
            source_modification_time,
            len(payload_bytes),
            0,
            0,
            payload_crc32,
            IH_OS_LINUX,
            IH_ARCH_ARM,
            IH_TYPE_SCRIPT,
            IH_COMP_NONE,
            image_name_bytes.ljust(32, b"\0"),
        )

    calculated_header_crc32 = binascii.crc32(build_header(0)) & 0xFFFFFFFF

    with open(output_image_path, "wb") as output_file:
        output_file.write(build_header(calculated_header_crc32) + payload_bytes)


if __name__ == "__main__":
    main()
