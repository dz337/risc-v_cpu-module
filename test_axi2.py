#!/usr/bin/env python3
"""
AXI Interface Test Script for GPU and RISC-V CPU
Tests read/write operations to both peripherals
"""

import mmap
import os
import struct
import time

# Base addresses from your memory map
GPU_BASE = 0x4300_0000
CPU_BASE = 0x4400_0000

# GPU Register offsets (word-aligned)
GPU_ID          = 0x00
GPU_STATUS      = 0x04
GPU_CONTROL     = 0x08
GPU_CMD         = 0x0C
GPU_ARG0        = 0x10
GPU_ARG1        = 0x14
GPU_ARG2        = 0x18
GPU_ARG3        = 0x1C
GPU_COLOR       = 0x20
GPU_FB_READ     = 0x40
GPU_FB_DATA     = 0x44
GPU_MATH_A      = 0x80
GPU_MATH_B      = 0x84
GPU_MATH_OP     = 0x88
GPU_MATH_RESULT = 0x8C

# GPU Commands
CMD_NOP         = 0x00
CMD_CLEAR       = 0x01
CMD_FILL_RECT   = 0x02
CMD_DRAW_LINE   = 0x03
CMD_DRAW_PIXEL  = 0x04
CMD_MANDELBROT  = 0x05
CMD_MATH_OP     = 0x06

# Math operations
MATH_ADD = 0x0
MATH_SUB = 0x1
MATH_MUL = 0x2
MATH_DIV = 0x3

# CPU Register offsets (word-aligned)
CPU_CTRL   = 0x00
CPU_STATUS = 0x04
CPU_PC     = 0x08
CPU_REG    = 0x0C
CPU_INSTR_BASE = 0x40  # Instruction memory starts here
CPU_DATA_BASE  = 0x80  # Data memory starts here

# CPU Control bits
CTRL_RUN   = 0x01
CTRL_RESET = 0x02
CTRL_STEP  = 0x04

class AXIDevice:
    """Helper class for AXI register access"""
    def __init__(self, base_addr, size=0x10000):
        self.base_addr = base_addr
        self.size = size
        self.mem = None

    def open(self):
        """Open /dev/mem and map the device"""
        try:
            self.fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
            self.mem = mmap.mmap(self.fd, self.size,
                                mmap.MAP_SHARED,
                                mmap.PROT_READ | mmap.PROT_WRITE,
                                offset=self.base_addr)
            return True
        except Exception as e:
            print(f"Error opening device at 0x{self.base_addr:08X}: {e}")
            return False

    def close(self):
        """Close the memory mapping"""
        if self.mem:
            self.mem.close()
        if hasattr(self, 'fd'):
            os.close(self.fd)

    def write32(self, offset, value):
        """Write 32-bit value to register"""
        self.mem.seek(offset)
        self.mem.write(struct.pack('<I', value & 0xFFFFFFFF))
        # No flush needed - mmap with O_SYNC writes immediately

    def read32(self, offset):
        """Read 32-bit value from register"""
        self.mem.seek(offset)
        return struct.unpack('<I', self.mem.read(4))[0]

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

def test_gpu_basic_rw():
    """Test basic GPU read/write operations"""
    print("\n" + "="*60)
    print("GPU BASIC READ/WRITE TEST")
    print("="*60)

    with AXIDevice(GPU_BASE) as gpu:
        # Test 1: Read GPU ID
        print("\n1. Reading GPU ID...")
        gpu_id = gpu.read32(GPU_ID)
        print(f"   GPU ID: 0x{gpu_id:08X}")
        expected_id = 0xABCD1234
        if gpu_id == expected_id:
            print(f"   ✓ PASS - ID matches expected (0x{expected_id:08X})")
        else:
            print(f"   ✗ FAIL - Expected 0x{expected_id:08X}, got 0x{gpu_id:08X}")

        # Test 2: Read initial status
        print("\n2. Reading initial status...")
        status = gpu.read32(GPU_STATUS)
        busy = status & 0x01
        done = (status >> 1) & 0x01
        print(f"   Status: 0x{status:08X} (busy={busy}, done={done})")

        # Test 3: Write/Read control register
        print("\n3. Testing control register...")
        test_value = 0x12345678
        gpu.write32(GPU_CONTROL, test_value)
        time.sleep(0.001)
        read_value = gpu.read32(GPU_CONTROL)
        if read_value == test_value:
            print(f"   ✓ PASS - Control register R/W (0x{test_value:08X})")
        else:
            print(f"   ✗ FAIL - Wrote 0x{test_value:08X}, read 0x{read_value:08X}")

        # Test 4: Write/Read color register
        print("\n4. Testing color register...")
        test_color = 0xFF
        gpu.write32(GPU_COLOR, test_color)
        time.sleep(0.001)
        read_color = gpu.read32(GPU_COLOR) & 0xFF
        if read_color == test_color:
            print(f"   ✓ PASS - Color register R/W (0x{test_color:02X})")
        else:
            print(f"   ✗ FAIL - Wrote 0x{test_color:02X}, read 0x{read_color:02X}")

        # Test 5: Write/Read argument registers
        print("\n5. Testing argument registers...")
        test_args = [0x11111111, 0x22222222, 0x33333333, 0x44444444]
        offsets = [GPU_ARG0, GPU_ARG1, GPU_ARG2, GPU_ARG3]
        all_pass = True
        for i, (offset, value) in enumerate(zip(offsets, test_args)):
            gpu.write32(offset, value)
            time.sleep(0.001)
            read_value = gpu.read32(offset)
            if read_value == value:
                print(f"   ✓ ARG{i}: 0x{value:08X}")
            else:
                print(f"   ✗ ARG{i}: Wrote 0x{value:08X}, read 0x{read_value:08X}")
                all_pass = False
        if all_pass:
            print("   ✓ PASS - All argument registers")

def test_gpu_math_unit():
    """Test GPU math unit"""
    print("\n" + "="*60)
    print("GPU MATH UNIT TEST")
    print("="*60)

    with AXIDevice(GPU_BASE) as gpu:
        test_cases = [
            (100, 50, MATH_ADD, 150, "ADD"),
            (100, 50, MATH_SUB, 50, "SUB"),
            (12, 5, MATH_MUL, 60, "MUL"),
            (100, 4, MATH_DIV, 25, "DIV"),
        ]

        for a, b, op, expected, name in test_cases:
            print(f"\n{name}: {a} {['+', '-', '*', '/'][op]} {b}")

            # Write operands
            gpu.write32(GPU_MATH_A, a)
            gpu.write32(GPU_MATH_B, b)
            gpu.write32(GPU_MATH_OP, op)

            # Trigger operation
            gpu.write32(GPU_CMD, CMD_MATH_OP)

            # Wait for completion
            time.sleep(0.01)

            # Read result
            result = gpu.read32(GPU_MATH_RESULT)

            if result == expected:
                print(f"   ✓ PASS - Result: {result}")
            else:
                print(f"   ✗ FAIL - Expected {expected}, got {result}")

def test_gpu_pixel_draw():
    """Test GPU pixel drawing"""
    print("\n" + "="*60)
    print("GPU PIXEL DRAW TEST")
    print("="*60)

    with AXIDevice(GPU_BASE) as gpu:
        # Draw a pixel at (10, 20) with color 0xFF
        print("\n1. Drawing pixel at (10, 20) with color 0xFF...")
        x, y = 10, 20
        color = 0xFF

        gpu.write32(GPU_COLOR, color)
        gpu.write32(GPU_ARG0, (y << 16) | x)  # y in upper 16 bits, x in lower
        gpu.write32(GPU_CMD, CMD_DRAW_PIXEL)

        # Wait for completion
        time.sleep(0.01)

        # Read back the pixel
        fb_addr = y * 320 + x  # 320 is FB_WIDTH
        gpu.write32(GPU_FB_READ, fb_addr)
        time.sleep(0.001)
        pixel_value = gpu.read32(GPU_FB_DATA) & 0xFF

        if pixel_value == color:
            print(f"   ✓ PASS - Pixel written and read correctly (0x{color:02X})")
        else:
            print(f"   ✗ FAIL - Expected 0x{color:02X}, read 0x{pixel_value:02X}")

def test_cpu_basic_rw():
    """Test basic CPU read/write operations"""
    print("\n" + "="*60)
    print("CPU BASIC READ/WRITE TEST")
    print("="*60)

    with AXIDevice(CPU_BASE) as cpu:
        # Test 1: Read initial status
        print("\n1. Reading initial CPU status...")
        status = cpu.read32(CPU_STATUS)
        print(f"   Status: 0x{status:08X}")

        # Test 2: Read initial PC
        print("\n2. Reading initial PC...")
        pc = cpu.read32(CPU_PC)
        print(f"   PC: 0x{pc:08X}")

        # Test 3: Write/Read control register
        print("\n3. Testing control register...")
        cpu.write32(CPU_CTRL, CTRL_RESET)
        time.sleep(0.01)
        ctrl = cpu.read32(CPU_CTRL)
        print(f"   Control: 0x{ctrl:08X}")

        # Test 4: Write to PC
        print("\n4. Writing to PC...")
        test_pc = 0x100
        cpu.write32(CPU_PC, test_pc)
        time.sleep(0.01)
        read_pc = cpu.read32(CPU_PC)
        if read_pc == test_pc:
            print(f"   ✓ PASS - PC write successful (0x{test_pc:08X})")
        else:
            print(f"   ✗ FAIL - Wrote 0x{test_pc:08X}, read 0x{read_pc:08X}")

def test_cpu_instruction_memory():
    """Test CPU instruction memory read/write"""
    print("\n" + "="*60)
    print("CPU INSTRUCTION MEMORY TEST")
    print("="*60)

    with AXIDevice(CPU_BASE) as cpu:
        print("\n1. Writing instructions to memory...")

        # Simple test program:
        # 0x00: ADDI x1, x0, 5    (x1 = 5)
        # 0x04: ADDI x2, x0, 10   (x2 = 10)
        # 0x08: ADD  x3, x1, x2   (x3 = x1 + x2 = 15)
        instructions = [
            0x00500093,  # ADDI x1, x0, 5
            0x00A00113,  # ADDI x2, x0, 10
            0x002081B3,  # ADD x3, x1, x2
        ]

        for i, instr in enumerate(instructions):
            offset = CPU_INSTR_BASE + (i * 4)
            cpu.write32(offset, instr)
            time.sleep(0.001)  # Small delay after write
            print(f"   [0x{i*4:03X}] = 0x{instr:08X}")

        print("\n2. Reading back instructions...")
        all_pass = True
        for i, expected in enumerate(instructions):
            offset = CPU_INSTR_BASE + (i * 4)
            read_val = cpu.read32(offset)
            if read_val == expected:
                print(f"   ✓ [0x{i*4:03X}] = 0x{read_val:08X}")
            else:
                print(f"   ✗ [0x{i*4:03X}] = 0x{read_val:08X} (expected 0x{expected:08X})")
                all_pass = False

        if all_pass:
            print("\n   ✓ PASS - All instructions written and read correctly")

def test_cpu_data_memory():
    """Test CPU data memory read/write"""
    print("\n" + "="*60)
    print("CPU DATA MEMORY TEST")
    print("="*60)

    with AXIDevice(CPU_BASE) as cpu:
        print("\n1. Writing data to memory...")

        test_data = [0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00]

        for i, data in enumerate(test_data):
            offset = CPU_DATA_BASE + (i * 4)
            cpu.write32(offset, data)
            time.sleep(0.001)  # Small delay after write
            print(f"   [0x{offset:03X}] = 0x{data:08X}")

        print("\n2. Reading back data...")
        all_pass = True
        for i, expected in enumerate(test_data):
            offset = CPU_DATA_BASE + (i * 4)
            read_val = cpu.read32(offset)
            if read_val == expected:
                print(f"   ✓ [0x{offset:03X}] = 0x{read_val:08X}")
            else:
                print(f"   ✗ [0x{offset:03X}] = 0x{read_val:08X} (expected 0x{expected:08X})")
                all_pass = False

        if all_pass:
            print("\n   ✓ PASS - All data written and read correctly")

def main():
    """Run all tests"""
    print("\n" + "="*60)
    print("AXI INTERFACE TEST SUITE")
    print("Testing GPU (0x{:08X}) and CPU (0x{:08X})".format(GPU_BASE, CPU_BASE))
    print("="*60)

    try:
        # GPU Tests
        test_gpu_basic_rw()
        test_gpu_math_unit()
        test_gpu_pixel_draw()

        # CPU Tests
        test_cpu_basic_rw()
        test_cpu_instruction_memory()
        test_cpu_data_memory()

        print("\n" + "="*60)
        print("TEST SUITE COMPLETE")
        print("="*60 + "\n")

    except PermissionError:
        print("\n✗ ERROR: Permission denied accessing /dev/mem")
        print("Run this script with sudo: sudo python3 test_axi.py\n")
    except Exception as e:
        print(f"\n✗ ERROR: {e}\n")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()




























