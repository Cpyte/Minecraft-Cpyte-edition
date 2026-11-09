/* Vortex - the GUI sprite sheet. See gui_atlas.h.
 *
 * The pixels come from three places, in this order of preference:
 *   - the embedded procedurally generated PNGs in gui_textures_embed.h,
 *   - shapes drawn here in C for controls that sheet does not carry,
 *   - nothing else. No Mojang-derived art is read or shipped.
 *
 * Building is done once into a static buffer. The renderer owns the upload,
 * so this file only ever deals in bytes. */

#include "gui_atlas.h"
#include "gui_textures_embed.h"

#include <png.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SHEET VT_GUI_ATLAS_SIZE

/* The layout. Buttons are the classic 200 by 20 and stack down the left edge;
 * the small controls share the column to their right. */
#define BUTTON_X 0
#define BUTTON_W 200
#define BUTTON_H 20
#define BUTTON_Y 128
#define HOVER_Y 150
#define ACTIVE_Y 172
#define DISABLED_Y 194
#define HANDLE_X 200
#define HANDLE_Y 128
#define HANDLE_W 8
#define HANDLE_H 20
#define SLOT_X 208
#define SLOT_Y 128
#define SLOT_W 18
#define SELECTION_X 208
#define SELECTION_Y 148

static unsigned char s_sheet[SHEET * SHEET * 4];
static int s_ready = 0;

/* ---- decoding the embedded PNGs ------------------------------------------- */

typedef struct {
    const unsigned char *bytes;
    size_t length;
    size_t at;
} PngStream;

static void png_stream_read(png_structp handle, png_bytep out, png_size_t count) {
    PngStream *stream = (PngStream *)png_get_io_ptr(handle);
    if (stream->at + count > stream->length) {
        png_error(handle, "embedded texture truncated");
    }
    memcpy(out, stream->bytes + stream->at, count);
    stream->at += count;
}

/* Always hands back RGBA8, whatever the source bit depth, colour type or
 * presence of a palette transparency chunk. Returns NULL if the bytes cannot be
 * read; the caller then uses the procedural stand-in. */
static unsigned char *decode_rgba(const unsigned char *bytes, unsigned length,
                                  int *out_width, int *out_height) {
    png_structp handle = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    png_infop info;
    PngStream stream;
    unsigned char **rows;
    unsigned char *rgba;
    int width, height, color_type, bit_depth, channels, y;

    if (!handle) return NULL;
    info = png_create_info_struct(handle);
    if (!info) {
        png_destroy_read_struct(&handle, NULL, NULL);
        return NULL;
    }
    if (setjmp(png_jmpbuf(handle))) {
        png_destroy_read_struct(&handle, &info, NULL);
        return NULL;
    }

    stream.bytes = bytes;
    stream.length = length;
    stream.at = 0;
    png_set_read_fn(handle, &stream, png_stream_read);
    png_read_info(handle, info);

    width = (int)png_get_image_width(handle, info);
    height = (int)png_get_image_height(handle, info);
    color_type = png_get_color_type(handle, info);
    bit_depth = png_get_bit_depth(handle, info);

    if (bit_depth == 16) png_set_strip_16(handle);
    if (color_type == PNG_COLOR_TYPE_PALETTE) png_set_palette_to_rgb(handle);
    if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8)
        png_set_expand_gray_1_2_4_to_8(handle);
    if (png_get_valid(handle, info, PNG_INFO_tRNS)) png_set_tRNS_to_alpha(handle);
    if (color_type == PNG_COLOR_TYPE_GRAY || color_type == PNG_COLOR_TYPE_GRAY_ALPHA)
        png_set_gray_to_rgb(handle);
    png_read_update_info(handle, info);

    color_type = png_get_color_type(handle, info);
    if (!(color_type & PNG_COLOR_MASK_ALPHA)) png_set_filler(handle, 0xFF, PNG_FILLER_AFTER);

    rows = (unsigned char **)malloc(sizeof(unsigned char *) * (size_t)height);
    rgba = (unsigned char *)malloc((size_t)width * (size_t)height * 4u);
    if (rows == NULL || rgba == NULL) {
        free(rows);
        free(rgba);
        png_destroy_read_struct(&handle, &info, NULL);
        return NULL;
    }
    for (y = 0; y < height; y++) rows[y] = rgba + (size_t)y * (size_t)width * 4u;
    png_read_image(handle, rows);
    png_destroy_read_struct(&handle, &info, NULL);
    free(rows);

    *out_width = width;
    *out_height = height;
    return rgba;
}

/* Nearest-neighbour blit with a colour multiply, which is how the grey button
 * art becomes the stone palette without storing two copies of it. */
static void blit(const unsigned char *source, int source_w, int source_h,
                 int x, int y, int width, int height,
                 float red, float green, float blue) {
    int row, column;
    if (source == NULL || width < 1 || height < 1) return;
    for (row = 0; row < height; row++) {
        int sy = (int)((long)row * source_h / height);
        for (column = 0; column < width; column++) {
            int sx = (int)((long)column * source_w / width);
            const unsigned char *pixel = source + ((size_t)sy * (size_t)source_w + (size_t)sx) * 4u;
            unsigned char *out = s_sheet + ((size_t)(y + row) * SHEET + (size_t)(x + column)) * 4u;
            float r = (float)pixel[0] * red;
            float g = (float)pixel[1] * green;
            float b = (float)pixel[2] * blue;
            out[0] = (unsigned char)(r > 255.0f ? 255.0f : r);
            out[1] = (unsigned char)(g > 255.0f ? 255.0f : g);
            out[2] = (unsigned char)(b > 255.0f ? 255.0f : b);
            out[3] = pixel[3];
        }
    }
}

/* ---- shapes drawn here ----------------------------------------------------- */

static void fill_rect(int x, int y, int width, int height,
                      unsigned char r, unsigned char g, unsigned char b, unsigned char a) {
    int row, column;
    for (row = 0; row < height; row++) {
        for (column = 0; column < width; column++) {
            unsigned char *out = s_sheet + ((size_t)(y + row) * SHEET + (size_t)(x + column)) * 4u;
            out[0] = r; out[1] = g; out[2] = b; out[3] = a;
        }
    }
}

static void frame_rect(int x, int y, int width, int height, int thickness,
                       unsigned char r, unsigned char g, unsigned char b, unsigned char a) {
    fill_rect(x, y, width, thickness, r, g, b, a);
    fill_rect(x, y + height - thickness, width, thickness, r, g, b, a);
    fill_rect(x, y + thickness, thickness, height - thickness * 2, r, g, b, a);
    fill_rect(x + width - thickness, y + thickness, thickness, height - thickness * 2, r, g, b, a);
}

/* The slider handle: a light bar with the same lit-top-left, dark-bottom-right
 * bevel the buttons use, so the two read as one family. */
static void draw_handle(void) {
    fill_rect(HANDLE_X, HANDLE_Y, HANDLE_W, HANDLE_H, 130, 132, 134, 255);
    fill_rect(HANDLE_X, HANDLE_Y, HANDLE_W, 1, 214, 216, 218, 255);
    fill_rect(HANDLE_X, HANDLE_Y, 1, HANDLE_H, 214, 216, 218, 255);
    fill_rect(HANDLE_X, HANDLE_Y + HANDLE_H - 1, HANDLE_W, 1, 24, 24, 26, 255);
    fill_rect(HANDLE_X + HANDLE_W - 1, HANDLE_Y, 1, HANDLE_H, 24, 24, 26, 255);
}

/* An inventory slot: recessed, with the highlight on the opposite corners to
 * the raised controls so it reads as a hole rather than a plate. */
static void draw_slot(void) {
    fill_rect(SLOT_X, SLOT_Y, SLOT_W, SLOT_W, 26, 26, 30, 255);
    fill_rect(SLOT_X, SLOT_Y, SLOT_W, 2, 12, 12, 14, 255);
    fill_rect(SLOT_X, SLOT_Y, 2, SLOT_W, 12, 12, 14, 255);
    fill_rect(SLOT_X, SLOT_Y + SLOT_W - 2, SLOT_W, 2, 120, 122, 126, 255);
    fill_rect(SLOT_X + SLOT_W - 2, SLOT_Y, 2, SLOT_W, 120, 122, 126, 255);
}

/* The square that says "this slot is the one under the pointer": an outline
 * with a see-through middle. */
static void draw_selection(void) {
    frame_rect(SELECTION_X, SELECTION_Y, SLOT_W, SLOT_W, 2, 235, 235, 235, 235);
}

/* ---- assembly -------------------------------------------------------------- */

static void build_sheet(void) {
    unsigned char *glyphs, *button, *hover, *disabled;
    int width, height, row, column;
    int button_w = 0, button_h = 0, hover_w = 0, hover_h = 0, disabled_w = 0, disabled_h = 0;

    for (row = 0; row < SHEET; row++) {
        for (column = 0; column < SHEET; column++) {
            unsigned char *out = s_sheet + ((size_t)row * SHEET + (size_t)column) * 4u;
            out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 0;
        }
    }

    glyphs = decode_rgba(g_embed_ascii_png, g_embed_ascii_png_len, &width, &height);
    if (glyphs != NULL && width == 128 && height == 128) {
        blit(glyphs, width, height, 0, 0, 128, 128, 1.0f, 1.0f, 1.0f);
    } else {
        /* Without the embedded grid the renderer still draws text from its own
         * 8 by 8 table, so an empty font region is a fall-back, not a fault. */
        for (row = 0; row < 16; row++)
            for (column = 0; column < 16; column++)
                fill_rect(column * 8, row * 8, 8, 8, 0, 0, 0, 0);
    }
    free(glyphs);

    button = decode_rgba(g_embed_button_png, g_embed_button_png_len, &button_w, &button_h);
    hover = decode_rgba(g_embed_button_h_png, g_embed_button_h_png_len, &hover_w, &hover_h);
    disabled = decode_rgba(g_embed_button_d_png, g_embed_button_d_png_len, &disabled_w, &disabled_h);
    /* The stone palette: the grey art is multiplied rather than recoloured per
     * vertex, so one sprite serves every widget. */
    blit(button, button_w, button_h, BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H,
         1.05f, 1.06f, 1.05f);
    blit(hover, hover_w, hover_h, BUTTON_X, HOVER_Y, BUTTON_W, BUTTON_H,
         1.15f, 1.20f, 1.15f);
    blit(disabled, disabled_w, disabled_h, BUTTON_X, DISABLED_Y, BUTTON_W, BUTTON_H,
         0.60f, 0.62f, 0.66f);
    blit(button, button_w, button_h, BUTTON_X, ACTIVE_Y, BUTTON_W, BUTTON_H,
         0.55f, 0.72f, 0.55f);
    free(button);
    free(hover);
    free(disabled);

    if (s_sheet[(BUTTON_Y + 10) * SHEET * 4 + 100 * 4 + 3] == 0) {
        /* Nothing decoded at all: keep the widgets legible with flat plates. */
        fill_rect(BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H, 92, 96, 92, 255);
        fill_rect(BUTTON_X, HOVER_Y, BUTTON_W, BUTTON_H, 118, 122, 118, 255);
        fill_rect(BUTTON_X, ACTIVE_Y, BUTTON_W, BUTTON_H, 74, 106, 74, 255);
        fill_rect(BUTTON_X, DISABLED_Y, BUTTON_W, BUTTON_H, 60, 62, 66, 255);
        frame_rect(BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H, 1, 200, 200, 200, 255);
        frame_rect(BUTTON_X, HOVER_Y, BUTTON_W, BUTTON_H, 1, 220, 220, 220, 255);
        frame_rect(BUTTON_X, ACTIVE_Y, BUTTON_W, BUTTON_H, 1, 150, 150, 150, 255);
        frame_rect(BUTTON_X, DISABLED_Y, BUTTON_W, BUTTON_H, 1, 90, 92, 96, 255);
    }

    draw_handle();
    draw_slot();
    draw_selection();
}

const unsigned char *vt_gui_atlas_pixels(void) {
    if (!s_ready) {
        build_sheet();
        s_ready = 1;
    }
    return s_sheet;
}

int vt_gui_atlas_region(const char *kind, int *x, int *y, int *w, int *h, int *border) {
    if (kind == NULL) return 0;
    vt_gui_atlas_pixels();
    if (strcmp(kind, "button") == 0) { *x = BUTTON_X; *y = BUTTON_Y; }
    else if (strcmp(kind, "button_hover") == 0) { *x = BUTTON_X; *y = HOVER_Y; }
    else if (strcmp(kind, "button_active") == 0) { *x = BUTTON_X; *y = ACTIVE_Y; }
    else if (strcmp(kind, "button_disabled") == 0) { *x = BUTTON_X; *y = DISABLED_Y; }
    else if (strcmp(kind, "handle") == 0) {
        *x = HANDLE_X; *y = HANDLE_Y; *w = HANDLE_W; *h = HANDLE_H; *border = 0; return 1;
    } else if (strcmp(kind, "slot") == 0) {
        *x = SLOT_X; *y = SLOT_Y; *w = SLOT_W; *h = SLOT_W; *border = 2; return 1;
    } else if (strcmp(kind, "selection") == 0) {
        *x = SELECTION_X; *y = SELECTION_Y; *w = SLOT_W; *h = SLOT_W; *border = 2; return 1;
    } else {
        return 0;
    }
    *w = BUTTON_W;
    *h = BUTTON_H;
    *border = 3;
    return 1;
}

void vt_gui_atlas_glyph(int code, int *x, int *y) {
    if (code < 0 || code > 255) code = '?';
    *x = (code % 16) * 8;
    *y = (code / 16) * 8;
}
