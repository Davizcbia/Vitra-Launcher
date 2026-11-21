// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QElapsedTimer>
#include <QtGlobal>
#include <algorithm>

// Total download speed limit ("DownloadSpeedLimit" setting, KiB/s, 0 = off),
// shared by every Net::Request: one token bucket refilled at the limit, with
// at most 250 ms of burst. A request that finds the bucket empty leaves the
// data in its (bounded) reply buffer and reads again shortly, so TCP slows the
// sender instead of anything being dropped. Main thread only, like Request.
namespace Net::DownloadThrottle {

inline constexpr int retryMs = 25;
inline constexpr qint64 replyBufferBytes = 256 * 1024;

struct Bucket {
    QElapsedTimer clock;
    double tokens = 0;
};

inline Bucket& bucket()
{
    static Bucket instance;
    return instance;
}

// How many of `wanted` bytes may be read now at `limitKiB` KiB/s.
inline qint64 take(qint64 wanted, int limitKiB)
{
    auto& b = bucket();
    const double rate = limitKiB * 1024.0;
    if (!b.clock.isValid()) {
        b.clock.start();
        b.tokens = rate * 0.1;
    }
    const double elapsed = b.clock.restart() / 1000.0;
    b.tokens = std::min(b.tokens + elapsed * rate, rate * 0.25);
    const qint64 allowed = std::clamp<qint64>(static_cast<qint64>(b.tokens), 0, wanted);
    b.tokens -= static_cast<double>(allowed);
    return allowed;
}

}  // namespace Net::DownloadThrottle
