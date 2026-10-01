"""Check the host-side loader frame and serial command sequence without hardware."""

import contextlib
import io
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch

import serial

from pack_flash import make_image


class FakeSerial:
    def __init__(self):
        self.name = "TEST"
        self.is_open = True
        self.sent = bytearray()
        self.responses = [bytes.fromhex("c0de4a11"), b"\x55", b"\x55", b"\x55"]

    def reset_input_buffer(self):
        pass

    def write(self, data):
        self.sent.extend(data)
        return len(data)

    def read(self, size):
        response = self.responses.pop(0)
        assert len(response) == size
        return response

    def close(self):
        self.is_open = False


class DownloadTest(unittest.TestCase):
    def test_framing_and_command_order(self):
        imem = make_image(bytes.fromhex("13000000"), 0xC0, 0)
        dmem = make_image(bytes.fromhex("78563412"), 0xD0, 4)
        self.assertEqual(imem, bytes.fromhex("c0c0c0c0000000040000000000000013e0e0e0e0"))
        self.assertEqual(dmem[12:16], bytes.fromhex("12345678"))

        fake = FakeSerial()
        script = Path(__file__).resolve().parents[1] / "peqflash.py"
        with tempfile.TemporaryDirectory() as directory:
            imem_path = Path(directory) / "imem.bin"
            dmem_path = Path(directory) / "dmem.bin"
            imem_path.write_bytes(imem)
            dmem_path.write_bytes(dmem)
            argv = [str(script), "-serport", "TEST", "-baud", "115200",
                    "-imembin", str(imem_path), "-dmembin", str(dmem_path)]
            with patch.object(sys, "argv", argv), patch.object(serial, "Serial", return_value=fake), \
                    patch("time.sleep"), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    runpy.run_path(str(script), run_name="__main__")

        self.assertEqual(result.exception.code, 0)
        self.assertEqual(fake.sent, b"\xD3" + imem + dmem + b"\xB0")
        self.assertEqual(fake.responses, [])
        self.assertFalse(fake.is_open)


if __name__ == "__main__":
    unittest.main()
