// SPDX-License-Identifier: GPL-3.0-only
#version 440
// Sidebar edge treatment ported from DockOver's settings sidebar
// (experiments/liquid-glass-27/glass27.hlsl, SidebarGlass). Only the boundary
// facing the content pane is an exposed glass edge: the hue of the adjacent
// content bleeds in over ~13 pt, a hairline catches the light and a faint
// dark line separates the rail from the content.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float glowWidth;   // item width in pt (x = 1 is the content seam)
    float sampleWidth; // pt of content captured into glowSource
    float dark;        // 1 = dark appearance
};
layout(binding = 1) uniform sampler2D glowSource;
const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);
void main() {
    float inside = (1.0 - qt_TexCoord0.x) * glowWidth;
    // DockOver samples the blurred content 15 pt past the seam on the same row.
    vec4 adjacent = texture(glowSource, vec2(clamp(15.0 / max(sampleWidth, 1.0), 0.0, 1.0), qt_TexCoord0.y));
    vec3 rgb = adjacent.a > 0.0 ? adjacent.rgb / adjacent.a : vec3(0.0);
    vec3 hue = rgb - dot(rgb, kLuma);
    bool isDark = dark > 0.5;
    // Additive light (premultiplied, alpha 0) + the dark hairline (alpha only).
    vec3 light = exp(-inside / 13.0) * (hue * 0.12 + 0.029 * (isDark ? 1.0 : 0.65));
    light += exp(-inside / 0.85) * (isDark ? 0.026 : 0.012);
    float line = exp(-abs(inside - 1.0) / 0.75) * (isDark ? 0.055 : 0.018);
    // Sub-LSB dithering prevents contour bands after 8-bit compositing.
    float noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715)))) - 0.5;
    light += vec3(noise / 255.0) * exp(-inside / 13.0);
    fragColor = vec4(light, line) * qt_Opacity;
}
