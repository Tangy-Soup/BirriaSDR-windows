/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Luigi C.
 */
#ifndef BIRRIASDR_USB_STREAM_H
#define BIRRIASDR_USB_STREAM_H
#include "internal.h"
#define BS_USB_BYTES 65536u
#include <stdlib.h>

/* Host bulk-IN read size per transfer. The default 64 KiB keeps 192 transfers
 * inside Linux usbfs budgets; BIRRIASDR_XFER (Windows diagnostic, 64..256 KiB,
 * multiple of 1024) is the T2-lite arm that pairs large reads with a larger
 * device aggregation code (BIRRIASDR_AGG) to cut the completion rate. Inline in
 * this header: stream.c links without usb_stream.c in the mock tests. */
static inline unsigned bs_usb_xfer_bytes(void)
{
#ifdef _WIN32
    const char *text = getenv("BIRRIASDR_XFER");
    if (text && *text) {
        char *end;
        unsigned long value = strtoul(text, &end, 10);
        if (!*end && value >= BS_USB_BYTES && value <= 4 * BS_USB_BYTES && value % 1024 == 0)
            return (unsigned)value;
    }
#endif
    return BS_USB_BYTES;
}

struct bs_reader;
int bs_reader_create(birriasdr_dev_t *dev, unsigned depth, struct bs_reader **out);
int bs_reader_start(struct bs_reader *reader);
int bs_reader_take(struct bs_reader *reader, uint8_t *data, size_t *length, unsigned timeout_ms);
void bs_reader_destroy(struct bs_reader *reader);
#endif
