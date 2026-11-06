#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// MovieMatch, ported from the public Shaders component contract:
// a white beam in an aspect-corrected frame, a smooth-relu elbow at the
// split, then a hue-cycling rainbow that fans out with distance.
// Composite is additive over the view's dark fill (the "dark layer").

static float smoothRelu(float x, float softness) {
    float s = max(softness, 1e-4);
    float y = x / s;
    float sp = (y > 0.0) ? (y + log(1.0 + exp(-y))) : log(1.0 + exp(y));
    return sp * s;
}

static float ign(float2 p) {
    float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(p, magic.xy)));
}

static float3 cyclicRainbow(float hue, float saturation) {
    float3 k = float3(0.0, 2.0 / 3.0, 1.0 / 3.0);
    float3 rgb = saturate(abs(fract(hue + k) * 6.0 - 3.0) - 1.0);
    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb *= 0.62 / max(luma, 0.14);
    float y = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    return mix(float3(y), rgb, saturation);
}

[[ stitchable ]] half4 movieMatch(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float4 endpoints,
    float4 shape,
    float4 look,
    float4 beamTint
) {
    float2 source = endpoints.xy;
    float2 split = endpoints.zw;
    float beamWidth = shape.x;
    float intensity = shape.y;
    float startFalloff = shape.z;
    float endFalloff = shape.w;
    float spread = look.x;
    float softness = look.y;
    float saturation = look.z;
    float speed = look.w;
    float3 beamColor = beamTint.rgb;

    float aspect = size.x / max(size.y, 1.0);
    float2 uv = float2(position.x / max(size.x, 1.0), 1.0 - position.y / max(size.y, 1.0));
    float2 src = float2(source.x * aspect, 1.0 - source.y);
    float2 spl = float2(split.x * aspect, 1.0 - split.y);
    float2 p = float2(uv.x * aspect, uv.y);

    float2 axisDelta = spl - src;
    float splitDistance = length(axisDelta);
    float2 axis = axisDelta / max(splitDistance, 1e-4);
    float2 side = float2(-axis.y, axis.x);

    float2 rel = p - src;
    float along = dot(rel, axis);
    float lateral = dot(rel, side);
    float opened = smoothRelu(along - splitDistance, softness);

    float startMask = 1.0 - exp(-max(along, 0.0) / max(startFalloff, 1e-3));
    float endMask = exp(-endFalloff * max(along, 0.0));
    float forward = smoothstep(-0.02, 0.02, along);
    float mask = startMask * endMask * forward;

    constexpr int kBands = 32;
    float sigma = max(beamWidth, 1e-3) * 0.55;
    float invCore = 1.0 / (sigma * sigma);
    float splitMix = 1.0 - exp(-opened / max(softness, 1e-3));

    float3 spectralNum = float3(0.0);
    float spectralCover = 0.0;
    for (int i = 0; i < kBands; ++i) {
        float spatial = (float(i) + 0.5) / float(kBands);
        float hue = fract(spatial + time * speed);
        float shift = (spatial - 0.5) * spread * opened;
        float d = lateral - shift;
        float d2 = d * d;
        float profile = exp(-0.5 * d2 * invCore) + exp(-0.5 * d2 * invCore * 0.2) * 0.1;
        spectralNum += cyclicRainbow(hue, saturation) * profile;
        spectralCover += profile;
    }

    float3 spectralHue = spectralNum / max(spectralCover, 1e-3);
    float spectralEnergy = 1.0 - exp(-spectralCover * 2.4);
    float3 spectralLit = spectralHue * spectralEnergy * intensity;

    float whiteEnergy = exp(-0.5 * lateral * lateral * invCore);
    float3 whiteLit = beamColor * whiteEnergy * intensity;
    float3 light = mix(whiteLit, spectralLit, splitMix) * mask;

    float peak = max(light.r, max(light.g, light.b));
    float3 chroma = light / max(peak, 1e-4);
    float head = peak < 1.0 ? peak : 1.0 + (1.0 - exp(-(peak - 1.0))) * 0.4;
    float blow = smoothstep(1.2, 2.6, peak);
    float3 mapped = mix(chroma, float3(1.0), blow) * head;
    mapped = saturate(mapped + (ign(position) - 0.5) / 255.0);

    float luma = dot(mapped, float3(0.2126, 0.7152, 0.0722));
    float cover = saturate(luma * 1.25);
    float3 background = float3(color.rgb);
    float3 outRgb = mapped + background * (1.0 - cover);
    return half4(half3(outRgb), 1.0);
}
