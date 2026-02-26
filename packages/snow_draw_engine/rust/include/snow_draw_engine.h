#ifndef SNOW_DRAW_ENGINE_H
#define SNOW_DRAW_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sd_engine sd_engine_t;

typedef struct sd_bytes {
  uint8_t* ptr;
  size_t len;
} sd_bytes_t;

enum {
  SD_STATUS_OK = 0,
  SD_STATUS_NO_EVENT = 1,
  SD_STATUS_NULL_POINTER = 2,
  SD_STATUS_DECODE_ERROR = 3,
  SD_STATUS_ENGINE_ERROR = 4,
  SD_STATUS_PANIC = 255,
};

enum {
  SD_CAP_EVENT_STREAM = 1ull << 0,
  SD_CAP_FRAME_PLAN = 1ull << 1,
  SD_CAP_DISPATCH_BATCH = 1ull << 2,
};

uint32_t sd_engine_abi_version(void);
uint64_t sd_engine_capabilities(void);

sd_engine_t* sd_engine_create(sd_bytes_t config_bytes, uint32_t* out_status, sd_bytes_t* out_error);
void sd_engine_destroy(sd_engine_t* engine);

uint32_t sd_engine_dispatch(sd_engine_t* engine, sd_bytes_t command_bytes, sd_bytes_t* out_error);
uint32_t sd_engine_dispatch_batch(
    sd_engine_t* engine,
    const sd_bytes_t* command_bytes,
    size_t command_count,
    sd_bytes_t* out_error);

uint32_t sd_engine_get_snapshot(sd_engine_t* engine, sd_bytes_t* out_snapshot, sd_bytes_t* out_error);
uint32_t sd_engine_build_frame_plan(
    sd_engine_t* engine,
    sd_bytes_t request_bytes,
    sd_bytes_t* out_plan,
    sd_bytes_t* out_error);
uint32_t sd_engine_poll_event(sd_engine_t* engine, sd_bytes_t* out_event, sd_bytes_t* out_error);

void sd_bytes_free(sd_bytes_t bytes);

#ifdef __cplusplus
}
#endif

#endif  // SNOW_DRAW_ENGINE_H
