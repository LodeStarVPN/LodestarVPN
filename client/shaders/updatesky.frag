#version 440
// The night sky of the in-app update's sheet and of its card on the home page:
// the connect button's sky (nightsky.frag, connected) laid over a rectangle - the
// same colours, the same light pool around the lodestar, the same darkening
// towards the edges - with the route of the app icon on it.
//  - the light runs along the route as the update comes down; the part behind
//    it brightens towards the light, the part ahead is a faint trace
//  - the stars the light has passed ignite (a short flare), then twinkle on slow
//    sines; the route's three relays flash as it reaches them
//  - as the light comes into the lodestar it flashes (glint): its rays shoot out
//    past the sprite's and its core blooms; and the connect button's landing
//    (nightsky.frag) follows: a soft band of light runs out from it with a flash
//    round it (wave, waveAmount), the stars flare as the band passes and the rest
//    of them ignite
//  - a broken download greys the route and dims the stars (failed)
// The route is a cubic Bezier that only goes right (x grows along it), so "the
// light has passed it" is "it is left of the light". Positions are in item
// pixels from the top left; the lodestar itself is the button's star sprite,
// drawn by QML over this.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float pixel;        // one device pixel in item units (1 / devicePixelRatio)
    float corner;       // radius of the rounded corners
    float allCorners;   // 1: all four (the card), 0: the top two (the sheet)
    float vignette;     // darkening towards the edges
    float lit;          // 0..1 how much of the update has come: the dust brightens with it
    vec2 glowPos;       // the lodestar
    float glowAmount;
    float glowRadius;
    vec2 p0;            // the route
    vec2 p1;
    vec2 p2;
    vec2 p3;
    vec2 headPos;       // the light on the route
    float headOn;       // 0..1 the light is shown
    float failed;       // 0..1 the download broke off
    vec2 relay1;
    vec2 relay2;
    vec2 relay3;
    vec3 relayGlow;     // per relay: 0 not reached, 1 lit, above 1 the flash on reaching it
    float time;         // twinkle clock, s
    float wave;         // stars closer than this to the lodestar are lit (the landing)
    float scaleX;       // star positions are laid out for a width of 360 (sheet) / 328 (card)
    float cardMode;     // 0 the sheet's stars, 1 the card's
    float glint;        // 0..1 the lodestar's flash as the light comes in
    float waveAmount;   // 0..1 the landing wave's light, fading as it runs out
    float starScale;    // the lodestar's size against the sheet's
    float flashSize;    // the landing flash round the lodestar (a gaussian's sigma)
};

const vec3 TOP_LIT = vec3(14.0, 24.0, 68.0) / 255.0;
const vec3 BOTTOM_LIT = vec3(4.0, 7.0, 24.0) / 255.0;
const vec3 SKY_LIGHT = vec3(34.0, 62.0, 170.0) / 255.0;
const vec3 STAR_TINT = vec3(0.86, 0.91, 1.0);
const vec3 ROUTE = vec3(165.0, 192.0, 255.0) / 255.0;
const vec3 ROUTE_HOT = vec3(235.0, 242.0, 255.0) / 255.0;
const vec3 ROUTE_GREY = vec3(150.0, 160.0, 190.0) / 255.0;
const vec3 RIM = vec3(150.0, 175.0, 255.0) / 255.0;
const float TAU = 6.2831853;

float gauss2(float d2, float sigma) {
    return exp(-d2 / (2.0 * sigma * sigma));
}

// a small star: gaussian core, faint halo, optional thin cross rays with the
// north ray longest (as in nightsky.frag)
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

// a star that ignites when the light passes it (byPath) or with the landing
// wave, flares once and then twinkles
float skyStar(vec2 p, vec2 c, float r, float bright, float rays, float period, float phase, float byPath) {
    c.x *= scaleX;
    float dist = length(c - glowPos);
    float byLight = byPath * step(c.x, p3.x - 6.0) * smoothstep(c.x - 2.0, c.x + 10.0, headPos.x);
    float byWave = smoothstep(dist - 6.0, dist + 26.0, wave);
    float on = max(byLight, byWave);
    if (on <= 0.0) {
        return 0.0;
    }
    float tw = 0.6 + 0.4 * sin(time * TAU / period + phase);
    tw *= 0.88 + 0.12 * sin(time * TAU / (period * 2.7) + phase * 1.7);
    // a short flare as the light passes it, and as the landing wave does
    float front = (headPos.x - c.x - 6.0) / 9.0;
    float waveFront = (wave - dist - 10.0) / 30.0;
    float pop = max(exp(-front * front) * byPath * headOn, exp(-waveFront * waveFront) * waveAmount);
    return starShape(p, c, r * (0.9 + 0.12 * tw), rays) * bright * on * (tw + 1.3 * pop) * (1.0 - 0.55 * failed);
}

float hash(vec2 v) {
    return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 bez(float t) {
    float u = 1.0 - t;
    return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3;
}

vec2 bezD(float t) {
    float u = 1.0 - t;
    return 3.0 * u * u * (p1 - p0) + 6.0 * u * t * (p2 - p1) + 3.0 * t * t * (p3 - p2);
}

// distance to the route: its point at this x (Newton on x(t), which only grows),
// the vertical gap turned into the distance by the slope there
float routeDistance(vec2 p) {
    if (p.x < p0.x || p.x > p3.x) {
        return 1e4;
    }
    float t = clamp((p.x - p0.x) / max(p3.x - p0.x, 1.0), 0.0, 1.0);
    for (int i = 0; i < 4; ++i) {
        t = clamp(t - (bez(t).x - p.x) / max(bezD(t).x, 1e-3), 0.0, 1.0);
    }
    vec2 d = bezD(t);
    return abs(p.y - bez(t).y) * abs(d.x) / max(length(d), 1e-3);
}

vec3 relayLight(vec2 p, vec2 c, float g) {
    vec2 d = p - c;
    float d2 = dot(d, d);
    if (d2 > 900.0) {
        return vec3(0.0);
    }
    if (g <= 0.0) {
        return STAR_TINT * gauss2(d2, 0.6) * 0.32;
    }
    float bloom = max(g - 1.0, 0.0);
    float k = 1.0 - 0.6 * failed;
    return (STAR_TINT * 0.65 * gauss2(d2, 2.0 + 4.0 * bloom) * (0.26 + 0.36 * bloom)
            + vec3(1.0) * gauss2(d2, 0.9)) * k;
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 q = qt_TexCoord0;

    // rounded corners: distance to the edge of the shape
    float bottomEdge = allCorners > 0.5 ? itemSize.y - p.y : 1e4;
    float edge = min(min(p.x, itemSize.x - p.x), min(p.y, bottomEdge));
    vec2 cc = vec2(clamp(p.x, corner, itemSize.x - corner), clamp(p.y, corner, allCorners > 0.5 ? itemSize.y - corner : 1e6));
    if (p.x != cc.x && p.y != cc.y) {
        edge = corner - length(p - cc);
    }
    float alpha = clamp(edge / pixel + 0.5, 0.0, 1.0);
    if (alpha <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // sky: the button's lit gradient, darker towards the edges
    float t = clamp(q.y * 0.9 + (1.0 - q.x) * 0.1, 0.0, 1.0);
    vec3 col = mix(TOP_LIT, BOTTOM_LIT, t);
    float rn = length((q - 0.5) * 2.0) / 1.41421356;
    col *= 1.0 - vignette * smoothstep(0.3, 1.0, rn);

    // light pool around the lodestar
    vec2 g = p - glowPos;
    float g2 = dot(g, g);
    float pool = (gauss2(g2, glowRadius) * 0.42 + gauss2(g2, glowRadius * 2.4) * 0.10) * glowAmount;
    col = mix(col, SKY_LIGHT, clamp(pool, 0.0, 1.0));

    // the glass edge: a faint cool rim, brighter in the middle of the top
    float rim = 1.0 - smoothstep(0.0, 1.5 * pixel, edge);
    float rimTop = p.y < corner + 1.0 ? 0.10 + 0.14 * (1.0 - abs(2.0 * q.x - 1.0)) : 0.10;
    col += RIM * rim * rimTop;

    // the landing (nightsky.frag's): a soft band of light running out from the
    // lodestar, and a flash round it. The band is wider and fainter than the
    // button's: over the sheet it runs far, and a sharper one reads as a ring
    if (waveAmount > 0.0) {
        float dO = length(p - glowPos);
        float across = (dO - wave) / (10.0 + wave * 0.16);
        float band = exp(-across * across);
        float flash = gauss2(dO * dO, flashSize);
        col += vec3(0.42, 0.56, 1.0) * (band * 0.05 + flash * 0.30 * waveAmount) * waveAmount;
    }

    // stars
    float s = 0.0;
    if (cardMode < 0.5) {
        s += skyStar(p, vec2(64.0, 94.0), 0.95, 0.95, 1.0, 4.2, 0.0, 1.0);
        s += skyStar(p, vec2(262.0, 152.0), 0.85, 0.82, 1.0, 3.4, 1.7, 1.0);
        s += skyStar(p, vec2(346.0, 112.0), 0.80, 0.75, 0.8, 5.1, 3.1, 0.0);
        s += skyStar(p, vec2(150.0, 78.0), 0.74, 0.72, 0.6, 2.9, 4.4, 1.0);
        s += skyStar(p, vec2(22.0, 128.0), 0.68, 0.64, 0.0, 3.8, 2.2, 1.0);
        s += skyStar(p, vec2(196.0, 184.0), 0.68, 0.66, 0.0, 4.6, 5.3, 0.0);
        s += skyStar(p, vec2(322.0, 186.0), 0.62, 0.56, 0.0, 3.1, 0.9, 0.0);
        s += skyStar(p, vec2(104.0, 198.0), 0.60, 0.52, 0.0, 5.6, 2.8, 1.0);
        s += skyStar(p, vec2(228.0, 126.0), 0.60, 0.56, 0.0, 2.7, 3.9, 1.0);
        s += skyStar(p, vec2(276.0, 94.0), 0.56, 0.52, 0.0, 4.9, 1.2, 1.0);
        s += skyStar(p, vec2(118.0, 160.0), 0.58, 0.54, 0.0, 3.6, 5.9, 1.0);
        s += skyStar(p, vec2(300.0, 140.0), 0.54, 0.46, 0.0, 4.4, 4.7, 0.0);
        s += skyStar(p, vec2(176.0, 142.0), 0.54, 0.48, 0.0, 3.2, 0.4, 1.0);
        s += skyStar(p, vec2(40.0, 176.0), 0.52, 0.44, 0.0, 5.3, 3.5, 1.0);
        s += skyStar(p, vec2(212.0, 122.0), 0.50, 0.42, 0.0, 4.1, 2.6, 1.0);
        s += skyStar(p, vec2(244.0, 108.0), 0.56, 0.50, 0.0, 3.7, 5.1, 1.0);
        s += skyStar(p, vec2(70.0, 178.0), 0.50, 0.42, 0.0, 4.8, 1.4, 1.0);
        s += skyStar(p, vec2(96.0, 152.0), 0.54, 0.50, 0.0, 3.3, 4.0, 1.0);

        // dust: faint, static, always there
        float dust = 0.0;
        dust += starShape(p, vec2(12.0 * scaleX, 22.0), 0.45, 0.0);
        dust += starShape(p, vec2(92.0 * scaleX, 16.0), 0.45, 0.0);
        dust += starShape(p, vec2(250.0 * scaleX, 22.0), 0.45, 0.0);
        dust += starShape(p, vec2(348.0 * scaleX, 20.0), 0.45, 0.0);
        dust += starShape(p, vec2(84.0 * scaleX, 122.0), 0.45, 0.0);
        dust += starShape(p, vec2(58.0 * scaleX, 202.0), 0.45, 0.0);
        dust += starShape(p, vec2(150.0 * scaleX, 204.0), 0.45, 0.0);
        dust += starShape(p, vec2(238.0 * scaleX, 198.0), 0.45, 0.0);
        dust += starShape(p, vec2(284.0 * scaleX, 206.0), 0.45, 0.0);
        dust += starShape(p, vec2(352.0 * scaleX, 160.0), 0.45, 0.0);
        dust += starShape(p, vec2(338.0 * scaleX, 78.0), 0.45, 0.0);
        dust += starShape(p, vec2(190.0 * scaleX, 118.0), 0.45, 0.0);
        dust += starShape(p, vec2(14.0 * scaleX, 190.0), 0.45, 0.0);
        s += dust * (0.16 + 0.14 * lit);
    } else {
        s += skyStar(p, vec2(60.0, 24.0), 0.50, 0.60, 0.0, 3.4, 0.0, 1.0);
        s += skyStar(p, vec2(118.0, 56.0), 0.45, 0.50, 0.0, 4.2, 1.9, 1.0);
        s += skyStar(p, vec2(176.0, 22.0), 0.50, 0.50, 0.0, 2.9, 3.3, 1.0);
        s += skyStar(p, vec2(236.0, 57.0), 0.45, 0.46, 0.0, 5.0, 4.6, 1.0);
        s += skyStar(p, vec2(262.0, 24.0), 0.42, 0.42, 0.0, 3.7, 2.2, 1.0);

        float dust = 0.0;
        dust += starShape(p, vec2(34.0 * scaleX, 52.0), 0.40, 0.0);
        dust += starShape(p, vec2(96.0 * scaleX, 12.0), 0.40, 0.0);
        dust += starShape(p, vec2(150.0 * scaleX, 44.0), 0.40, 0.0);
        dust += starShape(p, vec2(212.0 * scaleX, 12.0), 0.40, 0.0);
        dust += starShape(p, vec2(292.0 * scaleX, 30.0), 0.40, 0.0);
        dust += starShape(p, vec2(316.0 * scaleX, 58.0), 0.40, 0.0);
        s += dust * 0.18;
    }
    col += STAR_TINT * s;

    // the route: a faint trace ahead of the light, behind it a line that
    // brightens towards the light, with a soft glow
    float dR = routeDistance(p);
    if (dR < 16.0) {
        float behind = 1.0 - smoothstep(headPos.x - 0.5, headPos.x + 0.5, p.x);
        float ramp = clamp((p.x - max(p0.x, 0.0)) / max(headPos.x - max(p0.x, 0.0), 1.0), 0.0, 1.0);
        float core = 1.0 - smoothstep(0.5, 0.5 + 1.2 * pixel, dR);
        float glow = gauss2(dR * dR, 1.3) * 0.12 + gauss2(dR * dR, 2.6) * 0.06 + gauss2(dR * dR, 4.5) * 0.035;
        vec3 lineCol = mix(mix(ROUTE, ROUTE_HOT, ramp * ramp), ROUTE_GREY, failed);
        float k = 1.0 - 0.6 * failed;
        col += lineCol * behind * (core * (0.10 + 0.88 * ramp) + glow * (0.3 + 0.7 * ramp)) * k;
        col += RIM * (1.0 - behind) * core * 0.11;
    }

    // the relays
    col += relayLight(p, relay1, relayGlow.x);
    col += relayLight(p, relay2, relayGlow.y);
    col += relayLight(p, relay3, relayGlow.z);

    // the light itself
    if (headOn > 0.0) {
        vec2 h = p - headPos;
        float h2 = dot(h, h);
        col += vec3(0.55, 0.69, 1.0) * gauss2(h2, 5.5) * 0.30 * headOn;
        col += vec3(1.0) * gauss2(h2, 1.5) * headOn;
    }

    // the glint: the lodestar's rays shoot out past the sprite's, thin and fading
    // towards their ends (the north one short of the sheet's top), and its core
    // blooms (the sprite is drawn over the middle)
    if (glint > 0.0) {
        vec2 d = (p - glowPos) / starScale;
        float lenY = d.y < 0.0 ? 52.0 : 50.0;
        float w = max(0.75, 0.6 * pixel / starScale);
        float fx = max(0.0, 1.0 - abs(d.x) / 62.0);
        float fy = max(0.0, 1.0 - abs(d.y) / lenY);
        float rays = gauss2(d.y * d.y, w) * fx * fx * fx + gauss2(d.x * d.x, w) * fy * fy * fy;
        float core = gauss2(dot(d, d), 7.0);
        col += (vec3(1.0) * rays * 0.9 + STAR_TINT * core * 0.45) * glint;
    }

    // dither against 8-bit banding in the dark gradient
    col += (hash(gl_FragCoord.xy) - 0.5) / 255.0;
    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
