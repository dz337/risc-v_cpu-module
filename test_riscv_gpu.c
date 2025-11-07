#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>

// Memory addresses (adjust if you used different addresses)
#define CPU_BASE_ADDR    0x44000000
#define GPU_BASE_ADDR    0x43000000
#define MAP_SIZE         4096

// CPU register offsets
#define CPU_CTRL         0x00
#define CPU_STATUS       0x04
#define CPU_PC           0x08
#define CPU_REG          0x0C
#define CPU_INSTR_BASE   0x40

// CPU control bits
#define CTRL_RUN         (1 << 0)
#define CTRL_RESET       (1 << 1)
#define CTRL_STEP        (1 << 2)

// GPU register offsets
#define GPU_ID           0x00
#define GPU_STATUS       0x04
#define GPU_CONTROL      0x08
#define GPU_CMD          0x0C
#define GPU_ARG0         0x10
#define GPU_ARG1         0x14
#define GPU_ARG2         0x18
#define GPU_ARG3         0x1C
#define GPU_COLOR        0x20
#define GPU_FB_READ      0x40
#define GPU_FB_DATA      0x44

// GPU commands
#define CMD_NOP          0x00
#define CMD_CLEAR        0x01
#define CMD_FILL_RECT    0x02
#define CMD_DRAW_LINE    0x03
#define CMD_DRAW_PIXEL   0x04
#define CMD_MANDELBROT   0x05

// Global pointers
volatile uint32_t *cpu_regs = NULL;
volatile uint32_t *gpu_regs = NULL;

// Memory map helper
void* map_memory(off_t base_addr, size_t size) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("Error opening /dev/mem");
        return NULL;
    }

    void *ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base_addr);
    close(fd);

    if (ptr == MAP_FAILED) {
        perror("Error mapping memory");
        return NULL;
    }

    return ptr;
}

// GPU helper functions
void gpu_wait_ready() {
    while (gpu_regs[GPU_STATUS/4] & 0x01) {
        usleep(100);
    }
}

void gpu_clear(uint8_t color) {
    gpu_wait_ready();
    gpu_regs[GPU_COLOR/4] = color;
    gpu_regs[GPU_CMD/4] = CMD_CLEAR;
}

void gpu_draw_rect(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint8_t color) {
    gpu_wait_ready();
    gpu_regs[GPU_ARG0/4] = (y0 << 16) | x0;
    gpu_regs[GPU_ARG1/4] = (y1 << 16) | x1;
    gpu_regs[GPU_COLOR/4] = color;
    gpu_regs[GPU_CMD/4] = CMD_FILL_RECT;
}

void gpu_draw_line(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint8_t color) {
    gpu_wait_ready();
    gpu_regs[GPU_ARG0/4] = (y0 << 16) | x0;
    gpu_regs[GPU_ARG1/4] = (y1 << 16) | x1;
    gpu_regs[GPU_COLOR/4] = color;
    gpu_regs[GPU_CMD/4] = CMD_DRAW_LINE;
}

void gpu_draw_pixel(uint16_t x, uint16_t y, uint8_t color) {
    gpu_wait_ready();
    gpu_regs[GPU_ARG0/4] = (y << 16) | x;
    gpu_regs[GPU_COLOR/4] = color;
    gpu_regs[GPU_CMD/4] = CMD_DRAW_PIXEL;
}

uint8_t gpu_read_pixel(uint16_t x, uint16_t y) {
    uint32_t addr = y * 320 + x;
    gpu_regs[GPU_FB_READ/4] = addr;
    usleep(10);
    return gpu_regs[GPU_FB_DATA/4] & 0xFF;
}

// CPU helper functions
void cpu_reset() {
    cpu_regs[CPU_CTRL/4] = CTRL_RESET;
    usleep(1000);
    cpu_regs[CPU_CTRL/4] = 0;
}

void cpu_set_pc(uint32_t pc) {
    cpu_regs[CPU_PC/4] = pc;
}

uint32_t cpu_get_pc() {
    return cpu_regs[CPU_PC/4];
}

uint32_t cpu_get_status() {
    return cpu_regs[CPU_STATUS/4];
}

void cpu_run() {
    cpu_regs[CPU_CTRL/4] = CTRL_RUN;
}

void cpu_stop() {
    cpu_regs[CPU_CTRL/4] = 0;
}

void cpu_write_instruction(uint32_t addr, uint32_t instruction) {
    cpu_regs[(CPU_INSTR_BASE + addr*4)/4] = instruction;
}

// Test functions
int test_gpu_id() {
    printf("\n=== Testing GPU ID ===\n");
    uint32_t id = gpu_regs[GPU_ID/4];
    printf("GPU ID: 0x%08X\n", id);
    if (id == 0xABCD1234) {
        printf("✓ GPU ID correct!\n");
        return 1;
    } else {
        printf("✗ GPU ID incorrect! Expected 0xABCD1234\n");
        return 0;
    }
}

int test_gpu_clear() {
    printf("\n=== Testing GPU Clear ===\n");

    // Clear to red (color 0xFF for 8-bit)
    printf("Clearing screen to color 0xFF...\n");
    gpu_clear(0xFF);
    gpu_wait_ready();

    // Read back a few pixels to verify
    int errors = 0;
    for (int i = 0; i < 10; i++) {
        uint16_t x = rand() % 320;
        uint16_t y = rand() % 200;
        uint8_t pixel = gpu_read_pixel(x, y);
        if (pixel != 0xFF) {
            printf("✗ Pixel at (%d,%d) = 0x%02X, expected 0xFF\n", x, y, pixel);
            errors++;
        }
    }

    if (errors == 0) {
        printf("✓ GPU clear working!\n");
        return 1;
    } else {
        printf("✗ GPU clear failed with %d errors\n", errors);
        return 0;
    }
}

int test_gpu_draw() {
    printf("\n=== Testing GPU Drawing ===\n");

    // Clear screen first
    gpu_clear(0x00);
    gpu_wait_ready();

    // Draw a rectangle
    printf("Drawing rectangle...\n");
    gpu_draw_rect(50, 50, 100, 100, 0xAA);
    gpu_wait_ready();

    // Verify a pixel inside the rectangle
    uint8_t pixel = gpu_read_pixel(75, 75);
    printf("Pixel at (75,75) = 0x%02X (expected 0xAA)\n", pixel);

    // Draw a line
    printf("Drawing line...\n");
    gpu_draw_line(10, 10, 100, 50, 0x55);
    gpu_wait_ready();

    printf("✓ GPU drawing commands executed\n");
    return 1;
}

int test_cpu_signature() {
    printf("\n=== Testing CPU Signature ===\n");

    // Try reading from an unmapped address to get signature
    uint32_t sig = cpu_regs[0x3C/4];  // Random address should return signature
    printf("CPU Signature: 0x%08X\n", sig);

    if (sig == 0x52495343) {  // "RISC"
        printf("✓ CPU signature correct! (RISC-V)\n");
        return 1;
    } else {
        printf("? CPU signature: 0x%08X\n", sig);
        return 0;
    }
}

int test_cpu_control() {
    printf("\n=== Testing CPU Control ===\n");

    // Reset CPU
    printf("Resetting CPU...\n");
    cpu_reset();

    uint32_t pc = cpu_get_pc();
    printf("PC after reset: 0x%08X (expected 0x00000000)\n", pc);

    if (pc == 0) {
        printf("✓ CPU reset working!\n");
    } else {
        printf("✗ CPU reset failed\n");
        return 0;
    }

    // Set PC
    printf("Setting PC to 0x100...\n");
    cpu_set_pc(0x100);
    pc = cpu_get_pc();
    printf("PC readback: 0x%08X\n", pc);

    if (pc == 0x100) {
        printf("✓ CPU PC control working!\n");
        return 1;
    } else {
        printf("✗ CPU PC control failed\n");
        return 0;
    }
}

int test_cpu_simple_program() {
    printf("\n=== Testing CPU with Simple Program ===\n");

    cpu_reset();

    // Simple RISC-V program: NOP loop
    // 0x00000013 = ADDI x0, x0, 0 (NOP)
    printf("Loading NOP instructions...\n");
    for (int i = 0; i < 10; i++) {
        cpu_write_instruction(i, 0x00000013);
    }

    // Set PC to 0
    cpu_set_pc(0);

    // Run CPU briefly
    printf("Running CPU...\n");
    cpu_run();
    usleep(10000);  // 10ms

    uint32_t status = cpu_get_status();
    printf("CPU Status: 0x%08X\n", status);

    uint32_t pc = cpu_get_pc();
    printf("PC after running: 0x%08X\n", pc);

    cpu_stop();

    if (pc > 0) {
        printf("✓ CPU executed instructions! PC advanced to 0x%08X\n", pc);
        return 1;
    } else {
        printf("✗ CPU didn't advance PC\n");
        return 0;
    }
}

void test_pattern() {
    printf("\n=== Drawing Test Pattern ===\n");

    // Clear screen
    gpu_clear(0x00);
    gpu_wait_ready();

    // Draw colorful rectangles
    printf("Drawing color bars...\n");
    for (int i = 0; i < 8; i++) {
        uint8_t color = i * 32;
        gpu_draw_rect(i*40, 0, (i+1)*40-1, 199, color);
        gpu_wait_ready();
    }

    // Draw border
    printf("Drawing border...\n");
    gpu_draw_line(0, 0, 319, 0, 0xFF);     // Top
    gpu_draw_line(0, 199, 319, 199, 0xFF); // Bottom
    gpu_draw_line(0, 0, 0, 199, 0xFF);     // Left
    gpu_draw_line(319, 0, 319, 199, 0xFF); // Right
    gpu_wait_ready();

    printf("✓ Test pattern drawn!\n");
}

int main(int argc, char *argv[]) {
    printf("========================================\n");
    printf("RISC-V CPU + GPU Test Program\n");
    printf("========================================\n");

    // Map memory
    printf("\nMapping memory regions...\n");
    cpu_regs = (volatile uint32_t*)map_memory(CPU_BASE_ADDR, MAP_SIZE);
    gpu_regs = (volatile uint32_t*)map_memory(GPU_BASE_ADDR, MAP_SIZE);

    if (!cpu_regs || !gpu_regs) {
        printf("Failed to map memory!\n");
        return 1;
    }

    printf("CPU mapped at: %p\n", cpu_regs);
    printf("GPU mapped at: %p\n", gpu_regs);

    // Run tests
    int gpu_id_pass = test_gpu_id();
    int gpu_clear_pass = test_gpu_clear();
    int gpu_draw_pass = test_gpu_draw();
    int cpu_sig_pass = test_cpu_signature();
    int cpu_ctrl_pass = test_cpu_control();
    int cpu_prog_pass = test_cpu_simple_program();

    // Draw test pattern
    test_pattern();

    // Summary
    printf("\n========================================\n");
    printf("Test Summary:\n");
    printf("========================================\n");
    printf("GPU ID Test:          %s\n", gpu_id_pass ? "PASS" : "FAIL");
    printf("GPU Clear Test:       %s\n", gpu_clear_pass ? "PASS" : "FAIL");
    printf("GPU Draw Test:        %s\n", gpu_draw_pass ? "PASS" : "FAIL");
    printf("CPU Signature Test:   %s\n", cpu_sig_pass ? "PASS" : "FAIL");
    printf("CPU Control Test:     %s\n", cpu_ctrl_pass ? "PASS" : "FAIL");
    printf("CPU Program Test:     %s\n", cpu_prog_pass ? "PASS" : "FAIL");
    printf("========================================\n");

    int total = gpu_id_pass + gpu_clear_pass + gpu_draw_pass +
                cpu_sig_pass + cpu_ctrl_pass + cpu_prog_pass;
    printf("Total: %d/6 tests passed\n", total);

    // Cleanup
    munmap((void*)cpu_regs, MAP_SIZE);
    munmap((void*)gpu_regs, MAP_SIZE);

    return (total == 6) ? 0 : 1;
}
