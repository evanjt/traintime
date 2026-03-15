#include <pebble.h>
#include "state.h"
#include "ui.h"
#include "messaging.h"
#include "constants.h"
#include <math.h>

static Window *s_main_window;
static AppTimer *s_tick_timer;

// Timer tick
static void tick_handler(void *data) {
    // Auto-exit tracking when departed
    if (g_state.state == 2 && g_state.focused.active) {
        double min_f = state_minutes_until_f(g_state.focused.departure_timestamp);
        if (min_f < -1.0) {
            vibes_short_pulse();
            state_enter_inactive();
            ui_update();
        }

        // Heartbeat when behind
        double walk_min = (double)g_state.walk_dist / WALK_SPEED;
        double effect_buf = min_f - walk_min + (double)g_state.focused.delay;
        if (effect_buf < -0.5) {
            time_t now = time(NULL);
            int interval = effect_buf < -2.0 ? 2 : 4;
            if (now - g_state.last_vibe_tick >= interval) {
                vibes_short_pulse();
                g_state.last_vibe_tick = now;
            }
        }
    }

    // Inactivity timeout in station view
    if (g_state.state == 0 && time(NULL) - g_state.last_interaction_time >= INACTIVITY_TIMEOUT) {
        state_enter_inactive();
        ui_update();
    }

    // Fetch cooldown check
    if (g_state.state != 3) {
        time_t now = time(NULL);
        int cooldown = g_state.state == 2 ? FETCH_COOLDOWN_TRACKING : FETCH_COOLDOWN_NORMAL;
        if (now - g_state.last_fetch_time >= cooldown) {
            Station *station = state_current_station();
            if (station && station->has_data) {
                messaging_request_departures(station->id);
            } else if (g_state.station_count[g_state.current_mode] == 0) {
                messaging_request_stations();
            }
        }
    }

    ui_update();

    // Reschedule
    int interval = g_state.state == 2 ? TRACKING_TICK_INTERVAL : NORMAL_TICK_INTERVAL;
    s_tick_timer = app_timer_register(interval, tick_handler, NULL);
}

// Button handlers
static void up_click_handler(ClickRecognizerRef recognizer, void *context) {
    g_state.last_interaction_time = time(NULL);
    switch (g_state.state) {
        case 0: {
            int count = g_state.station_count[g_state.current_mode];
            if (count > 1) {
                g_state.station_index = (g_state.station_index + 1) % count;
                g_state.departure_count = 0;
                Station *s = state_current_station();
                if (s && s->has_data) messaging_request_departures(s->id);
            }
            break;
        }
        case 1:
            if (g_state.cursor_index > 0) g_state.cursor_index--;
            break;
        case 3:
            state_resume();
            break;
        default:
            break;
    }
    ui_update();
}

static void down_click_handler(ClickRecognizerRef recognizer, void *context) {
    g_state.last_interaction_time = time(NULL);
    switch (g_state.state) {
        case 0:
            state_cycle_mode();
            {
                Station *s = state_current_station();
                if (s && s->has_data) messaging_request_departures(s->id);
            }
            break;
        case 1: {
            int max_cursor = g_state.departure_count < MAX_VISIBLE_DEPARTURES ?
                g_state.departure_count - 1 : MAX_VISIBLE_DEPARTURES - 1;
            if (g_state.cursor_index < max_cursor) g_state.cursor_index++;
            break;
        }
        case 3:
            state_resume();
            break;
        default:
            break;
    }
    ui_update();
}

static void select_click_handler(ClickRecognizerRef recognizer, void *context) {
    g_state.last_interaction_time = time(NULL);
    switch (g_state.state) {
        case 0:
            if (g_state.departure_count > 0) {
                g_state.state = 1;
                g_state.cursor_index = 0;
            }
            break;
        case 1:
            state_select_departure(g_state.cursor_index);
            break;
        case 3:
            state_resume();
            break;
        default:
            break;
    }
    ui_update();
}

static void back_click_handler(ClickRecognizerRef recognizer, void *context) {
    g_state.last_interaction_time = time(NULL);
    switch (g_state.state) {
        case 1:
            g_state.state = 0;
            break;
        case 2:
            state_exit_to_station();
            break;
        case 3:
            state_resume();
            break;
        default:
            window_stack_pop(true);
            break;
    }
    ui_update();
}

static void click_config_provider(void *context) {
    window_single_click_subscribe(BUTTON_ID_UP, up_click_handler);
    window_single_click_subscribe(BUTTON_ID_DOWN, down_click_handler);
    window_single_click_subscribe(BUTTON_ID_SELECT, select_click_handler);
    window_single_click_subscribe(BUTTON_ID_BACK, back_click_handler);
}

// Window handlers
static void window_load(Window *window) {
    g_state.last_interaction_time = time(NULL);
    ui_init(window);
    messaging_init();

    // Request initial station data
    messaging_request_stations();

    // Start tick timer
    s_tick_timer = app_timer_register(NORMAL_TICK_INTERVAL, tick_handler, NULL);
}

static void window_unload(Window *window) {
    if (s_tick_timer) app_timer_cancel(s_tick_timer);
    messaging_deinit();
    ui_deinit();
}

// Main
int main(void) {
    state_init();

    s_main_window = window_create();
    window_set_background_color(s_main_window, GColorBlack);
    window_set_click_config_provider(s_main_window, click_config_provider);
    window_set_window_handlers(s_main_window, (WindowHandlers) {
        .load = window_load,
        .unload = window_unload,
    });

    window_stack_push(s_main_window, true);
    app_event_loop();
    window_destroy(s_main_window);
}
