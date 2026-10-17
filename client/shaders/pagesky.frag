#version 440
// The night behind every page but the home one (HomeScene draws its own) and behind the sheets
// (DrawerType2), from the owner's design (local-tools/design/app/screens.html in the service repo):
//  - a page (sheet 0): the home screen's sky without its land - homesky.frag's gradient, darkest
//    overhead, lighter towards the horizon, which is under the bottom edge, as if the hills were just
//    below - and its darkening towards the sides. No stars: on the pages a star means something (the
//    chosen server, this device)
//  - a sheet (sheet 1): the update sheet's sky (updatesky.frag without its route) - the connect
//    button's lit colours, a pool of light at the top, darker towards the sides
// Dithered against banding in the dark gradients. It never moves: its items draw it once (layer).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float pixel;        // one device pixel in item units (1 / devicePixelRatio)
    float sheet;        // 0 a page's sky, 1 a sheet's
    float corner;       // a sheet's top corners' radius
};

const vec3 NIGHT_TOP = vec3(4.0, 7.0, 19.0) / 255.0;
const vec3 NIGHT_MID = vec3(8.0, 13.0, 34.0) / 255.0;
const vec3 NIGHT_LOW = vec3(17.0, 25.0, 60.0) / 255.0;
const vec3 TOP_LIT = vec3(14.0, 24.0, 68.0) / 255.0;
const vec3 BOTTOM_LIT = vec3(4.0, 7.0, 24.0) / 255.0;
const vec3 SKY_LIGHT = vec3(34.0, 62.0, 170.0) / 255.0;

float gauss2(float d2, float sigma) {
    return exp(-d2 / (2.0 * sigma * sigma));
}

float hash(vec2 v) {
    return fract(52.9829189 * fract(dot(v, vec2(0.06711056, 0.00583715))));
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float v = qt_TexCoord0.y;
    float sx = abs(qt_TexCoord0.x - 0.5) * 2.0;

    vec3 page = mix(NIGHT_TOP, NIGHT_MID, smoothstep(0.0, 0.5, v));
    page = mix(page, NIGHT_LOW, smoothstep(0.48, 1.08, v));
    page *= 1.0 - 0.22 * sx * sx * sx;

    vec3 sh = mix(TOP_LIT, BOTTOM_LIT, clamp(v * 0.9 + 0.05, 0.0, 1.0)) * (1.0 - 0.22 * sx * sx * sx);
    vec2 d = p - vec2(itemSize.x * 0.5, -40.0);
    sh = mix(sh, SKY_LIGHT, clamp(gauss2(dot(d, d), 150.0) * 0.22, 0.0, 1.0));
    sh *= 1.0 - 0.25 * smoothstep(0.55, 1.0, sx);

    vec3 col = mix(page, sh, sheet);
    col += (hash(gl_FragCoord.xy) - 0.5) / 255.0;

    // a sheet's rounded top corners
    float alpha = 1.0;
    if (corner > 0.0) {
        vec2 q = vec2(min(p.x, itemSize.x - p.x), p.y);
        if (q.x < corner && q.y < corner) {
            alpha = clamp((corner - length(vec2(corner) - q)) / pixel + 0.5, 0.0, 1.0);
        }
    }
    fragColor = vec4(clamp(col, 0.0, 1.0) * alpha, alpha) * qt_Opacity;
}
