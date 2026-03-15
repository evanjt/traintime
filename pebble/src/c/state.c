#include "state.h"
#include "constants.h"
#include <math.h>

AppState g_state;

static char s_walk_buf[32];

void state_init(void) {
    memset(&g_state, 0, sizeof(AppState));
    g_state.state = 0;
    g_state.current_mode = MODE_TRAIN;
    g_state.gps_quality = GPS_UNAVAILABLE;
    strncpy(g_state.status, "GPS: Searching...", sizeof(g_state.status));
}

void state_clear_stations(void) {
    for (int m = 0; m < MODE_COUNT; m++) {
        g_state.station_count[m] = 0;
        for (int i = 0; i < MAX_STATIONS_PER_MODE; i++) {
            g_state.stations[m][i].has_data = false;
        }
    }
    g_state.station_index = 0;
    g_state.departure_count = 0;
    for (int i = 0; i < MODE_COUNT; i++) {
        g_state.mode_available[i] = false;
    }
    g_state.consecutive_errors = 0;
    if (g_state.state == 2) {
        state_exit_to_station();
    }
    strncpy(g_state.status, "Finding stations...", sizeof(g_state.status));
}

void state_rebuild_modes(void) {
    for (int m = 0; m < MODE_COUNT; m++) {
        g_state.mode_available[m] = g_state.station_count[m] > 0;
    }

    // If current mode has no stations, switch to first available
    if (!g_state.mode_available[g_state.current_mode]) {
        for (int m = 0; m < MODE_COUNT; m++) {
            if (g_state.mode_available[m]) {
                g_state.current_mode = (TransportMode)m;
                break;
            }
        }
    }
    g_state.station_index = 0;
}

Station* state_current_station(void) {
    int mode = g_state.current_mode;
    if (g_state.station_count[mode] == 0) return NULL;
    if (g_state.station_index >= g_state.station_count[mode]) return NULL;
    return &g_state.stations[mode][g_state.station_index];
}

void state_select_mode(TransportMode mode) {
    if (!g_state.mode_available[mode]) return;
    g_state.current_mode = mode;
    g_state.station_index = 0;
    g_state.departure_count = 0;
}

void state_cycle_mode(void) {
    int start = g_state.current_mode;
    for (int i = 1; i < MODE_COUNT; i++) {
        int next = (start + i) % MODE_COUNT;
        if (g_state.mode_available[next]) {
            state_select_mode((TransportMode)next);
            return;
        }
    }
}

void state_select_departure(int index) {
    if (index < 0 || index >= g_state.departure_count) return;
    Departure *dep = &g_state.departures[index];
    if (dep->minutes_until < 0) return;

    strncpy(g_state.focused.destination, dep->destination, sizeof(g_state.focused.destination));
    g_state.focused.departure_timestamp = dep->departure_timestamp;
    g_state.focused.delay = dep->delay;
    strncpy(g_state.focused.platform, dep->platform, sizeof(g_state.focused.platform));
    g_state.focused.platform_changed = dep->platform_changed;
    g_state.focused.active = true;

    g_state.state = 2;
    g_state.consecutive_errors = 0;
    g_state.last_vibe_tick = 0;
    g_state.last_fetch_time = 0;

    vibes_short_pulse();
}

void state_enter_inactive(void) {
    g_state.state = 3;
    g_state.focused.active = false;
    g_state.consecutive_errors = 0;
}

void state_resume(void) {
    g_state.state = 0;
}

void state_exit_to_station(void) {
    g_state.state = 0;
    g_state.focused.active = false;
    g_state.consecutive_errors = 0;
}

int state_walk_minutes(int dist_meters) {
    return (int)(dist_meters / WALK_SPEED);
}

char* state_format_walk_info(int dist_meters) {
    int walk_min = state_walk_minutes(dist_meters);
    if (walk_min < 1) {
        snprintf(s_walk_buf, sizeof(s_walk_buf), "<1 min walk - %dm", dist_meters);
    } else {
        snprintf(s_walk_buf, sizeof(s_walk_buf), "%d min walk - %dm", walk_min, dist_meters);
    }
    return s_walk_buf;
}

int state_seconds_until(int timestamp) {
    return timestamp - (int)time(NULL);
}

double state_minutes_until_f(int timestamp) {
    return (double)state_seconds_until(timestamp) / 60.0;
}
