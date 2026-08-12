#ifndef RF_RENDER_TELEMETRY_H
#define RF_RENDER_TELEMETRY_H

#include <stdint.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <mach/mach_time.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Lightweight realtime render telemetry.
 *
 * The audio callback only performs:
 *   - mach_continuous_time()
 *   - relaxed atomic operations
 *
 * Logging and interpretation happen elsewhere, off the realtime thread.
 */

typedef struct {
    _Atomic uint64_t callback_count;
    _Atomic uint64_t previous_start_ticks;
    _Atomic uint64_t max_gap_ticks;
    _Atomic uint64_t max_duration_ticks;
} RFRenderTelemetry;


/* Store a new maximum without taking a lock. */
static inline void rf_render_atomic_max(
    _Atomic uint64_t *target,
    uint64_t value
) {
    uint64_t current =
        atomic_load_explicit(target, memory_order_relaxed);

    while (
        value > current &&
        !atomic_compare_exchange_weak_explicit(
            target,
            &current,
            value,
            memory_order_relaxed,
            memory_order_relaxed
        )
    ) {
        /* current is refreshed automatically on failed comparison */
    }
}


/* Allocate the telemetry state outside the realtime callback. */
static inline void *rf_render_telemetry_create(void) {
    return calloc(1, sizeof(RFRenderTelemetry));
}


static inline void rf_render_telemetry_destroy(void *opaque) {
    free(opaque);
}


/*
 * Mark the beginning of a render callback.
 *
 * Returns the timestamp so the caller can pass it to
 * rf_render_telemetry_end().
 */
static inline uint64_t rf_render_telemetry_begin(void *opaque) {
    RFRenderTelemetry *telemetry = (RFRenderTelemetry *)opaque;
    if (telemetry == NULL) {
        return 0;
    }

    const uint64_t now = mach_continuous_time();

    atomic_fetch_add_explicit(
        &telemetry->callback_count,
        1,
        memory_order_relaxed
    );

    const uint64_t previous =
        atomic_exchange_explicit(
            &telemetry->previous_start_ticks,
            now,
            memory_order_relaxed
        );

    if (previous != 0 && now > previous) {
        rf_render_atomic_max(
            &telemetry->max_gap_ticks,
            now - previous
        );
    }

    return now;
}


/* Mark completion of the render callback. */
static inline void rf_render_telemetry_end(
    void *opaque,
    uint64_t start_ticks
) {
    RFRenderTelemetry *telemetry = (RFRenderTelemetry *)opaque;
    if (telemetry == NULL || start_ticks == 0) {
        return;
    }

    const uint64_t end = mach_continuous_time();

    if (end > start_ticks) {
        rf_render_atomic_max(
            &telemetry->max_duration_ticks,
            end - start_ticks
        );
    }
}


/*
 * Read the current interval's statistics and reset them.
 *
 * previous_start_ticks is deliberately NOT reset so that a long gap
 * spanning two telemetry intervals is still detected.
 */
static inline void rf_render_telemetry_snapshot(
    void *opaque,
    uint64_t *callback_count,
    uint64_t *max_gap_ticks,
    uint64_t *max_duration_ticks
) {
    RFRenderTelemetry *telemetry = (RFRenderTelemetry *)opaque;

    if (telemetry == NULL) {
        *callback_count = 0;
        *max_gap_ticks = 0;
        *max_duration_ticks = 0;
        return;
    }

    *callback_count =
        atomic_exchange_explicit(
            &telemetry->callback_count,
            0,
            memory_order_relaxed
        );

    *max_gap_ticks =
        atomic_exchange_explicit(
            &telemetry->max_gap_ticks,
            0,
            memory_order_relaxed
        );

    *max_duration_ticks =
        atomic_exchange_explicit(
            &telemetry->max_duration_ticks,
            0,
            memory_order_relaxed
        );
}


/* Convert Mach clock ticks to milliseconds off the realtime thread. */
static inline double rf_render_ticks_to_ms(uint64_t ticks) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);

    const double nanoseconds =
        (double)ticks *
        (double)timebase.numer /
        (double)timebase.denom;

    return nanoseconds / 1000000.0;
}

#ifdef __cplusplus
}
#endif

#endif /* RF_RENDER_TELEMETRY_H */