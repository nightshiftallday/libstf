import random
import unittest
from typing import List

from coyote_test import fpga_test_case
from unit_test.fpga_stream import Stream, StreamType

# SystemVerilog defines consumed by vfpga_tops/data_width_converter_test.sv to size the input and
# output sides of the NDataWidthConverter under test.
IN_NUM_ELEMENTS = "IN_NUM_ELEMENTS"
OUT_NUM_ELEMENTS = "OUT_NUM_ELEMENTS"


class _DataWidthConverterTestBase:
    """
    Shared test bodies for the NDataWidthConverter.

    The module under test converts an ndata stream between two element counts. The test harness wires
    a 512-bit host stream through AXIToNData -> NDataWidthConverter -> NDataToAXI, so for every
    supported configuration the byte stream that goes in must come back out unchanged. Each concrete
    subclass only differs in the input/output widths it configures.
    """

    alternative_vfpga_top_file = "vfpga_tops/data_width_converter_test.sv"

    debug_mode = True
    verbose_logging = True

    # Overridden by the concrete subclasses. These are the NUM_ELEMENTS of the in/out interfaces of
    # the NDataWidthConverter. Both must be supported by the AXIToNData/NDataToAXI adapters, i.e.
    # either 64 (a full 512-bit beat of bytes) or 32 (half a beat).
    IN_ELEMENTS: int = None
    OUT_ELEMENTS: int = None

    def setUp(self):
        super().setUp()
        self.input: List[int] = None
        self.set_system_verilog_defines(
            {
                IN_NUM_ELEMENTS: str(self.IN_ELEMENTS),
                OUT_NUM_ELEMENTS: str(self.OUT_ELEMENTS),
            }
        )

    def simulate_fpga(self):
        assert self.input is not None, (
            "Cannot run width converter test without input!"
        )

        # The converter must preserve the byte stream regardless of the width change, so the expected
        # output is simply the input again.
        self.set_stream_input(0, Stream(StreamType.UNSIGNED_INT_8, self.input))
        self.set_expected_output(0, Stream(StreamType.UNSIGNED_INT_8, self.input))

        return super().simulate_fpga()

    def _run_with_size(self, size: int):
        self.input = [i % 256 for i in range(size)]

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_single_full_beat(self):
        # Exactly one full 512-bit host beat (64 bytes).
        self._run_with_size(64)

    def test_two_full_beats(self):
        # Two full beats: enough to fill an upconverter twice over.
        self._run_with_size(128)

    def test_many_full_beats(self):
        self._run_with_size(512)

    def test_partial_first_beat(self):
        # Fewer bytes than a single host beat -> a single, partially-kept beat.
        self._run_with_size(20)

    def test_partial_final_beat(self):
        # Several full beats followed by a partial one, exercising keep/last on the tail.
        self._run_with_size(100)

    def test_odd_size(self):
        # A size that is not a multiple of either width to stress the keep/last handling.
        self._run_with_size(333)

    def test_random(self):
        random.seed(0)
        self.input = [random.randint(0, 255) for _ in range(777)]

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()


class DataWidthConverterPassthroughTest(
    _DataWidthConverterTestBase, fpga_test_case.FPGATestCase
):
    """IN_WIDTH == OUT_WIDTH: the converter degenerates to a pass-through."""

    IN_ELEMENTS = 64
    OUT_ELEMENTS = 64


class DataWidthConverterTest16to64(
    _DataWidthConverterTestBase, fpga_test_case.FPGATestCase
):
    IN_ELEMENTS = 16
    OUT_ELEMENTS = 64


class DataWidthConverterTest64To16(
    _DataWidthConverterTestBase, fpga_test_case.FPGATestCase
):
    IN_ELEMENTS = 64
    OUT_ELEMENTS = 16


class DataWidthConverterTest4to16(
    _DataWidthConverterTestBase, fpga_test_case.FPGATestCase
):
    IN_ELEMENTS = 4
    OUT_ELEMENTS = 16


class DataWidthConverterTest16to4(
    _DataWidthConverterTestBase, fpga_test_case.FPGATestCase
):
    IN_ELEMENTS = 16
    OUT_ELEMENTS = 4


class DataWidthConverterTest8to32(
    _DataWidthConverterTestBase, fpga_test_case.FPGATestCase
):
    IN_ELEMENTS = 8
    OUT_ELEMENTS = 32


class DataWidthConverterTest32to8(
    _DataWidthConverterTestBase, fpga_test_case.FPGATestCase
):
    IN_ELEMENTS = 32
    OUT_ELEMENTS = 8

