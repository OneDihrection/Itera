//
//  LongRestWaves.metal
//  Itera
//
//  Created by dimaswisodewo on 12/11/2026.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// The lower edge of one wave band, in points from the top.
///
/// `expansion` (0 at rest, 1 at a full breath) drives the breath three ways so it reads clearly:
/// bands lift by 20%, 16% and 12% of the height (back to front), so they fan apart on inhale
/// and settle together on exhale; and the crest swells from 5% to 10% of the height at the
/// centre. A slow sine sway keeps the crest moving between breath samples.
static float waveEdge(float2 position, float2 size, float time, float expansion, int index) {
    const float liftFractions[3] = { 0.20, 0.16, 0.12 };

    float x = position.x / max(size.x, 1.0);
    float base = size.y * (0.28 + float(index) * 0.23);
    float lift = expansion * size.y * liftFractions[index];

    // A quad curve whose control point sits `crestControl` above the edge peaks at half of it.
    float crestControl = size.y * (0.10 + 0.10 * expansion);
    float crest = 2.0 * x * (1.0 - x) * crestControl;

    float spatial = 0.8 + 0.2 * float(index);
    float speed = 0.45 + 0.1 * float(index);
    float phase = 1.7 * float(index);
    float sway = sin(x * 2.0 * M_PI_F * spatial + time * speed + phase) * size.y * 0.012;

    return base - lift - crest + sway;
}

/// Three rust wave bands over a dark rust base, composited back to front with soft edges.
/// Bands brighten slightly toward white as they expand. The source colour is ignored; the
/// bands cover the whole layer.
[[ stitchable ]] half4 longRestWaves(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float expansion,
    half4 base,
    half4 band0,
    half4 band1,
    half4 band2
) {
    // About one and a half points of feathering keeps edges smooth without looking blurred.
    const float feather = 1.5;
    const half brightening = 0.10;

    half4 bands[3] = { band0, band1, band2 };
    half4 result = base;

    for (int index = 0; index < 3; index++) {
        float edge = waveEdge(position, size, time, expansion, index);
        float coverage = smoothstep(edge - feather, edge + feather, position.y);
        half4 band = mix(bands[index], half4(1.0), brightening * half(expansion));
        result = mix(result, band, half(coverage));
    }

    return result;
}
