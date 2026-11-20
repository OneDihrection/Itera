//
//  CompletionPulse.metal
//  Tuntun
//
//  Created by dimaswisodewo on 20/11/2026.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// Places premultiplied `top` over premultiplied `bottom`.
static half4 over(half4 bottom, half4 top) {
    return top + bottom * (1.0h - top.a);
}

/// Premultiplies an opaque colour by `alpha`.
static half4 tinted(half3 color, float alpha) {
    half a = half(saturate(alpha));
    return half4(color * a, a);
}

/// One glow wave at local time `t` (0 → 1): a soft ring that leaves the circle's edge, travels
/// `spread` points outward, widens and fades. Returns its alpha at `distance` from the centre.
static float beat(float distance, float t, float radius, float spread, float ringWidth) {
    if (t <= 0.0 || t >= 1.0) {
        return 0.0;
    }

    // Ease out, so the wave leaves quickly and settles.
    float travel = 1.0 - (1.0 - t) * (1.0 - t);
    float center = radius + spread * travel;
    float width = ringWidth * mix(0.6, 1.6, travel);
    float offset = (distance - center) / max(width, 0.5);

    // A short attack, so the glow swells in instead of appearing at full strength.
    float attack = smoothstep(0.0, 0.12, t);
    float fade = (1.0 - t) * (1.0 - t);

    return exp(-offset * offset) * attack * fade;
}

/// A hold-completion pulse around a guide circle, centred in the layer: a soft glow in `tint`
/// swells out from the circle's edge twice, like a heartbeat, the second beat weaker and
/// overlapping the first. `radius` and `ringWidth` match the drawn circle and its outline;
/// `progress` runs 0 → 1 over the whole pulse. With `reduceMotion` at 1 only one short-travel beat
/// plays. During the first beat the outline itself brightens toward white, so the circle throbs.
/// The source colour is ignored; elsewhere the layer is transparent.
[[ stitchable ]] half4 completionPulse(
    float2 position,
    half4 color,
    float2 size,
    float radius,
    float ringWidth,
    float progress,
    float reduceMotion,
    half4 tint
) {
    const float secondStrength = 0.6;
    const float flashStrength = 0.5;
    const float whitening = 0.15;

    float distance = length(position - size * 0.5);
    float spread = radius * mix(0.35, 0.08, reduceMotion);

    // The first beat covers 0…0.6 of the pulse, the second 0.35…1; Reduce Motion stretches the
    // first over the whole pulse and drops the second.
    float firstT = reduceMotion > 0.5 ? progress : progress / 0.6;
    float secondT = (progress - 0.35) / 0.65;

    float first = beat(distance, firstT, radius, spread, ringWidth);
    float second = reduceMotion > 0.5
        ? 0.0
        : beat(distance, secondT, radius, spread * 0.7, ringWidth) * secondStrength;

    // The flash sits on the outline and fades with the first beat.
    float flashOffset = (distance - radius) / max(ringWidth * 0.6, 0.5);
    float flashT = saturate(firstT);
    float flash = exp(-flashOffset * flashOffset)
        * smoothstep(0.0, 0.1, flashT)
        * (1.0 - flashT)
        * flashStrength;

    half3 glow = tint.rgb;
    half3 bright = mix(tint.rgb, half3(1.0h), half(whitening));

    half4 result = half4(0.0h);
    result = over(result, tinted(glow, max(first, second)));
    result = over(result, tinted(bright, flash));
    return result;
}
