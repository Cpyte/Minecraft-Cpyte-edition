/* Vortex - the menu GUI: widgets, layout and input routing.
 *
 * Everything here is immediate mode: a screen calls the widgets in order each
 * frame, and the only state that survives a frame is the keyboard focus, the
 * widget being dragged and the scroll offsets, all held in this file. A widget
 * reports the one thing a caller cannot derive - that it was just activated -
 * through its return value, so a screen's logic reads as a list of tests.
 *
 * Coordinates are logical GUI pixels, the classic Minecraft space: a screen is
 * width/scale by height/scale where the scale comes from the display height,
 * so a button is always 200 by 20 and text is always 8 units tall no matter how
 * large the window is. The 8 by 8 glyph grid matches that unit exactly, which
 * is why text takes no scale argument here.
 *
 * The quads and glyphs are drawn through the two externs below, which the
 * renderer implements against its GUI vertex buffer. Keeping that seam here
 * means this file has no Vulkan, SDL or shader knowledge at all. */

#ifndef VT_GUI_H
#define VT_GUI_H

#include <stddef.h>

/* Key codes handed to vt_gui_begin, so this module does not need SDL. */
#define VT_GUI_KEY_NONE       0
#define VT_GUI_KEY_BACKSPACE  1
#define VT_GUI_KEY_ENTER      2
#define VT_GUI_KEY_ESCAPE     3
#define VT_GUI_KEY_TAB        4
#define VT_GUI_KEY_LEFT       5
#define VT_GUI_KEY_RIGHT      6
#define VT_GUI_KEY_UP         7
#define VT_GUI_KEY_DOWN       8
#define VT_GUI_KEY_HOME       9
#define VT_GUI_KEY_END       10
#define VT_GUI_KEY_DELETE    11

/* Starts a frame. `mouse_x`/`mouse_y` are window pixels, `mouse_down` is the
 * held state of the left button, `clicked` is its press edge this frame, and
 * `wheel` is the scroll delta in clicks. `key` and `typed` carry at most one
 * keyboard event per frame, which is enough because a frame is far slower than
 * typing. */
void vt_gui_begin(int mouse_x, int mouse_y, int mouse_down, int clicked, int wheel,
                  int key, const char *typed);

/* Chooses the GUI scale from the window size and returns the logical width.
 * The height of the logical space follows from the same scale. */
float vt_gui_layout(int screen_width, int screen_height);
/* The same layout maths with the scale the player chose in the options
 * screen instead of the one derived from the window height. */
void vt_gui_set_scale(int scale, int screen_width, int screen_height);

float vt_gui_scale(void);
float vt_gui_logical_width(void);
float vt_gui_logical_height(void);

/* Colours used by every widget, in the classic palette. */
#define VT_GUI_TEXT        0.90f, 0.90f, 0.90f
#define VT_GUI_TEXT_LIGHT  1.00f, 1.00f, 0.60f
#define VT_GUI_TEXT_DIM    0.50f, 0.50f, 0.50f

/* A centred line of text in logical units; returns its width for layout. */
float vt_gui_text(float x, float y, const char *text, float r, float g, float b);
float vt_gui_text_width(const char *text);
void vt_gui_text_centered(float y, const char *text, float r, float g, float b);

/* A flat rectangle, the seam every panel is built from. */
void vt_gui_rect(float x, float y, float w, float h, float r, float g, float b, float a);

/* Returns 1 on the frame its button is pressed. */
int vt_gui_button(const char *id, float x, float y, float w, float h, const char *label);
/* A disabled button draws grey and never activates. */
int vt_gui_button_enabled(const char *id, float x, float y, float w, float h,
                          const char *label, int enabled);

/* On and off, drawn as a button whose label carries the value. */
void vt_gui_toggle(const char *id, float x, float y, float w, float h,
                   const char *label, int *value);

/* Cycles through `names` on click; the label shows name and value. */
void vt_gui_cycle(const char *id, float x, float y, float w, float h, const char *label,
                  const char *const *names, int count, int *index);

/* Dragged with the mouse, or stepped with the arrow keys once focused. */
void vt_gui_slider(const char *id, float x, float y, float w, float h, const char *label,
                   float *value, float minimum, float maximum, const char *suffix);

/* A single-line editor. Returns 1 when its text changed, and 2 when Enter was
 * pressed with the field focused, which is how a screen sees "submit". */
int vt_gui_field(const char *id, float x, float y, float w, float h,
                 char *text, int capacity);

/* A vertical list of rows, one selected. Returns the row clicked this frame,
 * or -1. `scroll` is the caller's top row and is updated by the wheel. */
int vt_gui_list(const char *id, float x, float y, float w, float h,
                const char *const *rows, int count, int *selected, int *scroll);

/* Whether a frame ended with no widget focused, which is when a screen may
 * treat Escape as "go back". */
int vt_gui_focus_cleared(int key);

/* Drops focus and the drag capture, for a screen transition. */
void vt_gui_reset(void);

#endif /* VT_GUI_H */
