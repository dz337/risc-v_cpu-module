include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#define CPU_BASE 0x44000000
#define MAP_SIZE 0x10000

#define CPU_CTRL        0x00
#define CPU_STATUS      0x04
#define CPU_PC          0x08
#define CPU_INSTR_BASE  0x40
#define CPU_DATA_BASE   0x80

volatile uint32_t *cpu_vptr = NULL;

void write32(uint32_t offset, uint32_t value) {
    printf("  Writing 0x%08X to offset 0x%03X\n", value, offset);
    *(cpu_vptr + (offset / 4)) = value;
}

uint32_t read32(uint32_t offset) {
    uint32_t val = *(cpu_vptr + (offset / 4));
    printf("  Reading 0x%08X from offset 0x%03X\n", val, offset);
    return val;
}

int main() {
    printf("=== Simple CPU Debug Test ===\n\n");

    // Open /dev/mem
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("Error opening /dev/mem");
        return 1;
    }

    // Map CPU memory
    cpu_vptr = (volatile uint32_t*)mmap(NULL, MAP_SIZE,
                                        PROT_READ | PROT_WRITE,
                                        MAP_SHARED, fd, CPU_BASE);
    if (cpu_vptr == MAP_FAILED) {
        perror("Error mapping memory");
        close(fd);
        return 1;
    }

    printf("CPU mapped at virtual address: %p\n", cpu_vptr);
    printf("Physical base: 0x%08X\n\n", CPU_BASE);

    // Test 1: Single instruction write with delay
    printf("TEST 1: Single instruction write\n");
    printf("--------------------------------\n");
    write32(CPU_INSTR_BASE + 0x00, 0xAAAAAAAA);
    usleep(100000); // 100ms delay
    read32(CPU_INSTR_BASE + 0x00);
    printf("\n");

    // Test 2: Two instruction writes with delay
    printf("TEST 2: Two instruction writes with 100ms delay\n");
    printf("-----------------------------------------------\n");
    write32(CPU_INSTR_BASE + 0x00, 0x11111111);
    usleep(100000);
    write32(CPU_INSTR_BASE + 0x04, 0x22222222);
    usleep(100000);

    printf("Read back:\n");
    read32(CPU_INSTR_BASE + 0x00);
    read32(CPU_INSTR_BASE + 0x04);
    printf("\n");

    // Test 3: Three instruction writes with NO delay
    printf("TEST 3: Three back-to-back instruction writes (no delay)\n");
    printf("--------------------------------------------------------\n");
    write32(CPU_INSTR_BASE + 0x08, 0xBBBBBBBB);
    write32(CPU_INSTR_BASE + 0x0C, 0xCCCCCCCC);
    write32(CPU_INSTR_BASE + 0x10, 0xDDDDDDDD);

    usleep(100000); // Delay before readback

    printf("Read back:\n");
    read32(CPU_INSTR_BASE + 0x08);
    read32(CPU_INSTR_BASE + 0x0C);
    read32(CPU_INSTR_BASE + 0x10);
    printf("\n");

    // Test 4: Data memory - same tests
    printf("TEST 4: Single data write\n");
    printf("-------------------------\n");
    write32(CPU_DATA_BASE + 0x00, 0x12345678);
    usleep(100000);
    read32(CPU_DATA_BASE + 0x00);
    printf("\n");

    printf("TEST 5: Two data writes with delay\n");
    printf("-----------------------------------\n");
    write32(CPU_DATA_BASE + 0x04, 0xDEADBEEF);
    usleep(100000);
    write32(CPU_DATA_BASE + 0x08, 0xCAFEBABE);
    usleep(100000);

    printf("Read back:\n");
    read32(CPU_DATA_BASE + 0x04);
    read32(CPU_DATA_BASE + 0x08);
    printf("\n");

    printf("TEST 6: Three back-to-back data writes\n");
    printf("---------------------------------------\n");
    write32(CPU_DATA_BASE + 0x0C, 0xAAAAAAAA);
    write32(CPU_DATA_BASE + 0x10, 0xBBBBBBBB);
    write32(CPU_DATA_BASE + 0x14, 0xCCCCCCCC);

    usleep(100000);

    printf("Read back:\n");
    read32(CPU_DATA_BASE + 0x0C);
    read32(CPU_DATA_BASE + 0x10);
    read32(CPU_DATA_BASE + 0x14);
    printf("\n");

    // Cleanup
    munmap((void*)cpu_vptr, MAP_SIZE);
    close(fd);

    printf("=== Test Complete ===\n");
    return 0;
}
