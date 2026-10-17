#version 440
// The home screen's own stars (HomeScene.qml), drawn once into a texture that homesky.frag reads - a full
// screen of them each frame would cost the sky shader some fifty stars a pixel. A real sky's (the owner,
// 2026-10-17: «небо почти пустое», «на горизонте нет звезд, продумай точки для звезд более правильно»): as many
// of each brightness as a real sky has them, placed as stars are but never in a clump, dimmed by the air
// towards the hills and by the circle's light, none at the gear or crowding the Little Dipper, down to the far
// hills' line. The list is local-tools/design/home/tools/starfield.py's (seed 342; stars.js in the mockup,
// which draws the same). Here only their shapes - telescope.html's bgStar: a core, a halo, the brightest with
// thin rays: r the unlit brightness and g the lit one (square-rooted, for the 8-bit texture's faint halos),
// b and a the phase and the period of the star brightest at the pixel; the sky lights, twinkles and flares them.
// Lengths are the design's (a 393 px wide screen) times sc, positions from the circle's centre.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float pixel;        // one device pixel in item units (1 / devicePixelRatio)
    float sc;           // item units per design px
    vec2 circle;        // the connect circle's centre
};

float px;               // a device pixel in design px
vec2 q;                 // design px from the circle's centre
float dimSum;
float litSum;
float best;
float bestPhase;
float bestPeriod;

float gauss2(float d2, float s) {
    return exp(-d2 / (2.0 * s * s));
}

void star(vec2 c, float sz, float rays, float dim, float lit, float period, float phase) {
    vec2 d = q - c;
    float d2 = dot(d, d);
    if (d2 > 1600.0) {
        return;
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
    dimSum += v * dim;
    litSum += v * lit;
    if (v > best) {
        best = v;
        bestPhase = phase;
        bestPeriod = period;
    }
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    px = pixel / sc;
    q = (p - circle) / sc;
    dimSum = 0.0;
    litSum = 0.0;
    best = 0.0;
    bestPhase = 0.0;
    bestPeriod = 2.8;

    star(vec2(13.0, -145.7), 0.082, 0.00, 0.242, 0.365, 3.92, 3.17);
    star(vec2(157.1, -108.7), 0.228, 0.00, 0.378, 0.542, 5.90, 3.85);
    star(vec2(41.4, 152.3), 0.288, 0.00, 0.434, 0.615, 2.98, 3.83);
    star(vec2(-20.8, -251.1), 0.177, 0.00, 0.330, 0.479, 5.39, 1.72);
    star(vec2(158.1, -97.1), 0.288, 0.00, 0.434, 0.614, 2.99, 5.07);
    star(vec2(-32.2, -292.5), 0.127, 0.00, 0.283, 0.419, 5.15, 0.90);
    star(vec2(-171.8, -103.2), 0.080, 0.00, 0.235, 0.355, 4.93, 0.57);
    star(vec2(-72.7, -218.0), 0.086, 0.00, 0.246, 0.370, 4.68, 5.30);
    star(vec2(100.3, 149.4), 0.080, 0.00, 0.210, 0.323, 4.61, 1.58);
    star(vec2(-102.7, 68.6), 0.080, 0.00, 0.212, 0.325, 2.99, 3.96);
    star(vec2(-124.4, -229.6), 0.315, 0.00, 0.459, 0.647, 5.53, 4.01);
    star(vec2(-151.3, -60.8), 0.080, 0.00, 0.225, 0.343, 5.11, 5.88);
    star(vec2(37.2, -164.9), 0.478, 0.00, 0.611, 0.845, 3.67, 0.57);
    star(vec2(112.9, -67.3), 0.126, 0.00, 0.283, 0.417, 3.07, 4.72);
    star(vec2(3.9, -120.5), 0.184, 0.00, 0.337, 0.488, 3.19, 2.08);
    star(vec2(-102.6, 144.0), 0.149, 0.00, 0.304, 0.445, 6.03, 4.56);
    star(vec2(161.6, -13.9), 0.213, 0.00, 0.364, 0.523, 4.45, 2.46);
    star(vec2(69.1, -159.6), 0.115, 0.00, 0.273, 0.404, 5.65, 0.63);
    star(vec2(-157.5, -79.1), 0.197, 0.00, 0.349, 0.504, 5.79, 2.56);
    star(vec2(149.1, 127.5), 0.161, 0.00, 0.316, 0.460, 3.45, 0.82);
    star(vec2(-36.2, 155.6), 0.110, 0.00, 0.268, 0.399, 2.90, 4.81);
    star(vec2(-119.8, 61.3), 0.080, 0.00, 0.236, 0.357, 3.95, 5.31);
    star(vec2(163.4, -154.9), 0.167, 0.00, 0.321, 0.467, 4.38, 5.30);
    star(vec2(168.0, -175.1), 0.137, 0.00, 0.293, 0.431, 3.83, 3.60);
    star(vec2(54.1, -274.2), 0.107, 0.00, 0.265, 0.395, 6.01, 0.87);
    star(vec2(134.2, 158.8), 0.409, 0.00, 0.547, 0.761, 4.98, 5.65);
    star(vec2(136.8, -245.2), 0.080, 0.00, 0.213, 0.327, 3.61, 3.01);
    star(vec2(168.4, 71.2), 0.155, 0.00, 0.310, 0.453, 2.93, 0.37);
    star(vec2(111.6, 23.5), 0.390, 0.00, 0.530, 0.738, 3.12, 3.43);
    star(vec2(48.2, -137.4), 0.261, 0.00, 0.409, 0.581, 5.93, 3.02);
    star(vec2(-84.8, -219.7), 0.121, 0.00, 0.278, 0.411, 3.59, 2.06);
    star(vec2(41.5, -282.8), 0.357, 0.00, 0.499, 0.698, 5.78, 0.15);
    star(vec2(9.2, 130.8), 0.080, 0.00, 0.217, 0.332, 3.90, 5.71);
    star(vec2(8.3, 145.7), 0.080, 0.00, 0.201, 0.311, 4.50, 4.96);
    star(vec2(167.2, 168.6), 0.307, 0.00, 0.452, 0.638, 4.89, 3.98);
    star(vec2(-59.2, -168.7), 0.202, 0.00, 0.354, 0.510, 2.99, 1.63);
    star(vec2(-138.4, 5.6), 0.161, 0.00, 0.316, 0.460, 5.54, 2.32);
    star(vec2(92.1, -151.8), 0.080, 0.00, 0.211, 0.325, 3.14, 4.05);
    star(vec2(136.2, -131.9), 0.628, 0.45, 0.751, 1.000, 5.50, 0.56);
    star(vec2(153.6, 25.8), 0.110, 0.00, 0.268, 0.399, 3.24, 0.05);
    star(vec2(-13.6, 117.7), 0.080, 0.00, 0.210, 0.323, 3.02, 2.87);
    star(vec2(134.2, 108.8), 0.128, 0.00, 0.284, 0.420, 4.22, 1.04);
    star(vec2(-64.8, -279.3), 0.080, 0.00, 0.223, 0.339, 5.59, 1.15);
    star(vec2(-84.2, 145.5), 0.146, 0.00, 0.302, 0.443, 4.90, 4.27);
    star(vec2(-22.8, -203.1), 0.222, 0.00, 0.372, 0.534, 5.05, 5.80);
    star(vec2(-45.1, -156.6), 0.362, 0.00, 0.503, 0.704, 3.40, 0.16);
    star(vec2(2.3, -160.7), 0.268, 0.00, 0.416, 0.590, 3.74, 4.00);
    star(vec2(-171.8, -240.7), 0.094, 0.00, 0.253, 0.379, 3.92, 5.24);
    star(vec2(113.2, 184.9), 0.080, 0.00, 0.227, 0.345, 6.16, 1.66);
    star(vec2(-178.0, -143.2), 0.432, 0.00, 0.569, 0.789, 4.57, 2.80);
    star(vec2(42.8, -267.1), 0.270, 0.00, 0.417, 0.592, 3.47, 2.96);
    star(vec2(-136.1, 101.7), 0.108, 0.00, 0.266, 0.396, 2.99, 2.82);
    star(vec2(102.4, -57.1), 0.215, 0.00, 0.366, 0.526, 5.20, 0.72);
    star(vec2(-175.2, -79.5), 0.125, 0.00, 0.282, 0.417, 4.39, 3.71);
    star(vec2(175.9, -187.0), 0.314, 0.00, 0.458, 0.646, 4.26, 5.09);
    star(vec2(-179.3, -291.2), 0.203, 0.00, 0.355, 0.511, 2.97, 2.54);

    fragColor = vec4(sqrt(min(dimSum, 1.0)), sqrt(min(litSum, 1.0)), bestPhase / 6.2831853, clamp((bestPeriod - 2.8) / 3.4, 0.0, 1.0));
}
