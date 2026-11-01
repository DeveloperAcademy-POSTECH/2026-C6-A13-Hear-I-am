#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Settings hero background (Figma 457:14441), ported from the two shaders the design uses:
// "Liquid Metal" as the fill (opacity 0.73, then a 30% black layer) and "Light rays" over it.
// Parameters are copied from the design. The rays' edge glow needs a blurred mask pass and is left out.

namespace hero {

float srgbToLinear(float c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
float linearToSrgb(float c) { return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055; }
float3 srgb3ToLinear(float3 c) { return float3(srgbToLinear(c.x), srgbToLinear(c.y), srgbToLinear(c.z)); }
float3 linear3ToSrgb(float3 c) { return float3(linearToSrgb(c.x), linearToSrgb(c.y), linearToSrgb(c.z)); }

float3 linearToOklab(float3 c) {
    float l = 0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z;
    float m = 0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z;
    float s = 0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z;
    float l_ = pow(max(l, 0.0), 1.0 / 3.0), m_ = pow(max(m, 0.0), 1.0 / 3.0), s_ = pow(max(s, 0.0), 1.0 / 3.0);
    return float3(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                  1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                  0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_);
}
float3 oklabToLinear(float3 c) {
    float l_ = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m_ = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s_ = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    return float3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}
float3 mixOklch(float3 a, float3 b, float t) {
    float3 la = linearToOklab(a), lb = linearToOklab(b);
    float ca = sqrt(la.y * la.y + la.z * la.z), cb = sqrt(lb.y * lb.y + lb.z * lb.z);
    float ha = atan2(la.z, la.y), hb = atan2(lb.z, lb.y);
    float dh = hb - ha;
    if (dh > 3.14159265) dh -= 6.28318530;
    if (dh < -3.14159265) dh += 6.28318530;
    float L = mix(la.x, lb.x, t), C = mix(ca, cb, t), h = ha + dh * t;
    return oklabToLinear(float3(L, C * cos(h), C * sin(h)));
}

// Liquid Metal, seed 262 and the design's other values.
float3 liquidMetal(float2 uv, float2 dims, float seconds) {
    const float3 color1 = float3(0.07506886, 0.0, 0.13247446);
    const float3 color2 = float3(0.0, 0.76666665, 1.0);
    const float3 color3 = float3(0.0, 0.85657799, 0.91776216);
    const float3 color4 = float3(0.13358562, 0.0, 0.16357422);
    const float seed = 262.0, speed = 0.23, featureScale = 0.38, amplitude = 1.0, frequency = 1.35;
    const float definition = 7.0, bands = 2.6, grain = 0.06, exposure = 1.09, contrastAmt = 1.29, saturation = 1.0;

    float aspect = dims.x / max(dims.y, 1.0);
    float T = seconds * 0.3 * speed;
    float2 p0 = float2((uv.x * 2.0 - 1.0) * aspect, -(uv.y * 2.0 - 1.0));
    float ang = seed * 2.3999632;
    float ca = cos(ang), sa = sin(ang);
    float2 p = float2(ca * p0.x + sa * p0.y, -sa * p0.x + ca * p0.y) * featureScale;

    const float3 so = float3(0.185610, 0.435062, 0.842443);
    const float3 so2 = float3(0.640671, 0.186654, 0.946699);
    float2 q = p;
    float a_acc = 0.883862, d_acc = -1.968811;
    int maxIter = int(definition);
    for (int j = 2; j < 13; j++) {
        if (j >= maxIter) break;
        float fj = float(j);
        q = q + amplitude * sin(q.yx * frequency * fj + T + float2(a_acc, d_acc) + so.xy * fj) / fj;
        a_acc = a_acc + cos(fj + d_acc * 1.2 + q.x * 2.0 - T + so2.z);
        d_acc = d_acc + sin(fj * q.y + a_acc + so.z + T + so2.y);
    }
    float L = length(q.yx + float2(a_acc, d_acc) * 0.2) * bands + so.x;
    float s1 = 0.5 + 0.5 * sin(L + 1.0), s2 = 0.5 + 0.5 * sin(L + 4.0), s3 = 0.5 + 0.5 * sin(L + 9.0);
    float val = clamp(((s1 * 0.5 + s2 + s3 * 0.5) * 0.5 - 0.3) / 0.4, 0.0, 1.0);

    float2 pix = floor(uv * dims);
    float ign = fract(52.9829189 * fract(dot(pix, float2(0.06711056, 0.00583715))));
    val = clamp(val + (ign - 0.5) * grain, 0.0, 1.0);

    float3 lin1 = srgb3ToLinear(color1), lin2 = srgb3ToLinear(color2), lin3 = srgb3ToLinear(color3), lin4 = srgb3ToLinear(color4);
    float3 col;
    if (val < 0.333333) col = mixOklch(lin1, lin2, val * 3.0);
    else if (val < 0.666667) col = mixOklch(lin2, lin3, (val - 0.333333) * 3.0);
    else col = mixOklch(lin3, lin4, (val - 0.666667) * 3.0);

    col = col * exposure;
    float3 lab = linearToOklab(col);
    lab = float3(clamp((lab.x - 0.5) * contrastAmt + 0.5, 0.0, 1.0), lab.y * saturation, lab.z * saturation);
    col = oklabToLinear(lab);
    float mx = max(col.x, max(col.y, col.z)), mn = min(col.x, min(col.y, col.z));
    if (mn < 0.0 || mx > 1.0) {
        float3 g = linearToOklab(max(col, float3(0.0)));
        float gl = clamp(g.x, 0.0, 1.0);
        float gc = length(g.yz);
        float gh = atan2(g.z, g.y);
        float maxC = 0.4 * (1.0 - pow(abs(2.0 * gl - 1.0), 2.0));
        float knee = maxC * 0.7;
        if (gc > knee) gc = knee + (maxC - knee) * tanh((gc - knee) / (maxC - knee + 0.001));
        col = clamp(oklabToLinear(float3(gl, gc * cos(gh), gc * sin(gh))), float3(0.0), float3(1.0));
    }
    return linear3ToSrgb(clamp(col, float3(0.0), float3(1.0)));
}

float rayStrength(float2 sourceToPoint, float2 rayRef, float reach, float bandBase, float bandSwing,
                  float seedA, float seedB, float speed, float time) {
    float sourceDistance = length(sourceToPoint);
    float2 dir = sourceDistance > 0.0001 ? sourceToPoint / max(sourceDistance, 0.0001) : rayRef;
    float cosAngle = dot(dir, rayRef);
    float wave = (0.15 * sin(cosAngle * seedA + time * speed) + 0.20 * cos(-cosAngle * seedB + time * speed)) / 0.35;
    float bandStrength = clamp(bandBase + bandSwing * wave, 0.0, 1.0);
    float distanceModulation = clamp((reach - sourceDistance) / reach, 0.5, 1.0);
    float reachFade = 1.0 - smoothstep(reach * 0.35, reach, sourceDistance);
    float pulse = 1.0 - 0.16 * sin(time * speed * 0.55 + seedA * 0.1) - 0.07 * sin(time * speed * 1.27 + seedB * 0.1);
    return bandStrength * distanceModulation * reachFade * pulse;
}

// Light rays from below the card's bottom edge, pointing up.
float3 lightRays(float2 uv, float2 dims, float3 content, float time) {
    const float intensity = 0.08, spread = 0.85, colorBlendIn = 0.61, threshold = 0.18, density = 0.5, softness = 0.45;
    const float speed = 0.5, radius = 54.89561, angleDeg = -90.0;
    const float2 lightUv = float2(0.5, 1.1389031);
    const float3 tint1 = float3(0.10196079, 0.73725492, 0.99607843);
    const float3 tint2 = float3(0.63529414, 0.34901962, 1.0);

    float shortest = max(min(dims.x, dims.y), 1.0);
    float2 uvToEqual = dims / shortest;
    float reach = max((radius / 100.0) * (dims.y / shortest) * 2.0, 0.005);
    float2 sourceToPoint = uv * uvToEqual - lightUv * uvToEqual;
    float distanceFromLight = length(sourceToPoint);
    float colorBlend = clamp(colorBlendIn, -1.0, 1.0) * 0.5 + 0.5;
    float detailScale = pow(2.0, mix(-2.4, 2.4, density));
    float animationSpeed = mix(0.2, 4.0, speed);

    const float PI = 3.14159265359;
    float lightAngle = angleDeg * PI / 180.0;
    float2 rayDirection = float2(cos(lightAngle), sin(lightAngle));
    float halfArc = mix(0.16, PI * 1.7, spread);
    float pointAngle = atan2(sourceToPoint.y, sourceToPoint.x);
    float angleFromAxis = atan2(sin(pointAngle - lightAngle), cos(pointAngle - lightAngle));
    float rangeMask = 1.0 - smoothstep(halfArc * 0.6, halfArc, abs(angleFromAxis));
    float si = 1.0 - softness;
    float sc = si * si * si * (si * (si * 6.0 - 15.0) + 10.0);
    float bandBase = mix(1.10, 0.40, sc), bandSwing = mix(0.05, 0.65, sc);
    float band1 = rayStrength(sourceToPoint, rayDirection, reach, bandBase, bandSwing, 36.2214 * detailScale, 21.11349 * detailScale, animationSpeed, time) * rangeMask;
    float band2 = rayStrength(sourceToPoint, rayDirection, reach, bandBase, bandSwing, 22.3991 * detailScale, 18.0234 * detailScale, animationSpeed * 0.2, time) * rangeMask;
    float distanceBrightness = mix(0.5, 4.0, intensity) * 0.4 / pow(max(distanceFromLight / reach, 0.001), 1.7);
    float3 rayColor = (tint1 * band1 * (1.0 - colorBlend) * 0.9 + tint2 * band2 * colorBlend * 0.9) * distanceBrightness;

    float luma = dot(content, float3(0.2126, 0.7152, 0.0722));
    float halfWidth = max(min(threshold, 1.0 - threshold), 0.00001);
    float sourceMask = smoothstep(threshold - halfWidth, threshold + halfWidth, luma);
    return content + rayColor * (1.0 - sourceMask);
}

}

[[ stitchable ]] half4 settingsHero(float2 position, half4 color, float2 size, float time) {
    float2 dims = max(size, float2(1.0));
    float2 uv = position / dims;
    float3 fill = hero::liquidMetal(uv, dims, time) * 0.73;   // fill opacity 73% over black
    fill *= 0.7;                                              // 30% black layer
    float3 lit = hero::lightRays(uv, dims, fill, time);
    return half4(half3(clamp(lit, float3(0.0), float3(1.0))), 1.0h) * color.a;
}
