#version 440
// The home screen's land (HomeScene.qml): four ridges of hills, back to front,
// with mist between them, over the night sky of homesky.frag. The ridges are
// smooth noise, not repeating bumps; the near hill on the right carries the
// telescope, whose feet stand on this same formula (ridge4). Each ridge has a
// faint rim of starlight on its crest; the light of the landed lodestar
// (night) brightens the mist and the rims a little.
// It is drawn into a layer once (and again while night changes), with alpha:
// transparent above the land. Lengths are the design's
// (local-tools/design/home/telescope.html, a 393 px wide screen) times sc,
// anchored to the top of the server card, x to the circle's centre.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float pixel;        // one device pixel in item units (1 / devicePixelRatio)
    float sc;           // item units per design px
    vec2 circle;        // the connect circle's centre, in the scene's units
    float cardTop;      // the server card's top, in the scene's units
    float landTop;      // this item's top in the scene
    float night;        // 0 disconnected .. 1 landed
};

const vec3 SKY_LIGHT = vec3(34.0, 62.0, 170.0) / 255.0;

float px;               // a device pixel in design px
vec4 land;              // premultiplied, painted over back to front

float gauss2(float d2, float s) {
    return exp(-d2 / (2.0 * s * s));
}

float hash(vec2 v) {
    return fract(52.9829189 * fract(dot(v, vec2(0.06711056, 0.00583715))));
}

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

// (the design's falling smoothsteps written rising: edge0 >= edge1 is
// undefined on GPUs, as is pow() of a negative base)
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

// the near hill, the telescope's (HomeScene.qml places its feet by the same formula)
float ridge4(float x) {
    float k = (x - 330.0) / 72.0;
    float k2 = (x - 330.0) / 46.0;
    return 612.0 - 0.02 * x - 16.0 * exp(-k * k) - 2.4 * fbm(x / 140.0 + 1.3, 3.0, 0.45) * (1.0 - exp(-k2 * k2));
}

void over(vec3 c, float a) {
    land = vec4(c * a, a) + land * (1.0 - a);
}

void ridge(vec2 p, float r, vec3 crest, vec3 fog, float depth, float rim, float poolK, float pool) {
    float a = clamp((p.y - r) / px + 0.5, 0.0, 1.0);
    if (a <= 0.0) {
        return;
    }
    vec3 c = mix(crest, fog, smoothstep(r, r + depth, p.y));
    c += vec3(0.42, 0.52, 1.0) * exp(-max(0.0, p.y - r) / 1.2) * rim;
    c = mix(c, SKY_LIGHT, clamp(pool * poolK, 0.0, 1.0));
    over(c, a);
}

void main() {
    vec2 s = vec2(qt_TexCoord0.x * itemSize.x, landTop + qt_TexCoord0.y * itemSize.y);
    px = pixel / sc;
    // the design's coordinates: x from the circle's centre, y from the card's top
    vec2 p = vec2(196.5 + (s.x - circle.x) / sc, 631.0 + (s.y - cardTop) / sc);
    land = vec4(0.0);
    if (p.y < 400.0) {
        fragColor = land;           // the sky: no ridge or mist reaches up here
        return;
    }
    vec2 q = (s - circle) / sc;
    float d0 = dot(q, q);
    float pool = (gauss2(d0, 118.0) * 0.15 + gauss2(d0, 250.0) * 0.035) * night + gauss2(d0, 112.0) * 0.03 * (1.0 - night);
    float lt = 0.5 + 0.5 * night;

    ridge(p, ridge1(p.x), vec3(10.0, 15.0, 37.0) / 255.0, vec3(15.0, 22.0, 54.0) / 255.0, 40.0, 0.03 * lt, 0.14, pool);
    float dx = p.x - 196.0;
    float m = gauss2((p.y - 556.0) * (p.y - 556.0), 16.0) * (0.35 + 0.65 * gauss2(dx * dx, 150.0));
    over(vec3(58.0, 82.0, 182.0) / 255.0, clamp(m * (0.045 + 0.08 * night), 0.0, 1.0));
    ridge(p, ridge2(p.x), vec3(7.0, 10.0, 26.0) / 255.0, vec3(10.0, 16.0, 40.0) / 255.0, 30.0, 0.025 * lt, 0.1, pool);
    dx = p.x - 200.0;
    m = gauss2((p.y - 584.0) * (p.y - 584.0), 11.0) * (0.25 + 0.75 * gauss2(dx * dx, 135.0));
    over(vec3(70.0, 96.0, 205.0) / 255.0, clamp(m * (0.045 + 0.11 * night), 0.0, 1.0));
    ridge(p, ridge3(p.x), vec3(5.0, 7.0, 18.0) / 255.0, vec3(7.0, 11.0, 28.0) / 255.0, 22.0, 0.02 * lt, 0.07, pool);
    ridge(p, ridge4(p.x), vec3(4.0, 6.0, 15.0) / 255.0, vec3(1.0, 2.0, 6.0) / 255.0, 230.0, 0.035 * lt, 0.05, pool);

    // dither against 8-bit banding in the dark fog
    land.rgb += (hash(gl_FragCoord.xy) - 0.5) / 255.0 * land.a;
    fragColor = clamp(land, 0.0, 1.0) * qt_Opacity;
}
