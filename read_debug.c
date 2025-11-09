#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#define CPU_BASE 0x44000000
#define MAP_SIZE 0x10000

#define CPU_INSTR_BASE  0x40
#define DEBUG_LAST_ADDR 0x30
#define DEBUG_LAST_DATA 0x34
#define DEBUG_WRITE_CNT 0x38
#define DEBUG_STATE     0x3C

volatile uint32_t *cpu_vptr = NULL;

uint32_t read32(uint32_t offset) {
    return *(cpu_vptr + (offset / 4));
}

void write32(uint32_t offset, uint32_t value) {
    *(cpu_vptr + (offset / 4)) = value;
    asm volatile("dsb" : : : "memory");
}

int main() {
    printf("=== Debug Register Reader ===\n\n");

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

    // Read initial debug state
    printf("Initial Debug State:\n");
    printf("  Last Addr:   0x%08X\n", read32(DEBUG_LAST_ADDR));
    printf("  Last Data:   0x%08X\n", read32(DEBUG_LAST_DATA));
    printf("  Write Count: %u\n", read32(DEBUG_WRITE_CNT));
    printf("  State:       0x%08X\n", read32(DEBUG_STATE));
    printf("\n");

    // Do a test write sequence
    printf("Writing test sequence to 0x40, 0x44, 0x48...\n");
    write32(CPU_INSTR_BASE + 0x00, 0xAAAAAAAA);
    write32(CPU_INSTR_BASE + 0x04, 0xBBBBBBBB);
    write32(CPU_INSTR_BASE + 0x08, 0xCCCCCCCC);

    usleep(10000); // Small delay

    printf("\nDebug State After Writes:\n");
    printf("  Last Addr:   0x%08X\n", read32(DEBUG_LAST_ADDR));
    printf("  Last Data:   0x%08X\n", read32(DEBUG_LAST_DATA));
    printf("  Write Count: %u\n", read32(DEBUG_WRITE_CNT));
    printf("  State:       0x%08X\n", read32(DEBUG_STATE));
    printf("\n");

    // Read back the values
    printf("Reading back from memory:\n");
    printf("  [0x40] = 0x%08X (expected 0xAAAAAAAA)\n", read32(CPU_INSTR_BASE + 0x00));
    printf("  [0x44] = 0x%08X (expected 0xBBBBBBBB)\n", read32(CPU_INSTR_BASE + 0x04));
    printf("  [0x48] = 0x%08X (expected 0xCCCCCCCC)\n", read32(CPU_INSTR_BASE + 0x08));

    munmap((void*)cpu_vptr, MAP_SIZE);
    close(fd);
    return 0;
}


