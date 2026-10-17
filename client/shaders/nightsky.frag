#version 440
// The connect button's night sky: a disc of sky that the lodestar lights up -
// and the eye of the home screen's telescope (HomeScene.qml): the sky in it is
// what the tube points at, and it slides by as the tube turns.
// Everything is a function of the uniforms, so every animation driven from
// QML (star position, landing wave, twinkle time, the tube) stays perfectly
// smooth.
//  - the glass: vertical night gradient + vignette, deeper when idle ("lit"
//    0..1), a faint cool rim
//  - light pool around the lodestar (follows it while it orbits)
//  - landing wave: a soft ring of light running out from the landing point;
//    the stars round it, dim till then, ignite as it passes them ("ignite"
//    radius), then twinkle on slow, unrelated sines
//  - the eye: laid out as the view on the landing point (the tube on it,
//    eyeAngle = eyeAim). EYE_K px of sky a degree of the tube: while it turns,
//    the sky slides by as much, a star smearing a little along its way while
//    fast. Further down the sky dimmer stars, and low, where the tube rests,
//    the home screen's own sky and land EYE_M times larger: the mountain the
//    tube points at (the same formulas as homesky.frag and homeland.frag)
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
    float eyeAngle;     // the telescope's tube, degrees above level
    float eyeAim;       // the same when it is on the landing point
    float eyeRest;      // and when it rests
    float eyeRate;      // how fast it turns, degrees a second
};

const vec3 TOP_IDLE = vec3(13.0, 18.0, 44.0) / 255.0;
const vec3 BOTTOM_IDLE = vec3(5.0, 7.0, 19.0) / 255.0;
const vec3 TOP_LIT = vec3(14.0, 24.0, 68.0) / 255.0;
const vec3 BOTTOM_LIT = vec3(4.0, 7.0, 24.0) / 255.0;
const vec3 SKY_LIGHT = vec3(34.0, 62.0, 170.0) / 255.0;
const vec3 STAR_TINT = vec3(0.86, 0.91, 1.0);
const float TAU = 6.2831853;

const float EYE_K = 6.0;            // px of the eye's sky a degree of the tube
const float EYE_SHUTTER = 0.012;    // s: how far back a moving star smears
// the home screen's point (its design px, local-tools/design/home/telescope.html)
// the eye's axis is on while the tube rests, and how much larger it shows it;
// the land comes no higher than LAND_TOP in that view (ridge1 at its left edge)
const vec2 EYE_REST = vec2(90.0, 495.0);
const float EYE_M = 2.0;
const float LAND_TOP = 471.0;

float eyeP;             // how far the tube is under the landing point, px of the eye
vec2 eyeT;              // where a star of the eye was a moment ago, from where it is
float landCover;        // how much of the pixel the land has covered

float gauss2(float d2, float sigma) {
    return exp(-d2 / (2.0 * sigma * sigma));
}

// a small star: gaussian core, faint halo, optional thin cross rays with the
// north ray longest (the same light as the app icon's lodestar), d from it.
// While the eye moves it is drawn along its way back (eyeT), its light spread
// over it
float starShape(vec2 d, float r, float rays) {
    r = max(r, 0.6 * pixel);
    float L = abs(eyeT.y);
    float h = L > 0.001 ? clamp(d.y / eyeT.y, 0.0, 1.0) : 0.0;
    d.y -= eyeT.y * h;
    float d2 = dot(d, d);
    if (d2 > 900.0) {
        return 0.0;
    }
    float k1 = mix(1.0, 2.5 * r / (2.5 * r + L), 0.6);
    float k3 = mix(1.0, 7.5 * r / (7.5 * r + L), 0.6);
    float v = gauss2(d2, r) * k1 + gauss2(d2, r * 3.0) * 0.16 * k3;
    if (rays > 0.0) {
        float w = max(r * 0.42, 0.45 * pixel);
        float len = r * 9.0 * rays;
        float up = d.y < 0.0 ? 1.3 : 1.0;
        float fx = max(0.0, 1.0 - abs(d.x) / len);
        float fy = max(0.0, 1.0 - abs(d.y) / (len * up));
        float hr = gauss2(d.y * d.y, w) * fx * fx;
        float vr = gauss2(d.x * d.x, w) * fy * fy;
        v += (hr + vr) * 0.7 * k1;
    }
    return v;
}

// a star of the view on the landing point (c, as the eye has it when the tube
// is on it): dim, igniting with the landing wave, then twinkling
float skyStar(vec2 p, vec2 c, float r, float bright, float rays, float period, float phase, float dim) {
    float dist = length(c - origin);
    float on = smoothstep(dist - 6.0, dist + 26.0, ignite) * field;
    float tw = 0.6 + 0.4 * sin(time * TAU / period + phase);
    tw *= 0.88 + 0.12 * sin(time * TAU / (period * 2.7) + phase * 1.7);
    // a short flare as the wave front passes
    // (squares written out: pow() of a negative base is undefined on GPUs)
    float front = (ignite - dist - 10.0) / 16.0;
    float pop = exp(-front * front) * waveAmount;
    return starShape(p - c + vec2(0.0, eyeP), r * (0.9 + 0.12 * tw * on), rays) * mix(dim, bright * (tw + 1.3 * pop), on);
}

// a star further down the sky, towards the horizon: out of the light's reach
float dimStar(vec2 p, vec2 c, float r, float dim, float rays) {
    return starShape(p - c + vec2(0.0, eyeP), r, rays) * dim;
}

float hash(vec2 v) {
    return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

// ---------------------------------------------------------------------------
// the home screen's night and land (homesky.frag, homeland.frag), in its
// design px, for the eye while the tube is low: the night unlit, as it is then
float h11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float vn(float x) {
    float i = floor(x);
    float f = fract(x);
    float u = f * f * (3.0 - 2.0 * f);
    return mix(h11(i), h11(i + 1.0), u);
}

float fbm(float x, float oct, float pers) {
    float s = 0.0;
    float a = 0.5;
    float fr = 1.0;
    float n = 0.0;
    for (int i = 0; i < 6; i++) {
        if (float(i) >= oct) {
            break;
        }
        s += a * vn(x * fr);
        n += a;
        a *= pers;
        fr *= 2.03;
    }
    return s / n;
}

float ridge1(float x) {
    float a = 28.0 + 125.0 * (1.0 - smoothstep(0.0, 165.0, x)) + 38.0 * smoothstep(250.0, 393.0, x);
    return 562.0 - a * (0.32 + 0.68 * pow(fbm(x / 118.0 + 8.9, 5.0, 0.52), 1.2));
}

float ridge2(float x) {
    float a = 16.0 + 86.0 * (1.0 - smoothstep(10.0, 185.0, x)) + 22.0 * smoothstep(290.0, 393.0, x);
    return 587.0 - a * (0.3 + 0.7 * pow(fbm(x / 92.0 + 11.4, 5.0, 0.5), 1.12));
}

float ridge3(float x) {
    float a = 8.0 + 38.0 * (1.0 - smoothstep(0.0, 160.0, x));
    return 606.0 - a * (0.3 + 0.7 * fbm(x / 150.0 + 7.7, 4.0, 0.45));
}

float ridge4(float x) {
    float k = (x - 330.0) / 72.0;
    float k2 = (x - 330.0) / 46.0;
    return 612.0 - 0.02 * x - 16.0 * exp(-k * k) - 2.4 * fbm(x / 140.0 + 1.3, 3.0, 0.45) * (1.0 - exp(-k2 * k2));
}

vec3 homeSky(vec2 p) {
    float v = p.y / 873.0;
    vec3 col = mix(vec3(4.0, 7.0, 19.0) / 255.0, vec3(8.0, 13.0, 34.0) / 255.0, smoothstep(0.0, 0.45, v));
    col = mix(col, vec3(20.0, 29.0, 73.0) / 255.0, smoothstep(0.43, 0.66, v));
    float sx = abs(p.x / 393.0 - 0.5) * 2.0;
    return col * (1.0 - 0.22 * sx * sx * sx);
}

// one ridge over col; aa: a device pixel in design px (more while it moves)
vec3 ridge(vec3 col, vec2 p, float r, vec3 crest, vec3 fog, float depth, float rim, float aa) {
    float a = clamp((p.y - r) / aa + 0.5, 0.0, 1.0);
    if (a <= 0.0) {
        return col;
    }
    landCover = max(landCover, a);
    vec3 c = mix(crest, fog, smoothstep(r, r + depth, p.y));
    c += vec3(0.42, 0.52, 1.0) * exp(-max(0.0, p.y - r) / 1.2) * rim;
    return mix(col, c, a);
}

vec3 homeLand(vec3 col, vec2 p, float aa) {
    landCover = 0.0;
    col = ridge(col, p, ridge1(p.x), vec3(10.0, 15.0, 37.0) / 255.0, vec3(15.0, 22.0, 54.0) / 255.0, 40.0, 0.015, aa);
    float dx = p.x - 196.0;
    float m = gauss2((p.y - 556.0) * (p.y - 556.0), 16.0) * (0.35 + 0.65 * gauss2(dx * dx, 150.0));
    col = mix(col, vec3(58.0, 82.0, 182.0) / 255.0, clamp(m * 0.045, 0.0, 1.0));
    col = ridge(col, p, ridge2(p.x), vec3(7.0, 10.0, 26.0) / 255.0, vec3(10.0, 16.0, 40.0) / 255.0, 30.0, 0.0125, aa);
    dx = p.x - 200.0;
    m = gauss2((p.y - 584.0) * (p.y - 584.0), 11.0) * (0.25 + 0.75 * gauss2(dx * dx, 135.0));
    col = mix(col, vec3(70.0, 96.0, 205.0) / 255.0, clamp(m * 0.045, 0.0, 1.0));
    col = ridge(col, p, ridge3(p.x), vec3(5.0, 7.0, 18.0) / 255.0, vec3(7.0, 11.0, 28.0) / 255.0, 22.0, 0.01, aa);
    col = ridge(col, p, ridge4(p.x), vec3(4.0, 6.0, 15.0) / 255.0, vec3(1.0, 2.0, 6.0) / 255.0, 230.0, 0.0175, aa);
    return col;
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
    eyeP = EYE_K * (eyeAim - eyeAngle);
    eyeT = vec2(0.0, -EYE_K * eyeRate * EYE_SHUTTER);
    float blur = max(pixel, abs(eyeT.y));

    // the glass
    float t = clamp(q.y * 0.9 + (1.0 - q.x) * 0.1, 0.0, 1.0);
    vec3 col = mix(mix(TOP_IDLE, BOTTOM_IDLE, t), mix(TOP_LIT, BOTTOM_LIT, t), lit);

    // low, where the tube rests, the eye shows the home screen itself: its
    // night towards the horizon and the mountain, sliding with the tube as the
    // stars do; higher up its own sky
    float el = eyeAngle - (p.y - origin.y) / EYE_K;      // the elevation this pixel looks at
    float lift = EYE_K * (eyeAngle - eyeRest);
    vec2 s = EYE_REST + vec2(p.x, p.y - origin.y - lift) / EYE_M;
    col = mix(col, homeSky(s), 1.0 - smoothstep(20.0, 32.0, el));
    float visible = 1.0;
    if (origin.y + lift + (LAND_TOP - EYE_REST.y) * EYE_M < radius + 2.0 + blur) {
        col = homeLand(col, s, blur / EYE_M);
        visible = 1.0 - landCover;
    }
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

    // stars: the view on the landing point, the ones its light ignites
    float st = 0.0;
    st += skyStar(p, vec2(-50.5, -46.5), 0.95, 0.95, 1.0, 4.2, 0.0, 0.17);
    st += skyStar(p, vec2(56.5, -9.5), 0.85, 0.80, 1.0, 3.4, 1.7, 0.15);
    st += skyStar(p, vec2(-33.5, 60.5), 0.85, 0.75, 0.8, 5.1, 3.1, 0.14);
    st += skyStar(p, vec2(29.5, -62.5), 0.72, 0.70, 0.0, 2.9, 4.4, 0.13);
    st += skyStar(p, vec2(-70.5, 3.5), 0.72, 0.60, 0.0, 3.8, 2.2, 0.12);
    st += skyStar(p, vec2(44.5, 57.5), 0.68, 0.62, 0.0, 4.6, 5.3, 0.12);
    st += skyStar(p, vec2(-17.5, -73.5), 0.62, 0.52, 0.0, 3.1, 0.9, 0.1);
    st += skyStar(p, vec2(73.5, 29.5), 0.62, 0.55, 0.0, 5.6, 2.8, 0.1);
    st += skyStar(p, vec2(-62.5, -27.5), 0.55, 0.45, 0.0, 2.7, 3.9, 0.09);
    st += skyStar(p, vec2(59.5, -49.5), 0.55, 0.45, 0.0, 4.9, 1.2, 0.09);
    st += skyStar(p, vec2(6.5, 73.5), 0.55, 0.42, 0.0, 3.6, 5.9, 0.08);
    st += skyStar(p, vec2(-73.5, 39.5), 0.52, 0.36, 0.0, 4.4, 4.7, 0.08);
    st += skyStar(p, vec2(36.5, -35.5), 0.50, 0.40, 0.0, 3.2, 0.4, 0.08);
    st += skyStar(p, vec2(-40.5, -7.5), 0.50, 0.36, 0.0, 5.3, 3.5, 0.07);

    // further down: the sky the tube passes on its way up, and the one it rests on
    st += dimStar(p, vec2(-24.0, 104.0), 0.6, 0.16, 0.0);
    st += dimStar(p, vec2(63.0, 118.0), 0.55, 0.15, 0.0);
    st += dimStar(p, vec2(-77.0, 131.0), 0.5, 0.14, 0.0);
    st += dimStar(p, vec2(18.0, 147.0), 0.7, 0.24, 0.0);
    st += dimStar(p, vec2(-49.0, 170.0), 0.55, 0.18, 0.0);
    st += dimStar(p, vec2(74.0, 179.0), 0.5, 0.16, 0.0);
    st += dimStar(p, vec2(-8.0, 192.0), 0.5, 0.15, 0.0);
    st += dimStar(p, vec2(-46.0, 236.0), 0.8, 0.45, 0.7);
    st += dimStar(p, vec2(12.0, 222.0), 0.5, 0.18, 0.0);
    st += dimStar(p, vec2(55.0, 262.0), 0.7, 0.32, 0.0);
    st += dimStar(p, vec2(-80.0, 268.0), 0.5, 0.18, 0.0);
    st += dimStar(p, vec2(-28.0, 318.0), 0.55, 0.24, 0.0);
    st += dimStar(p, vec2(36.0, 330.0), 0.5, 0.2, 0.0);
    st += dimStar(p, vec2(78.0, 305.0), 0.5, 0.18, 0.0);
    st += dimStar(p, vec2(-60.0, 342.0), 0.5, 0.2, 0.0);
    st += dimStar(p, vec2(10.0, 362.0), 0.55, 0.2, 0.0);
    st += dimStar(p, vec2(-40.0, 384.0), 0.5, 0.18, 0.0);
    st += dimStar(p, vec2(58.0, 401.0), 0.5, 0.18, 0.0);
    st += dimStar(p, vec2(-12.0, 420.0), 0.5, 0.16, 0.0);

    // dust: faint, always there
    float dust = 0.0;
    dust += dimStar(p, vec2(-24.5, -54.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(14.5, -80.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(68.5, -30.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-82.5, -12.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-56.5, 22.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(82.5, 10.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(24.5, 82.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-16.5, 84.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(60.5, 70.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-60.5, 62.5), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-60.0, 112.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(40.0, 140.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-30.0, 160.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(10.0, 210.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-85.0, 225.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(82.0, 240.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(30.0, 270.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-50.0, 312.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(62.0, 330.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(-15.0, 350.0), 0.45, 1.0, 0.0);
    dust += dimStar(p, vec2(45.0, 375.0), 0.45, 1.0, 0.0);
    st += dust * (0.16 + 0.14 * lit);

    // none behind the land, dimmer low in the haze
    col += STAR_TINT * st * visible * mix(0.45, 1.0, smoothstep(1.0, 9.0, el));

    // dither against 8-bit banding in the dark gradient
    col += (hash(gl_FragCoord.xy) - 0.5) / 255.0;
    col = clamp(col, 0.0, 1.0);

    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
