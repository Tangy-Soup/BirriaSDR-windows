/* SPDX-License-Identifier: MIT */
/* Windows link satisfaction only, never executed. mt7921_capture.c's static
 * validate() (referenced from the chip ops table) calls into the tune and
 * gain modules, which this injected-I/O test deliberately does not compile;
 * PE ld cannot section-GC the grouped .text$ section the way GNU ELF can.
 * Fail loudly if any path ever reaches these.
 */
#include "chips/mt7921.h"
#include <stdlib.h>

bool mt_frequency_supported(uint64_t frequency_hz)
{
    (void)frequency_hz;
    abort();
}

int mt_validate_gain(uint64_t frequency, unsigned chain, const struct birriasdr_gain *gain)
{
    (void)frequency;
    (void)chain;
    (void)gain;
    abort();
}
