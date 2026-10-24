//
//  Walk.metal
//  Hasher
//
//  GPU walkers for the distinguished-point search. Each thread is one walker that steps
//  x -> first `bits` bits of SHA-256(salt || x), exactly like HashStep on the CPU.
//

#include <metal_stdlib>
using namespace metal;

// Buffer layouts, all in 32-bit words (points are 8 big-endian words, like Point's 4 UInt64s):
//   params: salt[0..3], bits, dpBits, steps, outputCapacity, maxTrailLength lo, hi
//   trail:  start[0..7], current[8..15], length lo/hi [16..17], rng lo/hi [18..19]
//   record: point[0..7], start[8..15], length lo/hi [16..17]
constant uint kTrailWords = 20;
constant uint kRecordWords = 18;

constant uint K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

constant uint IV[8] = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
};

static inline uint rotr(uint x, uint n) {
    return rotate(x, 32 - n);
}

/// SHA-256 of the 48-byte message salt (16 bytes) || x (32 bytes): one padded block.
static void sha256Salted(constant uint *salt, thread const uint *x, thread uint *h) {
    uint w[64];
    for (uint i = 0; i < 4; i++) w[i] = salt[i];
    for (uint i = 0; i < 8; i++) w[4 + i] = x[i];
    w[12] = 0x80000000;
    w[13] = 0;
    w[14] = 0;
    w[15] = 48 * 8;
    for (uint i = 16; i < 64; i++) {
        uint s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint a = IV[0], b = IV[1], c = IV[2], d = IV[3], e = IV[4], f = IV[5], g = IV[6], hh = IV[7];
    for (uint i = 0; i < 64; i++) {
        uint t1 = hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
        uint t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] = a + IV[0]; h[1] = b + IV[1]; h[2] = c + IV[2]; h[3] = d + IV[3];
    h[4] = e + IV[4]; h[5] = f + IV[5]; h[6] = g + IV[6]; h[7] = hh + IV[7];
}

/// Keeps the first `bits` bits, like Point.masked(toBits:).
static void maskToBits(thread uint *x, uint bits) {
    for (uint i = 0; i < 8; i++) {
        int kept = clamp(int(bits) - int(32 * i), 0, 32);
        x[i] &= kept == 0 ? 0u : (kept == 32 ? 0xffffffffu : ~0u << (32 - kept));
    }
}

static inline ulong splitmix64(thread ulong &state) {
    state += 0x9E3779B97F4A7C15ul;
    ulong z = state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ul;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBul;
    return z ^ (z >> 31);
}

static void restartTrail(thread uint *start, thread uint *current, thread ulong &length, thread ulong &rng, uint bits) {
    for (uint i = 0; i < 4; i++) {
        ulong r = splitmix64(rng);
        start[2 * i] = uint(r >> 32);
        start[2 * i + 1] = uint(r);
    }
    maskToBits(start, bits);
    for (uint i = 0; i < 8; i++) current[i] = start[i];
    length = 0;
}

kernel void walk(device uint *trails [[buffer(0)]],
                 device uint *records [[buffer(1)]],
                 device atomic_uint *recordCount [[buffer(2)]],
                 constant uint *params [[buffer(3)]],
                 uint tid [[thread_position_in_grid]]) {
    const uint bits = params[4], dpBits = params[5], steps = params[6], capacity = params[7];
    const ulong maxLength = ulong(params[8]) | (ulong(params[9]) << 32);

    device uint *trail = trails + tid * kTrailWords;
    uint start[8], current[8];
    for (uint i = 0; i < 8; i++) {
        start[i] = trail[i];
        current[i] = trail[8 + i];
    }
    ulong length = ulong(trail[16]) | (ulong(trail[17]) << 32);
    ulong rng = ulong(trail[18]) | (ulong(trail[19]) << 32);

    for (uint s = 0; s < steps; s++) {
        uint next[8];
        sha256Salted(params, current, next);
        maskToBits(next, bits);
        length++;
        bool distinguished = dpBits == 0 || (next[0] >> (32 - dpBits)) == 0;
        if (distinguished) {
            uint slot = atomic_fetch_add_explicit(recordCount, 1, memory_order_relaxed);
            if (slot < capacity) {
                device uint *record = records + slot * kRecordWords;
                for (uint i = 0; i < 8; i++) {
                    record[i] = next[i];
                    record[8 + i] = start[i];
                }
                record[16] = uint(length);
                record[17] = uint(length >> 32);
            }
            restartTrail(start, current, length, rng, bits);
        } else if (length >= maxLength) {
            restartTrail(start, current, length, rng, bits);
        } else {
            for (uint i = 0; i < 8; i++) current[i] = next[i];
        }
    }

    for (uint i = 0; i < 8; i++) {
        trail[i] = start[i];
        trail[8 + i] = current[i];
    }
    trail[16] = uint(length);
    trail[17] = uint(length >> 32);
    trail[18] = uint(rng);
    trail[19] = uint(rng >> 32);
}

/// One step for each input point; used by tests to check the GPU matches HashStep exactly.
kernel void hashPoints(device const uint *input [[buffer(0)]],
                       device uint *output [[buffer(1)]],
                       constant uint *params [[buffer(2)]],
                       uint tid [[thread_position_in_grid]]) {
    uint x[8], h[8];
    for (uint i = 0; i < 8; i++) x[i] = input[tid * 8 + i];
    sha256Salted(params, x, h);
    maskToBits(h, params[4]);
    for (uint i = 0; i < 8; i++) output[tid * 8 + i] = h[i];
}
