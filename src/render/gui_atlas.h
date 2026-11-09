/* Vortex - the GUI sprite sheet.

   The menu widgets need pictures: a button is a bevelled surface, text is a
   grid of glyphs, a slider has a handle. This file assembles all of that into
   one 256 by 256 RGBA sheet at run time, from the tiny procedurally generated
   PNGs in gui_textures_embed.h plus a handful of shapes drawn here in C, so
   the repository carries no Mojang-derived art and the renderer has exactly
   one texture to bind for every 2D control.

   Nothing in here touches Vulkan. The renderer uploads vt_gui_atlas_pixels()
   into an image and asks vt_gui_atlas_region() where a named control lives;
   widget code asks for a control by name and never sees coordinates. */

#ifndef VT_GUI_ATLAS_H
#define VT_GUI_ATLAS_H

#define VT_GUI_ATLAS_SIZE 256

/* The sheet, built on the first call and returned from then on. The layout is
 * fixed: the glyph grid owns the top half and the controls the bottom, so the
 * regions below stay valid however the pixels are produced. */
const unsigned char *vt_gui_atlas_pixels(void);

/* Where a named control lives. `border` is the thickness of the part that must
 * keep its size when the control is stretched, which is how a 200 wide button
 * sprite still looks right at 98 wide. Returns 0 for an unknown name. */
int vt_gui_atlas_region(const char *kind, int *x, int *y, int *w, int *h, int *border);

/* The glyph grid: 16 by 16 cells of 8 by 8, addressed by character code, so
 * the code for 'A' (65) is column 1 of row 4. */
void vt_gui_atlas_glyph(int code, int *x, int *y);

#endif
