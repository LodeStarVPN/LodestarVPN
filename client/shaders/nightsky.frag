#version 440
// The connect button's night sky: a disc of sky that the lodestar lights up.
// Everything is a function of the uniforms, so every animation driven from
// QML (star position, landing wave, twinkle time) stays perfectly smooth.
//  - sky: vertical night gradient + vignette, deeper when idle ("lit" 0..1)
//  - light pool around the lodestar (follows it while it orbits)
//  - landing wave: a soft ring of light running out from the landing point;
//    background stars ignite as it passes them ("ignite" radius), then
//    twinkle on slow, unrelated sines
//  - a few faint static dust stars that are there even when idle
// Positions and sizes are in item pixels relative to the item centre.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float pixel;        // one device pixel in item units (1 / devicePixelRatio)
    float radius;       // sky disc radius
    float lit;          // 0 idle .. 1 connected
    float time;         // seconds, twinkle clock
    vec2 glowPos;       // the lodestar
    float glowAmount;
    float glowRadius;
    vec2 origin;        // landing point
    float waveRadius;
    float waveAmount;
    float ignite;       // stars closer than this to the origin are lit
    float field;        // overall visibility of the star field
};

const vec3 TOP_IDLE = vec3(13.0, 18.0, 44.0) / 255.0;
const vec3 BOTTOM_IDLE = vec3(5.0, 7.0, 19.0) / 255.0;
const vec3 TOP_LIT = vec3(14.0, 24.0, 68.0) / 255.0;
const vec3 BOTTOM_LIT = vec3(4.0, 7.0, 24.0) / 255.0;
const vec3 SKY_LIGHT = vec3(34.0, 62.0, 170.0) / 255.0;
const vec3 STAR_TINT = vec3(0.86, 0.91, 1.0);
const float TAU = 6.2831853;

float gauss2(float d2, float sigma) {
    return exp(-d2 / (2.0 * sigma * sigma));
}

// a small star: gaussian core, faint halo, optional thin cross rays with the
// north ray longest (the same light as the app icon's lodestar)
float starShape(vec2 p, vec2 c, float r, float rays) {
    vec2 d = p - c;
    float d2 = dot(d, d);
    if (d2 > 900.0) {
        return 0.0;
    }
    r = max(r, 0.6 * pixel);
    float v = gauss2(d2, r) + gauss2(d2, r * 3.0) * 0.16;
    if (rays > 0.0) {
        float w = max(r * 0.42, 0.45 * pixel);
        float len = r * 9.0 * rays;
        float up = d.y < 0.0 ? 1.3 : 1.0;
        float fx = max(0.0, 1.0 - abs(d.x) / len);
        float fy = max(0.0, 1.0 - abs(d.y) / (len * up));
        float h = gauss2(d.y * d.y, w) * fx * fx;
        float vv = gauss2(d.x * d.x, w) * fy * fy;
        v += (h + vv) * 0.7;
    }
    return v;
}

// a background star that ignites with the landing wave and then twinkles
float skyStar(vec2 p, vec2 c, float r, float bright, float rays, float period, float phase) {
    float dist = length(c - origin);
    float on = smoothstep(dist - 6.0, dist + 26.0, ignite) * field;
    if (on <= 0.0) {
        return 0.0;
    }
    float tw = 0.6 + 0.4 * sin(time * TAU / period + phase);
    tw *= 0.88 + 0.12 * sin(time * TAU / (period * 2.7) + phase * 1.7);
    // a short flare as the wave front passes
    // (squares written out: pow() of a negative base is undefined on GPUs)
    float front = (ignite - dist - 10.0) / 16.0;
    float pop = exp(-front * front) * waveAmount;
    return starShape(p, c, r * (0.9 + 0.12 * tw), rays) * bright * on * (tw + 1.3 * pop);
}

float hash(vec2 v) {
    return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * itemSize;
    float r = length(p);
    float alpha = clamp((radius - r) / pixel + 0.5, 0.0, 1.0);
    if (alpha <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 q = p / (2.0 * radius) + 0.5;           // 0..1 across the disc

    // sky
    float t = clamp(q.y * 0.9 + (1.0 - q.x) * 0.1, 0.0, 1.0);
    vec3 col = mix(mix(TOP_IDLE, BOTTOM_IDLE, t), mix(TOP_LIT, BOTTOM_LIT, t), lit);
    col *= 1.0 - 0.42 * smoothstep(0.3, 1.0, r / radius);

    // light pool around the lodestar
    vec2 g = p - glowPos;
    float g2 = dot(g, g);
    float pool = (gauss2(g2, glowRadius) * 0.42 + gauss2(g2, glowRadius * 2.4) * 0.10) * glowAmount;
    col = mix(col, SKY_LIGHT, clamp(pool, 0.0, 1.0));

    // inner edge of the glass: a faint cool rim, brighter at the top
    float edge = smoothstep(radius - 8.0, radius, r) * (0.04 + 0.04 * lit) * (0.5 + 0.5 * (1.0 - q.y));
    col += SKY_LIGHT * edge * 1.6;

    // landing wave: a soft band running out from the origin + a flash
    float dO = length(p - origin);
    float across = (dO - waveRadius) / (4.0 + waveRadius * 0.08);
    float band = exp(-across * across);
    float flash = gauss2(dO * dO, 12.0 + waveRadius * 0.25);
    col += vec3(0.42, 0.56, 1.0) * (band * 0.07 + flash * 0.30 * waveAmount) * waveAmount;

    // stars
    float s = 0.0;
    s += skyStar(p, vec2(-50.5, -46.5), 0.95, 0.95, 1.0, 4.2, 0.0);
    s += skyStar(p, vec2(56.5, -9.5), 0.85, 0.80, 1.0, 3.4, 1.7);
    s += skyStar(p, vec2(-33.5, 60.5), 0.85, 0.75, 0.8, 5.1, 3.1);
    s += skyStar(p, vec2(29.5, -62.5), 0.72, 0.70, 0.0, 2.9, 4.4);
    s += skyStar(p, vec2(-70.5, 3.5), 0.72, 0.60, 0.0, 3.8, 2.2);
    s += skyStar(p, vec2(44.5, 57.5), 0.68, 0.62, 0.0, 4.6, 5.3);
    s += skyStar(p, vec2(-17.5, -73.5), 0.62, 0.52, 0.0, 3.1, 0.9);
    s += skyStar(p, vec2(73.5, 29.5), 0.62, 0.55, 0.0, 5.6, 2.8);
    s += skyStar(p, vec2(-62.5, -27.5), 0.55, 0.45, 0.0, 2.7, 3.9);
    s += skyStar(p, vec2(59.5, -49.5), 0.55, 0.45, 0.0, 4.9, 1.2);
    s += skyStar(p, vec2(6.5, 73.5), 0.55, 0.42, 0.0, 3.6, 5.9);
    s += skyStar(p, vec2(-73.5, 39.5), 0.52, 0.36, 0.0, 4.4, 4.7);
    s += skyStar(p, vec2(36.5, -35.5), 0.50, 0.40, 0.0, 3.2, 0.4);
    s += skyStar(p, vec2(-40.5, -7.5), 0.50, 0.36, 0.0, 5.3, 3.5);

    // dust: faint, static, always there
    float dust = 0.0;
    dust += starShape(p, vec2(-24.5, -54.5), 0.45, 0.0);
    dust += starShape(p, vec2(14.5, -80.5), 0.45, 0.0);
    dust += starShape(p, vec2(68.5, -30.5), 0.45, 0.0);
    dust += starShape(p, vec2(-82.5, -12.5), 0.45, 0.0);
    dust += starShape(p, vec2(-56.5, 22.5), 0.45, 0.0);
    dust += starShape(p, vec2(82.5, 10.5), 0.45, 0.0);
    dust += starShape(p, vec2(24.5, 82.5), 0.45, 0.0);
    dust += starShape(p, vec2(-16.5, 84.5), 0.45, 0.0);
    dust += starShape(p, vec2(60.5, 70.5), 0.45, 0.0);
    dust += starShape(p, vec2(-60.5, 62.5), 0.45, 0.0);
    s += dust * (0.16 + 0.14 * lit);

    col += STAR_TINT * s;

    // dither against 8-bit banding in the dark gradient
    col += (hash(gl_FragCoord.xy) - 0.5) / 255.0;
    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
