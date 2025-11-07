#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>

#define GPU_BASE_ADDR    0x43000000
#define MAP_SIZE         4096

// GPU register offsets
#define GPU_ID           0x00
#define GPU_STATUS       0x04
#define GPU_CMD          0x0C
#define GPU_ARG0         0x10
#define GPU_ARG1         0x14
#define GPU_COLOR        0x20
#define GPU_FB_READ      0x40
#define GPU_FB_DATA      0x44

// GPU commands
#define CMD_CLEAR        0x01
#define CMD_FILL_RECT    0x02
#define CMD_DRAW_LINE    0x03
#define CMD_DRAW_PIXEL   0x04

// Screen dimensions
#define WIDTH  320
#define HEIGHT 200

volatile uint32_t *gpu_regs = NULL;

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
    uint32_t addr = y * WIDTH + x;
    gpu_regs[GPU_FB_READ/4] = addr;
    usleep(1);
    return gpu_regs[GPU_FB_DATA/4] & 0xFF;
}

void draw_demo_scene() {
    printf("Drawing demo scene...\n");

    // Clear to black
    printf("  Clearing screen...\n");
    gpu_clear(0x00);
    gpu_wait_ready();

    // Draw background gradient bars
    printf("  Drawing gradient bars...\n");
    for (int i = 0; i < 8; i++) {
        uint8_t color = i * 32;
        gpu_draw_rect(0, i*25, WIDTH-1, (i+1)*25-1, color);
        gpu_wait_ready();
    }

    // Draw a Pong-style scene
    printf("  Drawing paddles...\n");
    // Left paddle
    gpu_draw_rect(20, 70, 30, 130, 0xFF);
    gpu_wait_ready();

    // Right paddle
    gpu_draw_rect(289, 50, 299, 110, 0xFF);
    gpu_wait_ready();

    // Draw ball
    printf("  Drawing ball...\n");
    gpu_draw_rect(155, 95, 165, 105, 0xFF);
    gpu_wait_ready();

    // Draw center line (dashed)
    printf("  Drawing center line...\n");
    for (int y = 0; y < HEIGHT; y += 10) {
        gpu_draw_line(WIDTH/2, y, WIDTH/2, y+5, 0x80);
        gpu_wait_ready();
    }

    // Draw borders
    printf("  Drawing borders...\n");
    gpu_draw_line(0, 0, WIDTH-1, 0, 0xFF);       // Top
    gpu_draw_line(0, HEIGHT-1, WIDTH-1, HEIGHT-1, 0xFF); // Bottom
    gpu_wait_ready();

    // Draw some text-like blocks for "PONG"
    printf("  Drawing title blocks...\n");
    // P
    gpu_draw_rect(130, 10, 135, 30, 0xFF);
    gpu_draw_rect(135, 10, 145, 15, 0xFF);
    gpu_draw_rect(135, 18, 145, 23, 0xFF);
    gpu_draw_rect(145, 10, 150, 23, 0xFF);
    gpu_wait_ready();

    // O
    gpu_draw_rect(155, 10, 160, 30, 0xFF);
    gpu_draw_rect(160, 10, 170, 15, 0xFF);
    gpu_draw_rect(160, 25, 170, 30, 0xFF);
    gpu_draw_rect(170, 10, 175, 30, 0xFF);
    gpu_wait_ready();

    printf("  Scene complete!\n");
}

void dump_framebuffer_ppm(const char *filename) {
    printf("Reading framebuffer...\n");

    FILE *fp = fopen(filename, "wb");
    if (!fp) {
        perror("Error opening output file");
        return;
    }

    // Write PPM header (P6 = binary RGB)
    fprintf(fp, "P6\n%d %d\n255\n", WIDTH, HEIGHT);

    // Read each pixel and convert 8-bit grayscale to RGB
    for (int y = 0; y < HEIGHT; y++) {
        if (y % 20 == 0) {
            printf("  Row %d/%d\r", y, HEIGHT);
            fflush(stdout);
        }

        for (int x = 0; x < WIDTH; x++) {
            uint8_t pixel = gpu_read_pixel(x, y);

            // Convert 8-bit value to RGB
            // Treat as grayscale for now
            uint8_t rgb[3] = {pixel, pixel, pixel};
            fwrite(rgb, 1, 3, fp);
        }
    }

    printf("  Row %d/%d\n", HEIGHT, HEIGHT);
    fclose(fp);
    printf("Framebuffer saved to %s\n", filename);
}

void dump_framebuffer_raw(const char *filename) {
    printf("Reading raw framebuffer...\n");

    FILE *fp = fopen(filename, "wb");
    if (!fp) {
        perror("Error opening output file");
        return;
    }

    // Write width and height as header
    int width = WIDTH;
    int height = HEIGHT;
    fwrite(&width, sizeof(int), 1, fp);
    fwrite(&height, sizeof(int), 1, fp);

    // Read and write each pixel
    for (int y = 0; y < HEIGHT; y++) {
        if (y % 20 == 0) {
            printf("  Row %d/%d\r", y, HEIGHT);
            fflush(stdout);
        }

        for (int x = 0; x < WIDTH; x++) {
            uint8_t pixel = gpu_read_pixel(x, y);
            fwrite(&pixel, 1, 1, fp);
        }
    }

    printf("  Row %d/%d\n", HEIGHT, HEIGHT);
    fclose(fp);
    printf("Raw framebuffer saved to %s\n", filename);
}

int main(int argc, char *argv[]) {
    printf("========================================\n");
    printf("Framebuffer Dumper with Demo Scene\n");
    printf("========================================\n\n");

    // Map GPU memory
    gpu_regs = (volatile uint32_t*)map_memory(GPU_BASE_ADDR, MAP_SIZE);
    if (!gpu_regs) {
        printf("Failed to map GPU memory!\n");
        return 1;
    }

    // Check GPU ID
    uint32_t id = gpu_regs[GPU_ID/4];
    printf("GPU ID: 0x%08X\n", id);
    if (id != 0xABCD1234) {
        printf("Warning: GPU ID incorrect!\n");
    }

    // Draw demo scene
    printf("\n");
    draw_demo_scene();

    // Wait a bit for all operations to complete
    printf("\nWaiting for GPU to finish...\n");
    sleep(1);

    // Dump framebuffer to PPM (viewable image)
    printf("\n");
    dump_framebuffer_ppm("framebuffer.ppm");

    // Also save raw format
    dump_framebuffer_raw("framebuffer.raw");

    printf("\n========================================\n");
    printf("Done!\n");
    printf("========================================\n");
    printf("\nTo view the image:\n");
    printf("1. Copy framebuffer.ppm to your PC:\n");
    printf("   scp root@rp-f0c5bf.local:~/framebuffer.ppm .\n");
    printf("2. View with any image viewer that supports PPM\n");
    printf("   (GIMP, IrfanView, ImageMagick, etc.)\n");
    printf("3. Or convert to PNG:\n");
    printf("   convert framebuffer.ppm framebuffer.png\n");
    printf("\n");

    // Cleanup
    munmap((void*)gpu_regs, MAP_SIZE);

    return 0;
}



