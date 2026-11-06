#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Seams 3, from the unlocked preset:
// hidden MeshGradient (red→green, seed 38) drives DisplacementMap,
// CurlNoise (cyan→navy→black, seed 57) is the picture,
// then Glow (32px, 1.5, threshold 0.06) and ACES.

static uint bits(float x) { return as_type<uint>(x); }

static float hash11(float p) {
    uint u = bits(p * 3141592653.0);
    return float(u * u * 3141592653u) / 4294967296.0;
}

static float2 hash22(float2 p) {
    uint2 u = uint2(bits(p.x * 141421356.0), bits(p.y * 2718281828.0));
    uint h = u.x ^ u.y;
    return float2(float(h * 3141592653u), float(h * 1618033988u)) / 4294967296.0;
}

static float3 hash33(float3 p) {
    uint3 u = uint3(
        bits(p.x * 141421356.0),
        bits(p.y * 2718281828.0),
        bits(p.z * 1618033988.0)
    );
    uint h = u.x ^ u.y ^ u.z;
    return float3(
        float(h * 1732050807u),
        float(h * 2645751311u),
        float(h * 3316624790u)
    ) / 4294967296.0;
}

static float4 perm4(float4 x) {
    float4 xx = x * (x * 34.0 + 1.0);
    return xx - floor(xx / 289.0) * 289.0;
}

static float value13(float3 p) {
    float3 a = floor(p);
    float3 d0 = p - a;
    float3 sd = d0 * d0 * (3.0 - d0 * 2.0);
    float4 b = float4(a.x, a.x, a.y, a.y) + float4(0.0, 1.0, 0.0, 1.0);
    float4 k1 = perm4(float4(b.x, b.y, b.x, b.y));
    float4 k2 = perm4(float4(k1.x, k1.y, k1.x, k1.y) + float4(b.z, b.z, b.w, b.w)) + float4(a.z);
    float4 k3 = perm4(k2);
    float4 k4 = perm4(k2 + 1.0);
    float4 o1 = fract(k3 * 0.02439024);
    float4 o2 = fract(k4 * 0.02439024);
    float4 o3 = mix(o1, o2, sd.z);
    float2 o4 = mix(float2(o3.x, o3.z), float2(o3.y, o3.w), sd.x);
    return mix(o4.x, o4.y, sd.y);
}

static float2 curl22z(float2 p, float z) {
    float2 pax = p + float2(0.1, 0.0);
    float2 pay = p + float2(0.0, 0.1);
    float2 pbx = p - float2(0.1, 0.0);
    float2 pby = p - float2(0.0, 0.1);
    float2 a = float2(value13(float3(pax, z)), value13(float3(pay, z)));
    float2 b = float2(value13(float3(pbx, z)), value13(float3(pby, z)));
    return (a - b) / 0.1 * 0.5;
}

static float signedNoise(float3 p) {
    return value13(p) * 2.0 - 1.0;
}

static float2 spiralAnchor(float fi, float count, float seed, float drift, float aspect, float animTime) {
    const float golden = 2.39996322972865332;
    const float tau = 6.283185307179586;
    float theta = fi * golden + hash11(seed * 0.7311 + 1.618) * tau;
    float r = sqrt((fi + 0.5) / count);
    float2 j = (hash22(float2(fi * 3.77 + 0.917, seed * 1.093 + 2.236)) - 0.5) * 0.26;
    float2 ph = hash22(float2(fi * 7.13 + 1.618, seed * 0.531 + 3.71)) * tau;
    float w1 = 0.5 + hash11(fi * 5.417 + seed * 0.291 + 0.917) * 0.7;
    float tw = animTime * 0.11 * w1;
    float dx = sin(tw + ph.x);
    float dy = cos(tw * 1.37 + ph.y);
    float nx = cos(theta) * r * 0.62 + j.x + dx * drift * 0.16;
    float ny = sin(theta) * r * 0.62 + j.y + dy * drift * 0.16;
    return float2((0.5 + nx) * aspect, 0.5 + ny);
}

static float scatterField(float2 q, float count, float seed, float drift, float aspect, float animTime, float power) {
    float num = 0.0;
    float den = 0.0;
    float shuffle = hash11(seed * 0.531 + 0.77);
    for (int i = 0; i < 2; ++i) {
        float fi = float(i);
        float active = fi < count - 0.5 ? 1.0 : 0.0;
        float2 anchor = spiralAnchor(fi, count, seed, drift, aspect, animTime);
        float dist = max(length(q - anchor), 0.01);
        float w = active / pow(dist, power);
        float ti = fract(fi * 0.6180339887 + shuffle);
        num += w * ti;
        den += w;
    }
    return num / max(den, 0.000001);
}

static float3 srgbToLinear(float3 c) {
    float3 lo = c / 12.92;
    float3 hi = pow((c + 0.055) / 1.055, float3(2.4));
    return float3(
        c.r <= 0.04045 ? lo.r : hi.r,
        c.g <= 0.04045 ? lo.g : hi.g,
        c.b <= 0.04045 ? lo.b : hi.b
    );
}

static float3 linearToSrgb(float3 c) {
    float3 lo = c * 12.92;
    float3 hi = pow(max(c, float3(0.0)), float3(0.41666)) * 1.055 - 0.055;
    return float3(
        c.r <= 0.0031308 ? lo.r : hi.r,
        c.g <= 0.0031308 ? lo.g : hi.g,
        c.b <= 0.0031308 ? lo.b : hi.b
    );
}

static float3 linearToOklab(float3 c) {
    float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
    float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
    float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
    float l_ = pow(max(l, 0.0), 1.0 / 3.0);
    float m_ = pow(max(m, 0.0), 1.0 / 3.0);
    float s_ = pow(max(s, 0.0), 1.0 / 3.0);
    return float3(
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    );
}

static float3 oklabToLinear(float3 c) {
    float l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    float l = l_ * l_ * l_;
    float m = m_ * m_ * m_;
    float s = s_ * s_ * s_;
    return float3(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    );
}

static float3 oklabRamp(float t, float3 a, float3 b) {
    return oklabToLinear(mix(linearToOklab(a), linearToOklab(b), saturate(t)));
}

static float3 oklabStops3(float t, float3 c0, float p1, float3 c1, float3 c2) {
    float u = saturate(t);
    if (u < p1) {
        return oklabRamp(u / max(p1, 1e-4), c0, c1);
    }
    return oklabRamp((u - p1) / max(1.0 - p1, 1e-4), c1, c2);
}

static float wrapRamp(float t, float cycles) {
    float s = t * cycles;
    float m = fract(s * 0.5) * 2.0;
    float band = 1.0 - abs(m - 1.0);
    float fp = fwidth(t) * cycles;
    return mix(band, 0.5, smoothstep(0.5, 1.5, fp));
}

static float3 acesFit(float3 v) {
    float3 a = v * (v + 0.0245786) - 0.000090537;
    float3 b = v * (v + 0.4329510) * 0.983729 + 0.238081;
    return a / b;
}

static float3 aces(float3 color) {
    float3x3 inputMat = float3x3(
        float3(0.59719, 0.07600, 0.02840),
        float3(0.35458, 0.90834, 0.13383),
        float3(0.04823, 0.01566, 0.83777)
    );
    float3x3 outputMat = float3x3(
        float3(1.60475, -0.10208, -0.00327),
        float3(-0.53108, 1.10813, -0.07276),
        float3(-0.07367, -0.00605, 1.07602)
    );
    float3 c = inputMat * (color / 0.6);
    c = acesFit(c);
    c = outputMat * c;
    return saturate(c);
}

static float mirror1(float x) {
    float y = abs(x);
    float m = fmod(y, 2.0);
    return m > 1.0 ? 2.0 - m : m;
}

static float2 mirrorUV(float2 uv) {
    return float2(mirror1(uv.x), mirror1(uv.y));
}

static float3 meshRGB(float2 uv, float aspect, float time) {
    const float swirl = 0.1;
    const float drift = 0.2;
    const float wrapping = 0.13;
    const float seed = 38.0;
    const float count = 2.0;
    const float variation = 1.0;
    float meshTime = time * 2.0;

    float2 centred = float2(uv.x * aspect - aspect * 0.5, uv.y - 0.5);
    float swirlAngle = -3.0 * swirl * smoothstep(0.0, 1.0, length(centred));
    float cs = cos(swirlAngle);
    float sn = sin(swirlAngle);
    float2 rotated = float2(cs * centred.x - sn * centred.y, sn * centred.x + cs * centred.y);
    float2 uvS = float2(rotated.x + aspect * 0.5, rotated.y + 0.5);

    float3 at = float3(uvS * 1.6, seed * 7.31);
    float warpTime = meshTime * 0.125;
    float qx = signedNoise(at + float3(warpTime * 0.3, -warpTime * 0.2, 0.0));
    float qy = signedNoise(at + float3(5.2, 1.3, warpTime * 0.25));
    float2 q = (at.xy + float2(qx, qy) * 0.48) / 1.6;

    float basePower = 8.0 / 0.5;
    float varNoise = signedNoise(float3(q * 1.9, seed * 3.17 + meshTime * 0.045));
    float power = clamp(basePower * exp(varNoise * variation * 1.4), 0.6, 16.0);
    float field = scatterField(q, count, seed, drift, aspect, meshTime, power);
    float band = wrapRamp(field, 1.0 + wrapping * 9.0);

    float3 red = srgbToLinear(float3(1.0, 0.0, 0.0));
    float3 green = srgbToLinear(float3(0.0, 1.0, 0.0));
    return oklabRamp(band, red, green);
}

static float3 curlLinear(float2 uv, float aspect, float time) {
    float2 pos = float2(uv.x * aspect, uv.y) * exp(-0.7) + 57.0;
    float magnitude = length(curl22z(pos, time * 0.2)) / 1.41421356;
    float k = clamp((magnitude - 0.5) * 2.5 + 0.5, 0.0, 1.0);
    float t = 1.0 - k;
    float3 cyan = srgbToLinear(float3(0.0, 161.0 / 255.0, 1.0));
    float3 navy = srgbToLinear(float3(0.0, 104.0 / 255.0, 184.0 / 255.0));
    float3 black = float3(0.0);
    return oklabStops3(t, cyan, 0.4338, navy, black);
}

static float3 seamsLinear(float2 uv, float aspect, float time) {
    float3 mapColor = meshRGB(uv, aspect, time);
    float dx = (mapColor.r - 0.5) * 2.0 / max(aspect, 1e-4);
    float dy = (mapColor.g - 0.5) * 2.0;
    return curlLinear(mirrorUV(uv + float2(dx, dy)), aspect, time);
}

[[ stitchable ]] half4 seams(float2 position, half4 color, float2 size, float time) {
    float2 screenUV = position / max(size, float2(1.0));
    // The preset is framed on a wide canvas. Show the center of that frame
    // so a tall phone sees the same folds as the landscape preview.
    float bannerAspect = 1.78;
    float viewAspect = size.x / max(size.y, 1.0);
    float span = viewAspect / bannerAspect;
    // The preset's bright fold sits in the upper band of a wide frame.
    // Zoom onto that band so the phone shows the silk, not the empty black below it.
    float2 uv = float2((screenUV.x - 0.5) * span * 0.72 + 0.48, screenUV.y * 0.46 + 0.02);
    float aspect = bannerAspect;

    float3 base = seamsLinear(uv, aspect, time);
    float luma = dot(base, float3(0.2126, 0.7152, 0.0722));
    float3 glow = base * smoothstep(0.06, 0.35, luma);
    float3 lit = aces(base + glow * 0.45);
    return half4(half3(linearToSrgb(lit)), 1.0);
}
