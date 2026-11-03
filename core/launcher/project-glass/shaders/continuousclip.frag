// SPDX-License-Identifier: GPL-3.0-only
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;
    vec2 surfaceSize;
    float rimWidth;
    vec4 rimColor;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec2 size = max(surfaceSize, vec2(1.0));
    float extent = min(radius * 1.5, min(size.x, size.y) * 0.5);
    float coverage = 1.0;
    float rim = 0.0;
    if (extent > 0.0) {
        vec2 q = max(abs(qt_TexCoord0 * size - size * 0.5) - size * 0.5 + extent, vec2(0.0)) / extent;
        // Cubic superellipse: zero curvature where each corner meets a line.
        float d = (pow(q.x*q.x*q.x + q.y*q.y*q.y, 1.0/3.0) - 1.0) * extent;
        float aa = max(fwidth(d), 0.0001);
        coverage = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, d);
        if (rimWidth > 0.0) rim = smoothstep(-rimWidth - 0.5 * aa, -rimWidth + 0.5 * aa, d);
    }
    vec4 color = texture(source, qt_TexCoord0);
    color.rgb = color.rgb * (1.0 - rimColor.a * rim) + rimColor.rgb * rim * color.a;
    fragColor = color * (coverage * qt_Opacity);
}
