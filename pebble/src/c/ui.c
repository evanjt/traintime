#include "ui.h"
#include "state.h"
#include "constants.h"
#include <math.h>

static Layer *s_canvas_layer;

// Fonts
static GFont s_font_large;
static GFont s_font_medium;
static GFont s_font_small;
static GFont s_font_tiny;

// Draw helpers
static void draw_centered_text(GContext *ctx, const char *text, GFont font, GRect bounds, GColor color) {
    graphics_context_set_text_color(ctx, color);
    graphics_draw_text(ctx, text, font, bounds, GTextOverflowModeTrailingEllipsis, GTextAlignmentCenter, NULL);
}

static void draw_left_text(GContext *ctx, const char *text, GFont font, GRect bounds, GColor color) {
    graphics_context_set_text_color(ctx, color);
    graphics_draw_text(ctx, text, font, bounds, GTextOverflowModeTrailingEllipsis, GTextAlignmentLeft, NULL);
}

static void draw_right_text(GContext *ctx, const char *text, GFont font, GRect bounds, GColor color) {
    graphics_context_set_text_color(ctx, color);
    graphics_draw_text(ctx, text, font, bounds, GTextOverflowModeTrailingEllipsis, GTextAlignmentRight, NULL);
}

// GPS indicator dot
static void draw_gps_dot(GContext *ctx, int x, int y) {
    GColor color;
    switch (g_state.gps_quality) {
        case GPS_GOOD: color = COLOR_AHEAD; break;
        case GPS_POOR: color = COLOR_DELAY; break;
        default: color = COLOR_BEHIND; break;
    }
    graphics_context_set_fill_color(ctx, color);
    graphics_fill_circle(ctx, GPoint(x, y), 4);
}

// Mode indicator icons
static void draw_mode_bar(GContext *ctx, int y) {
    const char *icons[] = {"T", "B", "R", "S"};
    int total_w = MODE_COUNT * 22 + (MODE_COUNT - 1) * 8;
    int start_x = (SCREEN_W - total_w) / 2;

    for (int m = 0; m < MODE_COUNT; m++) {
        int x = start_x + m * 30;
        GColor color;
        if (m == g_state.current_mode && g_state.mode_available[m]) {
            color = GColorWhite;
            // Circle background
            graphics_context_set_fill_color(ctx, GColorDarkGray);
            graphics_fill_circle(ctx, GPoint(x + 11, y + 10), 12);
        } else if (g_state.mode_available[m]) {
            color = GColorLightGray;
        } else {
            color = GColorDarkGray;
        }
        draw_centered_text(ctx, icons[m], s_font_medium, GRect(x, y - 2, 22, 24), color);
    }

    // GPS dot
    draw_gps_dot(ctx, start_x + total_w + 16, y + 10);
}

// Minutes color
static GColor minutes_color(int minutes, bool is_gone) {
    if (is_gone) return COLOR_MINUTES_GONE;
    if (minutes <= 2) return COLOR_MINUTES_NOW;
    return COLOR_MINUTES_SOON;
}

// Draw departure row
static void draw_departure_row(GContext *ctx, int y, Departure *dep, bool selected) {
    if (!dep->has_data) return;

    // Selection highlight
    if (selected) {
        graphics_context_set_fill_color(ctx, COLOR_SELECTION);
        graphics_fill_rect(ctx, GRect(10, y, SCREEN_W - 20, ROW_H), 4, GCornersAll);
    }

    bool is_gone = dep->minutes_until < 0;
    char min_buf[8];

    // Minutes text
    if (is_gone) {
        snprintf(min_buf, sizeof(min_buf), "gone");
    } else if (dep->minutes_until == 0) {
        snprintf(min_buf, sizeof(min_buf), "now");
    } else {
        snprintf(min_buf, sizeof(min_buf), "%d'", dep->minutes_until);
    }
    draw_right_text(ctx, min_buf, s_font_medium,
        GRect(12, y + 2, 36, ROW_H - 4),
        minutes_color(dep->minutes_until, is_gone));

    // Delay
    if (dep->delay > 0 && !is_gone) {
        char delay_buf[8];
        snprintf(delay_buf, sizeof(delay_buf), "+%d", dep->delay);
        draw_left_text(ctx, delay_buf, s_font_tiny,
            GRect(52, y + 6, 20, 16), COLOR_DELAY);
    }

    // Line/Platform
    int line_x = 74;
    if (dep->line_number[0] != '\0') {
        draw_left_text(ctx, dep->line_number, s_font_small,
            GRect(line_x, y + 4, 24, ROW_H - 8),
            is_gone ? COLOR_MINUTES_GONE : COLOR_PLATFORM);
    } else if (dep->platform[0] != '\0') {
        char plat_buf[8];
        snprintf(plat_buf, sizeof(plat_buf), "P%s", dep->platform);
        GColor pc = dep->platform_changed ? COLOR_PLAT_CHANGED : COLOR_PLATFORM;
        draw_left_text(ctx, plat_buf, s_font_small,
            GRect(line_x, y + 4, 24, ROW_H - 8),
            is_gone ? COLOR_MINUTES_GONE : pc);
    }

    // Destination
    draw_left_text(ctx, dep->destination, s_font_small,
        GRect(100, y + 4, SCREEN_W - 116, ROW_H - 8),
        is_gone ? COLOR_MINUTES_GONE : COLOR_STATION_NAME);
}

// Tracking bar
static void draw_tracking_bar(GContext *ctx, int y) {
    int bar_w = SCREEN_W - 40;
    int bar_x = 20;
    int mid_x = bar_x + bar_w / 2;
    double scale = BAR_SCALE;

    // Background
    graphics_context_set_fill_color(ctx, COLOR_BACKGROUND);
    graphics_fill_rect(ctx, GRect(bar_x, y, bar_w, BAR_H), 2, GCornersAll);

    if (g_state.gps_quality == GPS_UNAVAILABLE) {
        graphics_context_set_fill_color(ctx, COLOR_BAR_GRAY);
        graphics_fill_rect(ctx, GRect(bar_x, y, bar_w, BAR_H), 2, GCornersAll);
    } else if (g_state.focused.active) {
        double walk_min = (double)g_state.walk_dist / WALK_SPEED;
        double min_until = state_minutes_until_f(g_state.focused.departure_timestamp);
        double sched_buf = min_until - walk_min;
        double effect_buf = sched_buf + (double)g_state.focused.delay;

        // Clamp and convert to position
        double s_clamp = fmax(-scale, fmin(scale, sched_buf));
        double e_clamp = fmax(-scale, fmin(scale, effect_buf));
        int s_pos = mid_x + (int)(s_clamp / scale * (bar_w / 2));
        int e_pos = mid_x + (int)(e_clamp / scale * (bar_w / 2));

        if (sched_buf >= 0 && effect_buf >= 0) {
            // Both positive
            graphics_context_set_fill_color(ctx, COLOR_BAR_GREEN);
            if (s_pos > mid_x) graphics_fill_rect(ctx, GRect(mid_x, y, s_pos - mid_x, BAR_H), 0, GCornerNone);
            if (e_pos > s_pos) {
                graphics_context_set_fill_color(ctx, COLOR_BAR_LGREEN);
                graphics_fill_rect(ctx, GRect(s_pos, y, e_pos - s_pos, BAR_H), 0, GCornerNone);
            }
        } else if (sched_buf < 0 && effect_buf < 0) {
            // Both negative
            graphics_context_set_fill_color(ctx, COLOR_BAR_RED);
            if (mid_x > e_pos) graphics_fill_rect(ctx, GRect(e_pos, y, mid_x - e_pos, BAR_H), 0, GCornerNone);
            if (e_pos > s_pos) {
                graphics_context_set_fill_color(ctx, COLOR_BAR_AMBER);
                graphics_fill_rect(ctx, GRect(s_pos, y, e_pos - s_pos, BAR_H), 0, GCornerNone);
            }
        } else if (sched_buf < 0 && effect_buf >= 0) {
            // Mixed
            graphics_context_set_fill_color(ctx, COLOR_BAR_AMBER);
            if (mid_x > s_pos) graphics_fill_rect(ctx, GRect(s_pos, y, mid_x - s_pos, BAR_H), 0, GCornerNone);
            graphics_context_set_fill_color(ctx, COLOR_BAR_LGREEN);
            if (e_pos > mid_x) graphics_fill_rect(ctx, GRect(mid_x, y, e_pos - mid_x, BAR_H), 0, GCornerNone);
        }
    }

    // Center marker
    graphics_context_set_fill_color(ctx, COLOR_BAR_GRAY);
    graphics_fill_rect(ctx, GRect(mid_x - 1, y, 2, BAR_H), 0, GCornerNone);
}

// Draw station view (state 0)
static void draw_station_view(GContext *ctx) {
    // Mode bar
    draw_mode_bar(ctx, 8);

    // Walk info
    Station *station = state_current_station();
    if (station) {
        char *walk = state_format_walk_info(station->dist);
        draw_centered_text(ctx, walk, s_font_tiny, GRect(0, 32, SCREEN_W, 16), COLOR_WALK_INFO);

        // Station name
        char name_upper[64];
        strncpy(name_upper, station->name, sizeof(name_upper));
        for (int i = 0; name_upper[i]; i++) {
            if (name_upper[i] >= 'a' && name_upper[i] <= 'z')
                name_upper[i] -= 32;
        }
        draw_centered_text(ctx, name_upper, s_font_medium, GRect(10, 46, SCREEN_W - 20, 22), COLOR_STATION_NAME);

        // Separator
        graphics_context_set_stroke_color(ctx, COLOR_SEPARATOR);
        graphics_draw_line(ctx, GPoint(20, 70), GPoint(SCREEN_W - 20, 70));

        // Departures
        if (g_state.departure_count == 0) {
            draw_centered_text(ctx, "Loading...", s_font_small, GRect(0, 80, SCREEN_W, 20), COLOR_WALK_INFO);
        } else {
            int visible = g_state.departure_count < MAX_VISIBLE_DEPARTURES ? g_state.departure_count : MAX_VISIBLE_DEPARTURES;
            for (int i = 0; i < visible; i++) {
                draw_departure_row(ctx, 74 + i * ROW_H, &g_state.departures[i], false);
            }
        }
    } else {
        // No station yet
        draw_centered_text(ctx, g_state.status, s_font_small, GRect(10, 70, SCREEN_W - 20, 40), COLOR_WALK_INFO);
    }
}

// Draw cursor view (state 1)
static void draw_cursor_view(GContext *ctx) {
    // Station name
    Station *station = state_current_station();
    if (station) {
        draw_centered_text(ctx, station->name, s_font_small, GRect(10, 10, SCREEN_W - 20, 20), COLOR_WALK_INFO);
    }

    // Separator
    graphics_context_set_stroke_color(ctx, COLOR_SEPARATOR);
    graphics_draw_line(ctx, GPoint(20, 32), GPoint(SCREEN_W - 20, 32));

    // Departures with cursor
    int visible = g_state.departure_count < MAX_VISIBLE_DEPARTURES ? g_state.departure_count : MAX_VISIBLE_DEPARTURES;
    for (int i = 0; i < visible; i++) {
        bool selected = (i == g_state.cursor_index);
        draw_departure_row(ctx, 36 + i * ROW_H, &g_state.departures[i], selected);
    }

    // Hint at bottom
    draw_centered_text(ctx, "SELECT to track", s_font_tiny,
        GRect(0, SCREEN_H - 22, SCREEN_W, 16), COLOR_SEL_ACCENT);
}

// Draw tracking view (state 2)
static void draw_tracking_view(GContext *ctx) {
    FocusedDeparture *f = &g_state.focused;
    if (!f->active) return;

    // Station name
    Station *station = state_current_station();
    if (station) {
        draw_centered_text(ctx, station->name, s_font_tiny, GRect(10, 8, SCREEN_W - 20, 16), COLOR_WALK_INFO);
    }

    // Destination
    GColor dest_color = f->platform_changed ? COLOR_DELAY : COLOR_STATION_NAME;
    draw_centered_text(ctx, f->destination, s_font_medium, GRect(10, 24, SCREEN_W - 20, 22), dest_color);

    // Platform
    if (f->platform[0] != '\0') {
        char plat_buf[12];
        snprintf(plat_buf, sizeof(plat_buf), "P%s", f->platform);
        GColor pc = f->platform_changed ? COLOR_PLAT_CHANGED : COLOR_PLATFORM;
        draw_centered_text(ctx, plat_buf, s_font_small, GRect(0, 46, SCREEN_W, 18), pc);
    }

    // Countdown
    int secs = state_seconds_until(f->departure_timestamp);
    char countdown[16];
    if (secs < -30) {
        snprintf(countdown, sizeof(countdown), "Departed");
    } else if (secs < 5) {
        snprintf(countdown, sizeof(countdown), "now");
    } else {
        int mins = secs / 60;
        int rem = secs % 60;
        if (mins < 3) {
            snprintf(countdown, sizeof(countdown), "%d:%02d", mins, rem);
        } else {
            snprintf(countdown, sizeof(countdown), "%d min", mins);
        }
    }

    double min_f = state_minutes_until_f(f->departure_timestamp);
    GColor cd_color = COLOR_MINUTES_SOON;
    if (min_f < -0.5) cd_color = COLOR_MINUTES_GONE;
    else if (min_f < 2.0) cd_color = COLOR_MINUTES_NOW;

    draw_centered_text(ctx, countdown, s_font_large, GRect(0, 62, SCREEN_W, 36), cd_color);

    // Delay badge
    if (f->delay > 0 && min_f >= -0.5) {
        char delay_buf[8];
        snprintf(delay_buf, sizeof(delay_buf), "+%d", f->delay);
        draw_centered_text(ctx, delay_buf, s_font_small, GRect(0, 96, SCREEN_W, 18), COLOR_DELAY);
    }

    // Tracking bar
    draw_tracking_bar(ctx, 116);

    // Status text
    double walk_min = (double)g_state.walk_dist / WALK_SPEED;
    double sched_buf = min_f - walk_min;
    double effect_buf = sched_buf + (double)f->delay;

    char status[32];
    GColor status_color = COLOR_ON_TIME;
    if (g_state.gps_quality == GPS_UNAVAILABLE) {
        snprintf(status, sizeof(status), "No GPS");
        status_color = COLOR_BAR_GRAY;
    } else {
        double abs_buf = fabs(effect_buf);
        if (abs_buf < 0.5) {
            snprintf(status, sizeof(status), "On time");
        } else if (abs_buf < 1.5) {
            snprintf(status, sizeof(status), "%ds %s", (int)(abs_buf * 60), effect_buf > 0 ? "ahead" : "behind");
        } else {
            snprintf(status, sizeof(status), "%d min %s", (int)abs_buf, effect_buf > 0 ? "ahead" : "behind");
        }
        if (effect_buf > 0.5) status_color = COLOR_AHEAD;
        else if (effect_buf < -0.5) status_color = COLOR_BEHIND;
    }
    draw_centered_text(ctx, status, s_font_small, GRect(0, 130, SCREEN_W, 18), status_color);

    // Walk info
    char *walk = state_format_walk_info(g_state.walk_dist);
    draw_centered_text(ctx, walk, s_font_tiny, GRect(0, 150, SCREEN_W, 16), COLOR_WALK_INFO);
}

// Draw inactive view (state 3)
static void draw_inactive_view(GContext *ctx) {
    draw_centered_text(ctx, "✓", s_font_large, GRect(0, 50, SCREEN_W, 40), COLOR_WALK_INFO);
    draw_centered_text(ctx, "Inactive", s_font_medium, GRect(0, 90, SCREEN_W, 24), COLOR_WALK_INFO);
    draw_centered_text(ctx, "Press any button", s_font_tiny, GRect(0, 116, SCREEN_W, 16), GColorDarkGray);
}

// Main update callback
static void canvas_update_proc(Layer *layer, GContext *ctx) {
    // Clear background
    graphics_context_set_fill_color(ctx, COLOR_BACKGROUND);
    graphics_fill_rect(ctx, layer_get_bounds(layer), 0, GCornerNone);

    switch (g_state.state) {
        case 0: draw_station_view(ctx); break;
        case 1: draw_cursor_view(ctx); break;
        case 2: draw_tracking_view(ctx); break;
        case 3: draw_inactive_view(ctx); break;
    }
}

void ui_init(Window *window) {
    Layer *window_layer = window_get_root_layer(window);
    GRect bounds = layer_get_bounds(window_layer);

    s_canvas_layer = layer_create(bounds);
    layer_set_update_proc(s_canvas_layer, canvas_update_proc);
    layer_add_child(window_layer, s_canvas_layer);

    s_font_large = fonts_get_system_font(FONT_KEY_LECO_32_BOLD_NUMBERS);
    s_font_medium = fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD);
    s_font_small = fonts_get_system_font(FONT_KEY_GOTHIC_18);
    s_font_tiny = fonts_get_system_font(FONT_KEY_GOTHIC_14);
}

void ui_deinit(void) {
    layer_destroy(s_canvas_layer);
}

void ui_update(void) {
    layer_mark_dirty(s_canvas_layer);
}
