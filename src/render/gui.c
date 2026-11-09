/* Vortex - the menu GUI widgets. See gui.h for the contract. */

#include "gui.h"

#include <stdio.h>
#include <string.h>

/* The renderer's GUI buffer, in device pixels. */
extern void vt_gui_backend_rect(float x, float y, float w, float h,
                                float r, float g, float b, float a);
extern void vt_gui_backend_text(float x, float y, float scale, const char *text,
                               float r, float g, float b, float a);

#define GUI_FOCUS_SIZE 32
#define GUI_LABEL_SIZE 96

static float s_scale = 1.0f;
static float s_logical_w = 640.0f;
static float s_logical_h = 360.0f;

/* Input for this frame, in window pixels until the layout is known. */
static int s_pointer_x = 0;
static int s_pointer_y = 0;
static int s_down = 0;
static int s_click = 0;
static int s_wheel = 0;
static int s_key = VT_GUI_KEY_NONE;
static char s_typed[16] = "";

/* Which widget owns the keyboard and which owns an in-progress drag. A screen
 * transition clears both. */
static char s_focus[GUI_FOCUS_SIZE] = "";
static char s_active[GUI_FOCUS_SIZE] = "";
static char s_release[GUI_FOCUS_SIZE] = "";
static int s_focus_freed = 0;

static float to_logical(int pixels) { return (float)pixels / s_scale; }

static float px(float logical) { return logical * s_scale; }

void vt_gui_begin(int mouse_x, int mouse_y, int mouse_down, int clicked, int wheel,
                  int key, const char *typed) {
    s_pointer_x = mouse_x;
    s_pointer_y = mouse_y;
    s_down = mouse_down;
    s_click = clicked;
    s_wheel = wheel;
    s_key = key;
    s_typed[0] = '\0';
    if (typed != 0) {
        snprintf(s_typed, sizeof(s_typed), "%s", typed);
    }
    /* A press outside the focused field gives up the keyboard, the way a text
     * box does when the pointer goes elsewhere. */
    if (clicked && s_focus[0] != '\0' && s_active[0] == '\0') {
        s_focus_freed = 1;
    }
    s_release[0] = '\0';
    if (!mouse_down && s_active[0] != '\0') {
        snprintf(s_release, sizeof(s_release), "%s", s_active);
        s_active[0] = '\0';
    }
}

float vt_gui_layout(int screen_width, int screen_height) {
    /* The classic automatic scale: the largest whole factor that still leaves
     * at least 280 logical rows, from one to four. */
    int scale = (screen_height + 16) / 280;
    if (scale < 1) scale = 1;
    if (scale > 4) scale = 4;
    s_scale = (float)scale;
    s_logical_w = (float)screen_width / s_scale;
    s_logical_h = (float)screen_height / s_scale;
    return s_logical_w;
}

void vt_gui_set_scale(int scale, int screen_width, int screen_height) {
    /* The player picked a factor, so the logical space is simply the window
     * divided by it. Anything outside one to four falls back to auto. */
    if (scale < 1 || scale > 4) { vt_gui_layout(screen_width, screen_height); return; }
    s_scale = (float)scale;
    s_logical_w = (float)screen_width / s_scale;
    s_logical_h = (float)screen_height / s_scale;
}

float vt_gui_scale(void) { return s_scale; }
float vt_gui_logical_width(void) { return s_logical_w; }
float vt_gui_logical_height(void) { return s_logical_h; }

void vt_gui_reset(void) {
    s_focus[0] = '\0';
    s_active[0] = '\0';
    s_release[0] = '\0';
    s_focus_freed = 1;
}

int vt_gui_focus_cleared(int key) {
    return s_focus_freed || (key == VT_GUI_KEY_ESCAPE && s_focus[0] == '\0');
}

/* ---- primitives ------------------------------------------------------------ */

void vt_gui_rect(float x, float y, float w, float h, float r, float g, float b, float a) {
    vt_gui_backend_rect(px(x), px(y), px(w), px(h), r, g, b, a);
}

float vt_gui_text_width(const char *text) {
    if (text == 0) return 0.0f;
    return (float)strlen(text) * 8.0f;
}

float vt_gui_text(float x, float y, const char *text, float r, float g, float b) {
    if (text == 0) return 0.0f;
    /* One device pixel down and right is the vanilla drop shadow. */
    vt_gui_backend_text(px(x) + 1.0f, px(y) + 1.0f, s_scale, text, 0.0f, 0.0f, 0.0f, 1.0f);
    vt_gui_backend_text(px(x), px(y), s_scale, text, r, g, b, 1.0f);
    return vt_gui_text_width(text);
}

void vt_gui_text_centered(float y, const char *text, float r, float g, float b) {
    float x = (s_logical_w - vt_gui_text_width(text)) / 2.0f;
    vt_gui_text(x, y, text, r, g, b);
}

/* The bevelled control surface every widget shares. */
static void gui_surface(float x, float y, float w, float h, int hovered, int active,
                        int enabled) {
    float base = enabled ? (active ? 0.55f : (hovered ? 0.45f : 0.32f)) : 0.22f;
    float green = enabled ? (active ? 0.70f : (hovered ? 0.50f : 0.32f)) : 0.22f;
    vt_gui_rect(x, y, w, h, 0.06f, 0.06f, 0.06f, 1.0f);
    vt_gui_rect(x + 1, y + 1, w - 2, h - 2, base, green, base, 1.0f);
    vt_gui_rect(x + 1, y + 1, w - 2, 1, 0.85f, 0.85f, 0.85f, enabled ? 0.55f : 0.25f);
    vt_gui_rect(x + 1, y + 1, 1, h - 2, 0.85f, 0.85f, 0.85f, enabled ? 0.55f : 0.25f);
    vt_gui_rect(x + 1, y + h - 2, w - 2, 1, 0.10f, 0.10f, 0.10f, 0.75f);
    vt_gui_rect(x + w - 2, y + 1, 1, h - 2, 0.10f, 0.10f, 0.10f, 0.75f);
}

static int gui_inside(float x, float y, float w, float h) {
    float pointer_x = to_logical(s_pointer_x);
    float pointer_y = to_logical(s_pointer_y);
    return pointer_x >= x && pointer_x < x + w && pointer_y >= y && pointer_y < y + h;
}

static void gui_claim(const char *id) {
    snprintf(s_active, sizeof(s_active), "%s", id);
}

static int gui_released_by(const char *id) {
    return s_release[0] != '\0' && strcmp(s_release, id) == 0;
}

static void gui_label_centered(float x, float y, float w, const char *text,
                               int enabled) {
    float width = vt_gui_text_width(text);
    float rx = x + (w - width) / 2.0f;
    if (enabled) {
        vt_gui_text(rx, y, text, VT_GUI_TEXT);
    } else {
        vt_gui_text(rx, y, text, VT_GUI_TEXT_DIM);
    }
}

/* ---- widgets --------------------------------------------------------------- */

int vt_gui_button_enabled(const char *id, float x, float y, float w, float h,
                          const char *label, int enabled) {
    int hovered = enabled && gui_inside(x, y, w, h);
    if (s_click && hovered) gui_claim(id);
    gui_surface(x, y, w, h, hovered, strcmp(s_active, id) == 0, enabled);
    gui_label_centered(x, y + (h - 8.0f) / 2.0f, w, label, enabled);
    return enabled && gui_released_by(id) && hovered;
}

int vt_gui_button(const char *id, float x, float y, float w, float h, const char *label) {
    return vt_gui_button_enabled(id, x, y, w, h, label, 1);
}

void vt_gui_toggle(const char *id, float x, float y, float w, float h,
                   const char *label, int *value) {
    char text[GUI_LABEL_SIZE];
    snprintf(text, sizeof(text), "%s: %s", label, *value ? "ON" : "OFF");
    if (vt_gui_button(id, x, y, w, h, text) && value != 0) {
        *value = *value ? 0 : 1;
    }
}

void vt_gui_cycle(const char *id, float x, float y, float w, float h, const char *label,
                  const char *const *names, int count, int *index) {
    char text[GUI_LABEL_SIZE];
    int next;
    int reversed = s_down && s_pointer_x >= x && s_pointer_x < x + w
        && s_pointer_y >= y && s_pointer_y < y + h && s_active[0] == '\0';
    if (count < 1 || index == 0) return;
    snprintf(text, sizeof(text), "%s: %s", label, names[*index]);
    if (vt_gui_button(id, x, y, w, h, text) && names != 0) {
        next = *index + (reversed ? -1 : 1);
        if (next < 0) next = count - 1;
        if (next >= count) next = 0;
        *index = next;
    }
}

void vt_gui_slider(const char *id, float x, float y, float w, float h, const char *label,
                   float *value, float minimum, float maximum, const char *suffix) {
    char text[GUI_LABEL_SIZE];
    float span = maximum - minimum;
    float ratio = 0.0f;
    float track_x = x + 4.0f;
    float track_w = w - 8.0f;
    int hovered = gui_inside(x, y, w, h);

    if (value == 0 || span <= 0.0f) return;
    ratio = (*value - minimum) / span;
    if (ratio < 0.0f) ratio = 0.0f;
    if (ratio > 1.0f) ratio = 1.0f;

    if (s_click && hovered) gui_claim(id);
    if (strcmp(s_active, id) == 0 && s_down) {
        float pointer_x = to_logical(s_pointer_x);
        ratio = (pointer_x - track_x) / track_w;
        if (ratio < 0.0f) ratio = 0.0f;
        if (ratio > 1.0f) ratio = 1.0f;
        *value = minimum + ratio * span;
    }
    if (strcmp(s_focus, id) == 0) {
        float step = span / 20.0f;
        if (s_key == VT_GUI_KEY_LEFT) *value -= step;
        if (s_key == VT_GUI_KEY_RIGHT) *value += step;
        if (*value < minimum) *value = minimum;
        if (*value > maximum) *value = maximum;
    }

    gui_surface(x, y, w, h, hovered, strcmp(s_active, id) == 0, 1);
    snprintf(text, sizeof(text), "%s: %.0f%s", label, (double)*value,
             suffix == 0 ? "" : suffix);
    gui_label_centered(x, y + (h - 8.0f) / 2.0f - 5.0f, w, text, 1);

    /* The handle sits on the track, 8 wide like the classic control. */
    vt_gui_rect(track_x + ratio * track_w - 4.0f, y + h - 8.0f, 8.0f, 6.0f,
                0.85f, 0.85f, 0.85f, 1.0f);
    vt_gui_rect(track_x + ratio * track_w - 4.0f, y + h - 8.0f, 8.0f, 1.0f,
                0.30f, 0.30f, 0.30f, 1.0f);
}

int vt_gui_field(const char *id, float x, float y, float w, float h,
                 char *text, int capacity) {
    int hovered = gui_inside(x, y, w, h);
    int focused = strcmp(s_focus, id) == 0;
    int length;
    int changed = 0;
    int submitted = 0;

    if (text == 0 || capacity < 1) return 0;
    if (s_click && hovered) {
        snprintf(s_focus, sizeof(s_focus), "%s", id);
        s_active[0] = '\0';
        s_focus_freed = 0;
    }
    if (focused) {
        length = (int)strlen(text);
        if (s_typed[0] != '\0') {
            int added = (int)strlen(s_typed);
            if (length + added < capacity - 1) {
                snprintf(text + length, (size_t)(capacity - length), "%s", s_typed);
                changed = 1;
            }
        }
        if (s_key == VT_GUI_KEY_BACKSPACE && length > 0) {
            text[length - 1] = '\0';
            changed = 1;
        }
        if (s_key == VT_GUI_KEY_DELETE) {
            text[0] = '\0';
            changed = 1;
        }
        if (s_key == VT_GUI_KEY_ESCAPE) {
            s_focus[0] = '\0';
            s_focus_freed = 1;
        }
        if (s_key == VT_GUI_KEY_ENTER) {
            s_focus[0] = '\0';
            submitted = 2;
        }
    }

    gui_surface(x, y, w, h, hovered, focused, 1);
    vt_gui_rect(x + 3, y + 3, w - 6, h - 6, 0.06f, 0.06f, 0.06f, 1.0f);
    vt_gui_text(x + 6, y + (h - 8.0f) / 2.0f, text, VT_GUI_TEXT);
    if (focused) {
        float caret = x + 6.0f + vt_gui_text_width(text);
        if (caret + 2.0f < x + w - 3.0f) {
            vt_gui_rect(caret + 1.0f, y + (h - 10.0f) / 2.0f, 1.0f, 10.0f,
                        VT_GUI_TEXT, 1.0f);
        }
    }
    return submitted != 0 ? submitted : changed;
}

int vt_gui_list(const char *id, float x, float y, float w, float h,
                const char *const *rows, int count, int *selected, int *scroll) {
    /* Each row claims under its own id, so a list releases like a button: the
     * pick only lands if the pointer is lifted over the same row. */
    char row_id[GUI_FOCUS_SIZE];
    int row_height = 16;
    int visible = (int)(h / (float)row_height);
    int top = 0;
    int hit = -1;
    int index;
    float pointer_x = to_logical(s_pointer_x);
    float pointer_y = to_logical(s_pointer_y);
    int inside = gui_inside(x, y, w, h);

    if (rows == 0 || count < 0 || visible < 1) return -1;
    if (scroll != 0) {
        top = *scroll;
        if (s_wheel != 0 && inside) {
            top -= s_wheel;
            if (top < 0) top = 0;
            if (top > count - visible) top = count - visible;
            if (top < 0) top = 0;
            *scroll = top;
        }
    }

    vt_gui_rect(x, y, w, h, 0.06f, 0.06f, 0.06f, 0.75f);
    for (index = 0; index < visible && top + index < count; index++) {
        float row_y = y + index * (float)row_height;
        int row = top + index;
        int hovered = inside && pointer_y >= row_y && pointer_y < row_y + (float)row_height
            && pointer_x >= x && pointer_x < x + w;
        snprintf(row_id, sizeof(row_id), "%s.%d", id, row);
        if (hovered && s_click) gui_claim(row_id);
        if (hovered && gui_released_by(row_id)) hit = row;
        if (selected != 0 && row == *selected) {
            vt_gui_rect(x + 1, row_y, w - 2, (float)row_height, 0.20f, 0.20f, 0.60f, 0.85f);
        } else if (hovered) {
            vt_gui_rect(x + 1, row_y, w - 2, (float)row_height, 0.50f, 0.50f, 0.50f, 0.55f);
        }
        vt_gui_text(x + 6, row_y + 4.0f, rows[row], VT_GUI_TEXT);
    }
    if (scroll != 0 && count > visible) {
        /* The scroll trough and thumb, so a long list says how deep it is. */
        float trough_x = x + w - 4.0f;
        float thumb_h = (float)h * (float)visible / (float)count;
        float thumb_y = y + (float)h * (float)top / (float)count;
        vt_gui_rect(trough_x, y, 3.0f, h, 0.10f, 0.10f, 0.10f, 0.9f);
        vt_gui_rect(trough_x, thumb_y, 3.0f, thumb_h, 0.60f, 0.60f, 0.60f, 0.9f);
    }
    if (hit >= 0 && selected != 0) *selected = hit;
    return hit;
}
