#include "messaging.h"
#include "state.h"
#include "ui.h"
#include "constants.h"

static int s_pending_dep_count = 0;
static int s_pending_dep_received = 0;

static void inbox_received_handler(DictionaryIterator *iter, void *context) {
    Tuple *cmd_tuple = dict_find(iter, MESSAGE_KEY_CMD);
    if (!cmd_tuple) return;

    int cmd = cmd_tuple->value->int32;

    switch (cmd) {
        case CMD_STATIONS_READY: {
            // Station data
            Tuple *name_t = dict_find(iter, MESSAGE_KEY_STATION_NAME);
            Tuple *id_t = dict_find(iter, MESSAGE_KEY_STATION_ID);
            Tuple *dist_t = dict_find(iter, MESSAGE_KEY_STATION_DIST);
            Tuple *mode_t = dict_find(iter, MESSAGE_KEY_STATION_MODE);

            if (name_t && id_t && mode_t) {
                int mode = mode_t->value->int32;
                if (mode >= 0 && mode < MODE_COUNT) {
                    int idx = g_state.station_count[mode];
                    if (idx < MAX_STATIONS_PER_MODE) {
                        Station *s = &g_state.stations[mode][idx];
                        strncpy(s->id, id_t->value->cstring, sizeof(s->id));
                        strncpy(s->name, name_t->value->cstring, sizeof(s->name));
                        s->dist = dist_t ? dist_t->value->int32 : 0;
                        s->has_data = true;
                        g_state.station_count[mode]++;
                    }
                }
                state_rebuild_modes();

                // Auto-request departures for first station if we're in state 0
                if (g_state.state == 0) {
                    Station *current = state_current_station();
                    if (current && g_state.departure_count == 0) {
                        messaging_request_departures(current->id);
                    }
                }
            }
            break;
        }

        case CMD_DEPARTURE: {
            Tuple *dest_t = dict_find(iter, MESSAGE_KEY_DEP_DESTINATION);
            Tuple *mins_t = dict_find(iter, MESSAGE_KEY_DEP_MINUTES);
            Tuple *ts_t = dict_find(iter, MESSAGE_KEY_DEP_TIMESTAMP);
            Tuple *delay_t = dict_find(iter, MESSAGE_KEY_DEP_DELAY);
            Tuple *plat_t = dict_find(iter, MESSAGE_KEY_DEP_PLATFORM);
            Tuple *pc_t = dict_find(iter, MESSAGE_KEY_DEP_PLATFORM_CHANGED);
            Tuple *line_t = dict_find(iter, MESSAGE_KEY_DEP_LINE_NUMBER);
            Tuple *idx_t = dict_find(iter, MESSAGE_KEY_DEP_INDEX);
            Tuple *count_t = dict_find(iter, MESSAGE_KEY_DEP_COUNT);

            if (dest_t && idx_t) {
                int idx = idx_t->value->int32;
                if (count_t) s_pending_dep_count = count_t->value->int32;

                if (idx >= 0 && idx < MAX_DEPARTURES) {
                    Departure *dep = &g_state.departures[idx];
                    strncpy(dep->destination, dest_t->value->cstring, sizeof(dep->destination));
                    dep->minutes_until = mins_t ? mins_t->value->int32 : -1;
                    dep->departure_timestamp = ts_t ? ts_t->value->int32 : 0;
                    dep->delay = delay_t ? delay_t->value->int32 : 0;
                    strncpy(dep->platform, plat_t ? plat_t->value->cstring : "", sizeof(dep->platform));
                    dep->platform_changed = pc_t ? pc_t->value->int32 != 0 : false;
                    strncpy(dep->line_number, line_t ? line_t->value->cstring : "", sizeof(dep->line_number));
                    dep->has_data = true;
                    s_pending_dep_received++;
                }
            }
            break;
        }

        case CMD_DEPARTURES_DONE: {
            g_state.departure_count = s_pending_dep_received < s_pending_dep_count ?
                s_pending_dep_received : s_pending_dep_count;
            g_state.last_fetch_time = time(NULL);
            g_state.consecutive_errors = 0;
            s_pending_dep_received = 0;

            // Update focused train in state 2
            if (g_state.state == 2 && g_state.focused.active) {
                bool found = false;
                for (int i = 0; i < g_state.departure_count; i++) {
                    Departure *dep = &g_state.departures[i];
                    if (strcmp(dep->destination, g_state.focused.destination) == 0 && dep->minutes_until >= -1) {
                        // Update delay and platform
                        if (dep->platform[0] != '\0' && strcmp(dep->platform, g_state.focused.platform) != 0) {
                            if (dep->platform_changed) vibes_double_pulse();
                            strncpy(g_state.focused.platform, dep->platform, sizeof(g_state.focused.platform));
                            g_state.focused.platform_changed = dep->platform_changed;
                        }
                        g_state.focused.delay = dep->delay;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    vibes_short_pulse();
                    state_enter_inactive();
                }
            }
            break;
        }

        case CMD_GPS_UPDATE: {
            Tuple *quality_t = dict_find(iter, MESSAGE_KEY_GPS_QUALITY);
            Tuple *lat_t = dict_find(iter, MESSAGE_KEY_GPS_LAT);
            Tuple *lon_t = dict_find(iter, MESSAGE_KEY_GPS_LON);

            if (quality_t) {
                g_state.gps_quality = (GPSQuality)quality_t->value->int32;
            }

            // Walk distance is computed by JS companion and could be sent separately
            // For now the JS companion sends it with station data
            (void)lat_t;
            (void)lon_t;
            break;
        }

        case CMD_ERROR: {
            Tuple *msg_t = dict_find(iter, MESSAGE_KEY_ERROR_MSG);
            if (msg_t) {
                strncpy(g_state.status, msg_t->value->cstring, sizeof(g_state.status));
            }
            if (g_state.state == 2) {
                g_state.consecutive_errors++;
                if (g_state.consecutive_errors >= CONSECUTIVE_ERROR_LIMIT) {
                    state_exit_to_station();
                    strncpy(g_state.status, "Connection lost", sizeof(g_state.status));
                }
            }
            break;
        }
    }

    ui_update();
}

static void inbox_dropped_handler(AppMessageResult reason, void *context) {
    APP_LOG(APP_LOG_LEVEL_ERROR, "Message dropped: %d", reason);
}

static void outbox_failed_handler(DictionaryIterator *iter, AppMessageResult reason, void *context) {
    APP_LOG(APP_LOG_LEVEL_ERROR, "Outbox failed: %d", reason);
}

void messaging_init(void) {
    app_message_register_inbox_received(inbox_received_handler);
    app_message_register_inbox_dropped(inbox_dropped_handler);
    app_message_register_outbox_failed(outbox_failed_handler);

    const int inbox_size = 512;
    const int outbox_size = 256;
    app_message_open(inbox_size, outbox_size);
}

void messaging_deinit(void) {
    app_message_deregister_callbacks();
}

void messaging_request_stations(void) {
    DictionaryIterator *iter;
    if (app_message_outbox_begin(&iter) != APP_MSG_OK) return;

    dict_write_int32(iter, MESSAGE_KEY_CMD, CMD_REQUEST_STATIONS);
    app_message_outbox_send();
}

void messaging_request_departures(const char *station_id) {
    DictionaryIterator *iter;
    if (app_message_outbox_begin(&iter) != APP_MSG_OK) return;

    dict_write_int32(iter, MESSAGE_KEY_CMD, CMD_FETCH_DEPARTURES);
    dict_write_cstring(iter, MESSAGE_KEY_FETCH_STATION_ID, station_id);

    s_pending_dep_count = 0;
    s_pending_dep_received = 0;
    for (int i = 0; i < MAX_DEPARTURES; i++) {
        g_state.departures[i].has_data = false;
    }

    app_message_outbox_send();
}
