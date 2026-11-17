//
//  MergingGuide.metal
//  Tuntun
//
//  Created by Amelia Putri Aftiana on 17/11/2026.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// Polynomial smooth minimum: joins two distance fields with a rounded bridge `k` wide.
static float smoothUnion(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

/// Places premultiplied `top` over premultiplied `bottom`.
static half4 over(half4 bottom, half4 top) {
    return top + bottom * (1.0h - top.a);
}

/// Premultiplies an opaque colour by `alpha`.
static half4 tinted(half4 color, float alpha) {
    half a = half(clamp(alpha, 0.0, 1.0));
    return half4(color.rgb * a, a);
}

/// Two guide circles drawn as one gooey shape that becomes a single circle as they merge.
///
/// `first` and `second` are the circle centres in this layer's points, `firstRadius` and
/// `secondRadius` their radii. `smoothing` is the bridge width; the caller widens it and pulls
/// the centres together as the circles merge. The outline is a `ringWidth` band centred on the
/// edge, so a SwiftUI stroke of the same width and radius sits exactly on it. Under it lies a
/// dark underlay for contrast on bright video, outside the outline only, and inside it a soft
/// fill. The source colour is ignored.
[[ stitchable ]] half4 mergingGuide(
    float2 position,
    half4 color,
    float2 first,
    float2 second,
    float firstRadius,
    float secondRadius,
    float smoothing,
    float ringWidth,
    half4 fill,
    float fillOpacity,
    half4 ring,
    float ringOpacity,
    half4 underlay,
    float underlayOpacity
) {
    float distance = smoothUnion(
        length(position - first) - firstRadius,
        length(position - second) - secondRadius,
        max(smoothing, 0.0001)
    );

    // About one point of anti-aliasing on each edge.
    const float edge = 1.0;
    float halfRing = ringWidth * 0.5;

    // The underlay hugs only the outer side of the ring. Inside, the smooth union's distance is
    // not exact near the bridge, and an inner band there would show as a dark streak.
    float underlayAlpha = smoothstep(-edge, edge, distance)
        * (1.0 - smoothstep(halfRing + 2.0 - edge, halfRing + 2.0 + edge, distance));
    float fillAlpha = 1.0 - smoothstep(-halfRing - edge, -halfRing + edge, distance);
    float ringAlpha = 1.0 - smoothstep(halfRing - edge, halfRing + edge, abs(distance));

    half4 result = half4(0.0h);
    result = over(result, tinted(underlay, underlayAlpha * underlayOpacity * ringOpacity));
    result = over(result, tinted(fill, fillAlpha * fillOpacity));
    result = over(result, tinted(ring, ringAlpha * ringOpacity));
    return result;
}
