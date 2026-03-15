#pragma once

#include <pebble.h>

void messaging_init(void);
void messaging_deinit(void);
void messaging_request_stations(void);
void messaging_request_departures(const char *station_id);
