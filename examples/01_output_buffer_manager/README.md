# LibSTF Example 1: Output Buffer Manager
This example shows how to use the OutputBufferManager of the libSTF software library that manages 
output memory buffers together with an OutputWriter on the hardware side.

## Hardware synthesis
You need to copy the content of `hardware/unit-tests/vfpga_tops/output_writer_test.sv` to 
`hardware/src/vfpga_top.svh`. Then, you can build the hardware in the root directory of this repo as 
follows (the last step takes several hours so we run it in the background and pipe the output to 
`bitgen.log`):

``` bash
mkdir build-hw-01 && cd build-hw-01
cmake ../hardware
make project
nohup make bitgen &> bitgen.log &
```

## Software build
The software side can be built with:

``` bash
mkdir build
cmake -DCMAKE_PREFIX_PATH=$HOME/opt -S . -B build
cmake --build build -j
```

## Running the example
After flashing the design to the hardware, you can run the example as follows with default values:

``` bash
./build/output_buffer_manager
```

For simulations (add `-DEN_SIMULATION=ON` to the first cmake call of the software build), it is 
recommended to disable huge pages and set the buffer size to the minimum (65536 Bytes):

``` bash
COYOTE_SIM_DIR="/<path-to-this-repo>/hardware/build-sim" ./build_sw/output_buffer_manager -p -b 65536 -s 1024
```
