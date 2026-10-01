"""Wrap little-endian raw IMEM/DMEM binaries for the UART loader."""

import argparse
from pathlib import Path


REGION_BYTES = 32768 * 4  # InstMemNum and DataMemNum in define.sv
POSTAMBLE = bytes([0xE0]) * 4


def make_image(raw: bytes, preamble: int, offset: int) -> bytes:
    if offset < 0 or offset % 4:
        raise ValueError("base offset must be nonnegative and 4-byte aligned")
    if len(raw) % 4:
        raise ValueError("raw binary length must be a multiple of 4 bytes")
    if offset + len(raw) > REGION_BYTES:
        raise ValueError(f"image exceeds the {REGION_BYTES}-byte memory region")

    # UART loader shifts the first received byte to bits [31:24]. Raw RISC-V
    # binaries are little-endian, so reverse the four bytes in each word.
    payload = b"".join(raw[i:i + 4][::-1] for i in range(0, len(raw), 4))
    return (bytes([preamble]) * 4 + len(raw).to_bytes(4, "big")
            + offset.to_bytes(4, "big") + payload + POSTAMBLE)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--imem", type=Path, required=True, help="raw little-endian instruction binary")
    parser.add_argument("--dmem", type=Path, required=True, help="raw little-endian data binary")
    parser.add_argument("--out-dir", type=Path, default=Path("."))
    parser.add_argument("--imem-offset", type=lambda value: int(value, 0), default=0)
    parser.add_argument("--dmem-offset", type=lambda value: int(value, 0), default=0)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for name, source, preamble, offset in (
        ("imem.flash.bin", args.imem, 0xC0, args.imem_offset),
        ("dmem.flash.bin", args.dmem, 0xD0, args.dmem_offset),
    ):
        raw = source.read_bytes()
        image = make_image(raw, preamble, offset)
        target = args.out_dir / name
        target.write_bytes(image)
        print(f"{target}: {len(raw)} payload bytes, offset 0x{offset:08X}")


if __name__ == "__main__":
    main()
