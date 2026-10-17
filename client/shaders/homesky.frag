#version 440
// The home screen's night sky behind the connect circle (HomeScene.qml); the
// land in front of it is homeland.frag, the circle's own sky nightsky.frag.
//  - the night: darkest overhead, lighter towards the hills
//  - a pool of light round the circle, brighter once the lodestar has landed
//    (night), and while it circles a glow spilling past the ring after it
//  - the landing wave of the button, running on out over the sky (wave)
//  - the Little Dipper, its handle leading to the circle - the lodestar is
//    Polaris: dim while disconnected, igniting as the wave passes and then
//    twinkling while connected (field)
//  - the sky's own stars, a real sky's down to the hills: their shapes drawn
//    once into a texture (homestars.frag), lit, twinkled and flared here as the
//    dipper's are
// Lengths are the design's (local-tools/design/home/telescope.html, a 393 px
// wide screen) times sc; positions are taken from the circle's centre, the
// horizon from the top of the server card, where the land stands.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float pixel;        // one device pixel in item units (1 / devicePixelRatio)
    float sc;           // item units per design px
    vec2 circle;        // the connect circle's centre
    float cardTop;      // the server card's top
    float time;         // twinkle clock, s (the button's)
    float night;        // 0 disconnected, 0.1 connecting, 1 landed
    float spill;        // the circling star's glow past the ring
    vec2 spillDir;      // towards the star from the centre
    float wave;         // the landing wave's radius, item units
    float waveAmount;
    float ignite;       // stars closer than this to the landing point are lit, item units
    float field;        // the stars on (the button's)
    vec2 starsSize;     // the stars' texture, from the top left, item units
};

// homestars.frag's: r unlit and g lit brightness (square-rooted), b phase, a period
layout(binding = 1) uniform sampler2D stars;

const vec3 SKY_LIGHT = vec3(34.0, 62.0, 170.0) / 255.0;
const vec3 STAR_TINT = vec3(0.86, 0.91, 1.0);
const float TAU = 6.2831853;

float px;               // a device pixel in design px
float lit;              // ignite in design px

float gauss2(float d2, float s) {
    return exp(-d2 / (2.0 * s * s));
}

float hash(vec2 v) {
    return fract(52.9829189 * fract(dot(v, vec2(0.06711056, 0.00583715))));
}

// a star of the sky: a core, a halo, the brightest with thin rays (the north
// one longest); dim until lit, then twinkling, flaring as the wave passes it
float bgStar(vec2 q, vec2 c, float sz, float rays, float bright, float period, float phase, float dim) {
    vec2 d = q - c;
    float d2 = dot(d, d);
    if (d2 > 1600.0) {
        return 0.0;
    }
    float v = gauss2(d2, max(0.5 + 0.22 * sz, 0.62 * px)) + gauss2(d2, 1.5 + 1.7 * sz) * (0.22 + 0.3 * sz)
            + gauss2(d2, 5.0 + 6.0 * sz) * 0.045 * sz;
    if (rays > 0.0) {
        float w = max(0.42, 0.5 * px);
        float len = (5.0 + 11.0 * sz) * rays;
        float up = d.y < 0.0 ? 1.35 : 1.0;
        float fx = max(0.0, 1.0 - abs(d.x) / len);
        float fy = max(0.0, 1.0 - abs(d.y) / (len * up));
        v += (gauss2(d.y * d.y, w) * fx * fx + gauss2(d.x * d.x, w) * fy * fy) * 0.75;
    }
    float dist = length(c - vec2(0.0, -22.0));
    float on = smoothstep(dist - 6.0, dist + 26.0, lit) * field;
    float tw = 0.72 + 0.28 * sin(time * TAU / period + phase);
    // (squares written out: pow() of a negative base is undefined on GPUs)
    float front = (lit - dist - 10.0) / 16.0;
    float pop = exp(-front * front) * waveAmount;
    return v * mix(dim, bright * (tw + 1.4 * pop), on);
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    px = pixel / sc;
    lit = ignite / sc;
    vec2 q = (p - circle) / sc;                      // design px from the circle's centre

    // the night: darkest overhead, lighter towards the horizon
    float v = (631.0 + (p.y - cardTop) / sc) / 873.0;
    vec3 col = mix(vec3(4.0, 7.0, 19.0) / 255.0, vec3(8.0, 13.0, 34.0) / 255.0, smoothstep(0.0, 0.45, v));
    col = mix(col, vec3(20.0, 29.0, 73.0) / 255.0, smoothstep(0.43, 0.66, v));
    float sx = abs(qt_TexCoord0.x - 0.5) * 2.0;
    col *= 1.0 - 0.22 * sx * sx * sx;

    // light round the circle
    float d0 = dot(q, q);
    float pool = (gauss2(d0, 118.0) * 0.15 + gauss2(d0, 250.0) * 0.035) * night + gauss2(d0, 112.0) * 0.03 * (1.0 - night);
    col = mix(col, SKY_LIGHT, clamp(pool, 0.0, 1.0));
    if (spill > 0.0) {
        vec2 s = q - spillDir * 104.0;
        float ds2 = dot(s, s);
        col = mix(col, SKY_LIGHT, clamp((gauss2(ds2, 30.0) * 0.22 + gauss2(ds2, 82.0) * 0.06) * spill, 0.0, 1.0));
    }

    // the landing wave, out past the ring
    if (waveAmount > 0.0) {
        float dO = length(q - vec2(0.0, -22.0));
        float w = wave / sc;
        float across = (dO - w) / (26.0 + w * 0.16);
        col += vec3(0.42, 0.56, 1.0) * exp(-across * across) * 0.03 * waveAmount * smoothstep(88.0, 130.0, dO);
    }

    // the Little Dipper (real positions round the pole, turned so its handle
    // leads to the circle) and three faint stars
    float s = 0.0;
    s += bgStar(q, vec2(-51.0, -37.8), 0.179, 0.0, 0.819, 3.920, 3.760, 0.2);    // Yildun
    s += bgStar(q, vec2(-100.1, -94.1), 0.250, 0.0, 0.835, 5.060, 1.020, 0.2);   // epsilon
    s += bgStar(q, vec2(-112.5, -173.2), 0.214, 0.0, 0.827, 3.190, 2.390, 0.2);  // zeta
    s += bgStar(q, vec2(-156.8, -179.7), 0.000, 0.0, 0.780, 4.970, 4.330, 0.2);  // eta
    s += bgStar(q, vec2(-140.5, -267.5), 0.679, 0.6, 0.929, 4.100, 3.420, 0.34); // Pherkad
    s += bgStar(q, vec2(-92.7, -248.5), 1.000, 1.0, 1.000, 5.330, 3.650, 0.34);  // Kochab
    s += bgStar(q, vec2(143.5, -191.0), 0.350, 0.0, 0.800, 3.600, 3.200, 0.08);
    s += bgStar(q, vec2(169.5, -43.0), 0.220, 0.0, 0.720, 3.600, 2.400, 0.08);
    s += bgStar(q, vec2(-168.5, 87.0), 0.280, 0.0, 0.750, 3.600, 2.200, 0.08);

    // the sky's own stars, from their texture: one sample a pixel
    if (p.y < starsSize.y) {
        vec4 t = texture(stars, p / starsSize);
        float bright = t.g * t.g;
        if (bright > 0.0002) {
            float dist = length(q - vec2(0.0, -22.0));
            float on = smoothstep(dist - 6.0, dist + 26.0, lit) * field;
            float tw = 0.72 + 0.28 * sin(time * TAU / (2.8 + 3.4 * t.a) + t.b * TAU);
            float front = (lit - dist - 10.0) / 16.0;
            float pop = exp(-front * front) * waveAmount;
            s += mix(t.r * t.r, bright * (tw + 1.4 * pop), on);
        }
    }
    col += STAR_TINT * s;

    // dither against 8-bit banding in the dark gradient
    col += (hash(gl_FragCoord.xy) - 0.5) / 255.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
