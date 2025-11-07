#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <string.h>
#include <errno.h>
#include <time.h> // Required for nanosleep

// --- Device Base Addresses ---
#define GPU_BASE 0x43000000
#define CPU_BASE 0x44000000
#define MAP_SIZE 0x10000 // 64KB, same as Python's default

// --- GPU Register Offsets ---
#define GPU_ID          0x00
#define GPU_STATUS      0x04
#define GPU_CONTROL     0x08
#define GPU_CMD         0x0C
#define GPU_ARG0        0x10
#define GPU_ARG1        0x14
#define GPU_ARG2        0x18
#define GPU_ARG3        0x1C
#define GPU_COLOR       0x20
#define GPU_FB_READ     0x40
#define GPU_FB_DATA     0x44
#define GPU_MATH_A      0x80
#define GPU_MATH_B      0x84
#define GPU_MATH_OP     0x88
#define GPU_MATH_RESULT 0x8C

// --- GPU Commands (FIXED) ---
#define CMD_NOP         0x00
#define CMD_CLEAR       0x01
#define CMD_FILL_RECT   0x02
#define CMD_DRAW_LINE   0x03
#define CMD_DRAW_PIXEL  0x04
#define CMD_MANDELBROT  0x05
#define CMD_MATH_OP     0x06 // <--- Fix for #definedefine error

// --- Math Operations ---
#define MATH_ADD 0x0
#define MATH_SUB 0x1
#define MATH_MUL 0x2
#define MATH_DIV 0x3

// --- CPU Register Offsets ---
#define CPU_CTRL        0x00
#define CPU_STATUS      0x04
#define CPU_PC          0x08
#define CPU_REG         0x0C
#define CPU_INSTR_BASE  0x40
#define CPU_DATA_BASE   0x80

// --- CPU Control bits ---
#define CTRL_RUN    0x01
#define CTRL_RESET  0x02
#define CTRL_STEP   0x04

// Framebuffer size assumption for pixel test
#define FB_WIDTH 320

// --- Global mmap Pointers ---
volatile uint32_t *gpu_vptr = NULL;
volatile uint32_t *cpu_vptr = NULL;
int mem_fd = -1;

/**
 * @brief Sleeps for the specified number of microseconds using nanosleep.
 * @param usec Delay in microseconds.
 */
void delay_us(long usec) {
    struct timespec ts;
    ts.tv_sec = usec / 1000000;          // Seconds part
    ts.tv_nsec = (usec % 1000000) * 1000; // Nanoseconds part
    nanosleep(&ts, NULL);
}

// --- Helper Functions for Register Access ---

/**
 * @brief Writes a 32-bit value to a register offset.
 */
void write32(volatile uint32_t *base_vptr, uint32_t offset, uint32_t value) {
    if (base_vptr) {
        *(base_vptr + (offset / 4)) = value;
    }
}

/**
 * @brief Reads a 32-bit value from a register offset.
 */
uint32_t read32(volatile uint32_t *base_vptr, uint32_t offset) {
    if (base_vptr) {
        return *(base_vptr + (offset / 4));
    }
    return 0xFFFFFFFF; // Error value
}

/**
 * @brief Sets up memory mapping for a device.
 */
volatile uint32_t* axi_open(uint32_t phys_addr) {
    if (mem_fd == -1) {
        mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
        if (mem_fd == -1) {
            perror("Error opening /dev/mem. Did you run with sudo?");
            return NULL;
        }
    }

    volatile uint32_t *vptr = (volatile uint32_t*)mmap(
        0, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, phys_addr
    );

    if (vptr == MAP_FAILED) {
        perror("Error during mmap");
        return NULL;
    }
    return vptr;
}

/**
 * @brief Cleans up memory mapping.
 */
void axi_close(volatile uint32_t* vptr) {
    if (vptr != MAP_FAILED && vptr != NULL) {
        munmap((void*)vptr, MAP_SIZE);
    }
}

// --- Test Functions (Translated from Python) ---

void test_gpu_basic_rw() {
    printf("\n%s\n", "============================================================");
    printf("GPU BASIC READ/WRITE TEST\n");
    printf("%s\n", "============================================================");

    if (!gpu_vptr) {
        printf("GPU device not open. Skipping test.\n");
        return;
    }

    // Test 1: Read GPU ID
    printf("\n1. Reading GPU ID...\n");
    uint32_t gpu_id = read32(gpu_vptr, GPU_ID);
    printf("    GPU ID: 0x%08X\n", gpu_id);
    uint32_t expected_id = 0xABCD1234;
    if (gpu_id == expected_id) {
        printf("    ✓ PASS - ID matches expected (0x%08X)\n", expected_id);
    } else {
        printf("    ✗ FAIL - Expected 0x%08X, got 0x%08X\n", expected_id, gpu_id);
    }

    // Test 2: Read initial status
    printf("\n2. Reading initial status...\n");
    uint32_t status = read32(gpu_vptr, GPU_STATUS);
    uint32_t busy = status & 0x01;
    uint32_t done = (status >> 1) & 0x01;
    printf("    Status: 0x%08X (busy=%u, done=%u)\n", status, busy, done);

    // Test 3: Write/Read control register
    printf("\n3. Testing control register...\n");
    uint32_t test_value = 0x12345678;
    write32(gpu_vptr, GPU_CONTROL, test_value);
    delay_us(1000); // 1ms delay
    uint32_t read_value = read32(gpu_vptr, GPU_CONTROL);
    if (read_value == test_value) {
        printf("    ✓ PASS - Control register R/W (0x%08X)\n", test_value);
    } else {
        printf("    ✗ FAIL - Wrote 0x%08X, read 0x%08X\n", test_value, read_value);
    }

    // Test 4: Write/Read color register
    printf("\n4. Testing color register...\n");
    uint32_t test_color = 0xFF;
    write32(gpu_vptr, GPU_COLOR, test_color);
    delay_us(1000); // 1ms delay
    uint32_t read_color = read32(gpu_vptr, GPU_COLOR) & 0xFF;
    if (read_color == test_color) {
        printf("    ✓ PASS - Color register R/W (0x%02X)\n", test_color);
    } else {
        printf("    ✗ FAIL - Wrote 0x%02X, read 0x%02X\n", (unsigned int)test_color, (unsigned int)read_color);
    }

    // Test 5: Write/Read argument registers
    printf("\n5. Testing argument registers...\n");
    uint32_t test_args[] = {0x11111111, 0x22222222, 0x33333333, 0x44444444};
    uint32_t offsets[] = {GPU_ARG0, GPU_ARG1, GPU_ARG2, GPU_ARG3};
    int all_pass = 1;

    for (int i = 0; i < 4; i++) {
        write32(gpu_vptr, offsets[i], test_args[i]);
        delay_us(1000); // 1ms delay
        uint32_t arg_read_value = read32(gpu_vptr, offsets[i]);
        if (arg_read_value == test_args[i]) {
            printf("    ✓ ARG%d: 0x%08X\n", i, test_args[i]);
        } else {
            printf("    ✗ ARG%d: Wrote 0x%08X, read 0x%08X\n", i, test_args[i], arg_read_value);
            all_pass = 0;
        }
    }
    if (all_pass) {
        printf("    ✓ PASS - All argument registers\n");
    }
}

void test_gpu_math_unit() {
    printf("\n%s\n", "============================================================");
    printf("GPU MATH UNIT TEST\n");
    printf("%s\n", "============================================================");

    if (!gpu_vptr) {
        printf("GPU device not open. Skipping test.\n");
        return;
    }

    struct {
        int a, b;
        uint32_t op;
        int expected;
        const char *name;
        const char *op_str;
    } test_cases[] = {
        {100, 50, MATH_ADD, 150, "ADD", "+"},
        {100, 50, MATH_SUB, 50, "SUB", "-"},
        {12, 5, MATH_MUL, 60, "MUL", "*"},
        {100, 4, MATH_DIV, 25, "DIV", "/"},
    };
    int num_cases = sizeof(test_cases) / sizeof(test_cases[0]);

    for (int i = 0; i < num_cases; i++) {
        int a = test_cases[i].a;
        int b = test_cases[i].b;
        uint32_t op = test_cases[i].op;
        int expected = test_cases[i].expected;
        const char *name = test_cases[i].name;
        const char *op_str = test_cases[i].op_str;

        printf("\n%s: %d %s %d\n", name, a, op_str, b);

        // Write operands
        write32(gpu_vptr, GPU_MATH_A, a);
        write32(gpu_vptr, GPU_MATH_B, b);
        write32(gpu_vptr, GPU_MATH_OP, op);

        // Trigger operation
        write32(gpu_vptr, GPU_CMD, CMD_MATH_OP);

        // Wait for completion
        delay_us(10000); // 10ms delay

        // Read result
        uint32_t result = read32(gpu_vptr, GPU_MATH_RESULT);

        if ((int)result == expected) {
            printf("    ✓ PASS - Result: %u\n", result);
        } else {
            printf("    ✗ FAIL - Expected %d, got %u\n", expected, result);
        }
    }
}

void test_gpu_pixel_draw() {
    printf("\n%s\n", "============================================================");
    printf("GPU PIXEL DRAW TEST\n");
    printf("%s\n", "============================================================");

    if (!gpu_vptr) {
        printf("GPU device not open. Skipping test.\n");
        return;
    }

    // Draw a pixel at (10, 20) with color 0xFF
    printf("\n1. Drawing pixel at (10, 20) with color 0xFF...\n");
    uint32_t x = 10, y = 20;
    uint32_t color = 0xFF;

    write32(gpu_vptr, GPU_COLOR, color);
    // y in upper 16 bits, x in lower
    write32(gpu_vptr, GPU_ARG0, (y << 16) | x);
    write32(gpu_vptr, GPU_CMD, CMD_DRAW_PIXEL);

    // Wait for completion
    delay_us(10000); // 10ms delay

    // Read back the pixel
    uint32_t fb_addr = y * FB_WIDTH + x;
    write32(gpu_vptr, GPU_FB_READ, fb_addr);
    delay_us(1000); // 1ms delay
    uint32_t pixel_value = read32(gpu_vptr, GPU_FB_DATA) & 0xFF;

    if (pixel_value == color) {
        printf("    ✓ PASS - Pixel written and read correctly (0x%02X)\n", color);
    } else {
        printf("    ✗ FAIL - Expected 0x%02X, read 0x%02X\n", (unsigned int)color, (unsigned int)pixel_value);
    }
}

void test_cpu_basic_rw() {
    printf("\n%s\n", "============================================================");
    printf("CPU BASIC READ/WRITE TEST\n");
    printf("%s\n", "============================================================");

    if (!cpu_vptr) {
        printf("CPU device not open. Skipping test.\n");
        return;
    }

    // Test 1: Read initial CPU status
    printf("\n1. Reading initial CPU status...\n");
    uint32_t status = read32(cpu_vptr, CPU_STATUS);
    printf("    Status: 0x%08X\n", status);

    // Test 2: Read initial PC
    printf("\n2. Reading initial PC...\n");
    uint32_t pc = read32(cpu_vptr, CPU_PC);
    printf("    PC: 0x%08X\n", pc);

    // Test 3: Write/Read control register (e.g., reset)
    printf("\n3. Testing control register (reset)... \n");
    write32(cpu_vptr, CPU_CTRL, CTRL_RESET);
    delay_us(10000); // 10ms delay
    uint32_t ctrl = read32(cpu_vptr, CPU_CTRL);
    printf("    Control (after reset): 0x%08X\n", ctrl);

    // Test 4: Write to PC
    printf("\n4. Writing to PC...\n");
    uint32_t test_pc = 0x100;
    write32(cpu_vptr, CPU_PC, test_pc);
    delay_us(10000); // 10ms delay
    uint32_t read_pc = read32(cpu_vptr, CPU_PC);
    if (read_pc == test_pc) {
        printf("    ✓ PASS - PC write successful (0x%08X)\n", test_pc);
    } else {
        printf("    ✗ FAIL - Wrote 0x%08X, read 0x%08X\n", test_pc, read_pc);
    }
}

void test_cpu_instruction_memory() {
    printf("\n%s\n", "============================================================");
    printf("CPU INSTRUCTION MEMORY TEST\n");
    printf("%s\n", "============================================================");

    if (!cpu_vptr) {
        printf("CPU device not open. Skipping test.\n");
        return;
    }

    printf("\n1. Writing instructions to memory...\n");

    uint32_t instructions[] = {
        0x00500093, // ADDI x1, x0, 5
        0x00A00113, // ADDI x2, x0, 10
        0x002081B3, // ADD x3, x1, x2
    };
    int num_instr = sizeof(instructions) / sizeof(instructions[0]);

    for (int i = 0; i < num_instr; i++) {
        uint32_t offset = CPU_INSTR_BASE + (i * 4);
        write32(cpu_vptr, offset, instructions[i]);
        delay_us(1000); // Small delay after write
        printf("    [0x%03X] = 0x%08X\n", i * 4, instructions[i]);
    }

    printf("\n2. Reading back instructions...\n");
    int all_pass = 1;
    for (int i = 0; i < num_instr; i++) {
        uint32_t offset = CPU_INSTR_BASE + (i * 4);
        uint32_t read_val = read32(cpu_vptr, offset);
        if (read_val == instructions[i]) {
            printf("    ✓ [0x%03X] = 0x%08X\n", i * 4, read_val);
        } else {
            printf("    ✗ [0x%03X] = 0x%08X (expected 0x%08X)\n", i * 4, read_val, instructions[i]);
            all_pass = 0;
        }
    }
    if (all_pass) {
        printf("\n    ✓ PASS - All instructions written and read correctly\n");
    }
}

void test_cpu_data_memory() {
    printf("\n%s\n", "============================================================");
    printf("CPU DATA MEMORY TEST\n");
    printf("%s\n", "============================================================");

    if (!cpu_vptr) {
        printf("CPU device not open. Skipping test.\n");
        return;
    }

    printf("\n1. Writing data to memory...\n");

    uint32_t test_data[] = {0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00};
    int num_data = sizeof(test_data) / sizeof(test_data[0]);

    for (int i = 0; i < num_data; i++) {
        uint32_t offset = CPU_DATA_BASE + (i * 4);
        write32(cpu_vptr, offset, test_data[i]);
        delay_us(1000); // Small delay after write
        printf("    [0x%03X] = 0x%08X\n", offset, test_data[i]);
    }

    printf("\n2. Reading back data...\n");
    int all_pass = 1;
    for (int i = 0; i < num_data; i++) {
        uint32_t offset = CPU_DATA_BASE + (i * 4);
        uint32_t read_val = read32(cpu_vptr, offset);
        if (read_val == test_data[i]) {
            printf("    ✓ [0x%03X] = 0x%08X\n", offset, read_val);
        } else {
            printf("    ✗ [0x%03X] = 0x%08X (expected 0x%08X)\n", offset, read_val, test_data[i]);
            all_pass = 0;
        }
    }

    if (all_pass) {
        printf("\n    ✓ PASS - All data written and read correctly\n");
    }
}

int main() {
    printf("\n%s\n", "============================================================");
    printf("AXI INTERFACE TEST SUITE\n");
    printf("Testing GPU (0x%08X) and CPU (0x%08X)\n", GPU_BASE, CPU_BASE);
    printf("%s\n", "============================================================");

    // Open devices
    gpu_vptr = axi_open(GPU_BASE);
    cpu_vptr = axi_open(CPU_BASE);

    if (!gpu_vptr && !cpu_vptr) {
        printf("\n✗ FATAL ERROR: Could not open any AXI device. Check permissions and addresses.\n");
        if (errno == EACCES) {
             printf("Run this program with sudo: sudo ./test_axi2\n");
        }
        if (mem_fd != -1) close(mem_fd);
        return EXIT_FAILURE;
    }

    // GPU Tests
    test_gpu_basic_rw();
    test_gpu_math_unit();
    test_gpu_pixel_draw();

    // CPU Tests
    test_cpu_basic_rw();
    test_cpu_instruction_memory();
    test_cpu_data_memory();

    // Cleanup
    axi_close(gpu_vptr);
    axi_close(cpu_vptr);
    if (mem_fd != -1) close(mem_fd);

    printf("\n%s\n", "============================================================");
    printf("TEST SUITE COMPLETE\n");
    printf("%s\n\n", "============================================================");

    return EXIT_SUCCESS;
}






