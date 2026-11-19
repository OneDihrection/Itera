//
//  BreathingCircle.metal
//  Tuntun
//
//  Created by dimaswisodewo on 19/11/2026.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// A slow angular wobble in -1...1: three low-frequency lobes drifting at different speeds, so
/// the edge breathes organically without ever looking jittery.
static float edgeWobble(float angle, float time) {
    return 0.45 * sin(3.0 * angle + time * 0.60)
         + 0.35 * sin(2.0 * angle - time * 0.42 + 2.1)
         + 0.20 * sin(5.0 * angle + time * 0.33 + 1.3);
}

/// Composites `color` with straight alpha `alpha` over a premultiplied `result`.
static half4 over(half4 result, half3 color, float alpha) {
    half a = half(saturate(alpha));
    return half4(color * a + result.rgb * (1.0h - a), a + result.a * (1.0h - a));
}

/// The short rest's breathing circle: a soft panel fill, a rust ring and a faint halo, centred in
/// the layer. `expansion` (0 at rest, 1 at a full breath) grows the circle from 76% to 100% of its
/// size, raises the ring from 25% to full strength, brightens it slightly and swells the halo.
/// The edge wobbles by about 1–2% of the radius on `time`. The source colour is ignored; outside
/// the halo the layer is transparent. `ring` and `fill` are passed opaque.
[[ stitchable ]] half4 breathingCircle(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float expansion,
    half4 ring,
    half4 fill
) {
    // About one and a half points of feathering, matching the long-rest waves.
    const float feather = 1.5;
    const float fillStrength = 0.35;
    const float ringThickness = 0.36;
    const float haloStrength = 0.30;
    const float brightening = 0.10;

    float2 offset = position - size * 0.5;
    float distance = length(offset);
    float angle = atan2(offset.y, offset.x);

    // Leave the outer 14% of the layer for the halo, so it fades out before the edge.
    float maxRadius = min(size.x, size.y) * 0.5;
    float outer = maxRadius * 0.86 * mix(0.76, 1.0, expansion);
    outer += edgeWobble(angle, time) * outer * (0.010 + 0.008 * expansion);
    float inner = outer * (1.0 - ringThickness);

    float insideOuter = 1.0 - smoothstep(outer - feather, outer + feather, distance);
    float insideInner = 1.0 - smoothstep(inner - feather, inner + feather, distance);

    half4 result = half4(0.0h);

    // Panel fill, slightly lighter toward the centre.
    float fillShade = mix(0.7, 1.0, saturate(distance / max(inner, 1.0)));
    result = over(result, fill.rgb, fillStrength * fillShade * insideOuter);

    // Halo beyond the ring, fading to nothing before the layer edge.
    float beyond = max(0.0, distance - outer);
    float halo = exp(-beyond / (maxRadius * 0.05)) * (1.0 - insideOuter);
    halo *= 1.0 - smoothstep(maxRadius * 0.92, maxRadius, distance);
    result = over(result, ring.rgb, haloStrength * expansion * halo);

    // Ring, brightest on its inner edge and lightened toward white at a full breath.
    float across = saturate((distance - inner) / max(outer - inner, 1.0));
    half3 ringColor = mix(ring.rgb, half3(1.0h), half(0.12 * (1.0 - across) + brightening * expansion));
    float ringAlpha = mix(0.25, 1.0, expansion) * insideOuter * (1.0 - insideInner);
    result = over(result, ringColor, ringAlpha);

    return result;
}
