#pragma once
#include <stdint.h>
#if defined(_WIN32)
#define BDK_EXPORT __declspec(dllexport)
#else
#define BDK_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
BDK_EXPORT void* bdk_led_create(void);
BDK_EXPORT void bdk_led_destroy(void* context);
BDK_EXPORT int bdk_led_select(void* context, int effect);
BDK_EXPORT int bdk_led_settings(void* context, const uint8_t* settings, int length);
BDK_EXPORT int bdk_led_render(void* context, const float* audio, uint8_t flags,
                            int demo, uint8_t* rgba, int capacity);
BDK_EXPORT const char* bdk_led_name(int effect);
enum {
    BDK_LED_CORE_FIELD_WIDTH = 256,
    BDK_LED_HALO_FIELD_WIDTH = 128,
    BDK_LED_CORE_FIELD_FLOATS = 256 * 256 * 4,
    BDK_LED_HALO_FIELD_FLOATS = 128 * 128 * 4
};
// Read-only light reconstruction; does not step/configure the source effect.
// Input: exactly 16x16 straight RGBA bytes. The helper normalizes RGB and
// multiplies it by source alpha before reconstructing the field.
// Output: row-major RGBA float32, alpha=1, no gain/clamp/8-bit intermediate.
// Core nodes: -4+i*24/255 on each axis, sigma=.8 source cells.
// Halo nodes: i*16/127 on each axis, finite halo_sigma in [.25,32].
// Source LED centers stay at x+.5/y+.5. Capacities are FLOAT counts, not bytes.
// Returns 1 on success; invalid args or allocation failure return 0. Invalid
// args/capacities are rejected before either output is written.
BDK_EXPORT int bdk_led_light_fields(void* context, const uint8_t* source_rgba,
                                   int source_length, float halo_sigma,
                                   float* core_rgba, int core_capacity_floats,
                                   float* halo_rgba, int halo_capacity_floats);
#ifdef __cplusplus
}
#endif
