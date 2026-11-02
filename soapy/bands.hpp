/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Luigi C.
 * Tuning bands for the SoapySDR module, kept apart from SoapySDR so the band
 * walk and the gap check can be tested without a device.
 */
#pragma once

#include "birriasdr.h"
#include <cmath>
#include <cstdint>
#include <vector>

namespace birria_soapy {

struct Band { uint64_t minimum, maximum; };

/* Every band the library reports, in ascending order. get(index, &min, &max)
 * follows birriasdr_get_tuning_band(): INVALID ends the list, and a band this
 * board cannot reach (UNSUPPORTED) is skipped. Any other error ends the walk
 * with the bands found so far. The cap guards against a backend that never
 * returns INVALID.
 */
template <typename Get> std::vector<Band> collect_bands(Get get)
{
    std::vector<Band> bands;
    for (uint32_t index = 0; index < 64; ++index) {
        Band band{};
        int result = get(index, &band.minimum, &band.maximum);
        if (result == BIRRIASDR_ERROR_UNSUPPORTED)
            continue;
        if (result < 0)
            break;
        bands.push_back(band);
    }
    return bands;
}

/* The single band spanning every listed band, for hosts that clamp to one
 * interval (SDRangel's frequency dial asks for a single range and would never
 * leave the first band otherwise). {0, 0} when there is no band; callers
 * check for that first. Ascending order is collect_bands()'s contract; the
 * scan keeps the answer right even if a backend breaks it.
 */
inline Band spanning_band(const std::vector<Band> &bands)
{
    Band span{0, 0};
    for (const Band &band : bands) {
        if (span.minimum == 0 || band.minimum < span.minimum)
            span.minimum = band.minimum;
        if (band.maximum > span.maximum)
            span.maximum = band.maximum;
    }
    return span;
}

/* The request rounded to whole hertz if it lies inside a band, else 0.
 * Anything above 1 PHz is rejected before rounding, so llround cannot overflow.
 */
inline uint64_t in_band(const std::vector<Band> &bands, double frequency)
{
    if (!(frequency > 0) || frequency > 1e15)
        return 0;
    uint64_t hz = (uint64_t)std::llround(frequency);
    for (const Band &band : bands)
        if (hz >= band.minimum && hz <= band.maximum)
            return hz;
    return 0;
}

}  // namespace birria_soapy
