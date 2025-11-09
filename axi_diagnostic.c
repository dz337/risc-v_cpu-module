#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#define CPU_BASE 0x44000000
#define MAP_SIZE 0x10000

#define CPU_INSTR_BASE  0x40

volatile uint32_t *cpu_vptr = NULL;

void write32_verbose(uint32_t offset, uint32_t value) {
    printf("  [WRITE] offset=0x%03X value=0x%08X\n", offset, value);
    *(cpu_vptr + (offset / 4)) = value;
    // Force memory barrier (DSB = Data Synchronization Barrier)
    asm volatile("dsb" : : : "memory");
}

uint32_t read32_verbose(uint32_t offset) {
    // Force memory barrier before read
    asm volatile("dsb" : : : "memory");
    uint32_t val = *(cpu_vptr + (offset / 4));
    printf("  [READ]  offset=0x%03X value=0x%08X\n", offset, val);
    return val;
}

int main() {
    printf("=== AXI Transaction Diagnostic ===\n\n");

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("Error opening /dev/mem");
        return 1;
    }

    cpu_vptr = (volatile uint32_t*)mmap(NULL, MAP_SIZE,
                                        PROT_READ | PROT_WRITE,
                                        MAP_SHARED, fd, CPU_BASE);
    if (cpu_vptr == MAP_FAILED) {
        perror("Error mapping memory");
        close(fd);
        return 1;
    }

    printf("CPU mapped successfully\n\n");

    // Test 1: Write one value, verify immediately
    printf("TEST 1: Single write with immediate readback\n");
    printf("---------------------------------------------\n");
    write32_verbose(CPU_INSTR_BASE + 0x00, 0xAAAAAAAA);
    read32_verbose(CPU_INSTR_BASE + 0x00);
    printf("\n");

    // Test 2: Two writes to DIFFERENT addresses, NO delay
    printf("TEST 2: Two writes (different addresses, no delay)\n");
    printf("---------------------------------------------------\n");
    write32_verbose(CPU_INSTR_BASE + 0x00, 0x11111111);
    write32_verbose(CPU_INSTR_BASE + 0x04, 0x22222222);
    printf("Readback:\n");
    uint32_t val1 = read32_verbose(CPU_INSTR_BASE + 0x00);
    uint32_t val2 = read32_verbose(CPU_INSTR_BASE + 0x04);

    if (val1 == 0x11111111 && val2 == 0x22222222) {
        printf("✓ PASS\n");
    } else {
        printf("✗ FAIL - Got 0x%08X and 0x%08X\n", val1, val2);
    }
    printf("\n");

    // Test 3: Three writes to SAME address
    printf("TEST 3: Three writes to SAME address (should see last value)\n");
    printf("-------------------------------------------------------------\n");
    write32_verbose(CPU_INSTR_BASE + 0x08, 0xBBBBBBBB);
    write32_verbose(CPU_INSTR_BASE + 0x08, 0xCCCCCCCC);
    write32_verbose(CPU_INSTR_BASE + 0x08, 0xDDDDDDDD);
    printf("Readback:\n");
    uint32_t val3 = read32_verbose(CPU_INSTR_BASE + 0x08);

    if (val3 == 0xDDDDDDDD) {
        printf("✓ PASS - Last write won\n");
    } else {
        printf("✗ FAIL - Got 0x%08X, expected 0xDDDDDDDD\n", val3);
    }
    printf("\n");

    // Test 4: Write, delay, write, delay pattern
    printf("TEST 4: Alternating write-delay pattern\n");
    printf("----------------------------------------\n");
    write32_verbose(CPU_INSTR_BASE + 0x10, 0xAAAAAAAA);
    usleep(10000); // 10ms
    write32_verbose(CPU_INSTR_BASE + 0x14, 0xBBBBBBBB);
    usleep(10000); // 10ms
    write32_verbose(CPU_INSTR_BASE + 0x18, 0xCCCCCCCC);
    usleep(10000); // 10ms

    printf("Readback:\n");
    uint32_t val4 = read32_verbose(CPU_INSTR_BASE + 0x10);
    uint32_t val5 = read32_verbose(CPU_INSTR_BASE + 0x14);
    uint32_t val6 = read32_verbose(CPU_INSTR_BASE + 0x18);

    if (val4 == 0xAAAAAAAA && val5 == 0xBBBBBBBB && val6 == 0xCCCCCCCC) {
        printf("✓ PASS\n");
    } else {
        printf("✗ FAIL\n");
    }
    printf("\n");

    // Test 5: Burst of 5 writes to consecutive addresses
    printf("TEST 5: Burst of 5 consecutive writes\n");
    printf("--------------------------------------\n");
    uint32_t test_values[] = {0x11111111, 0x22222222, 0x33333333, 0x44444444, 0x55555555};
    for (int i = 0; i < 5; i++) {
        write32_verbose(CPU_INSTR_BASE + 0x20 + (i*4), test_values[i]);
    }

    printf("Readback:\n");
    int pass = 1;
    for (int i = 0; i < 5; i++) {
        uint32_t val = read32_verbose(CPU_INSTR_BASE + 0x20 + (i*4));
        if (val != test_values[i]) {
            printf("  ✗ Address 0x%03X: expected 0x%08X, got 0x%08X\n",
                   0x20 + (i*4), test_values[i], val);
            pass = 0;
        }
    }
    if (pass) {
        printf("✓ PASS - All 5 values correct\n");
    }

    munmap((void*)cpu_vptr, MAP_SIZE);
    close(fd);

    printf("\n=== Diagnostic Complete ===\n");
    return 0;
}
