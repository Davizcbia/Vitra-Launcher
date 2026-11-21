// SPDX-License-Identifier: GPL-3.0-only
// A ring just inside a continuous-corner contour: the same superellipse as
// continuousclip.frag, so it follows a clipped card's edge exactly.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;
    vec2 surfaceSize;
    float ringWidth;
    vec4 ringColor;
};
void main() {
    vec2 size = max(surfaceSize, vec2(1.0));
    float extent = max(min(radius * 1.5, min(size.x, size.y) * 0.5), 0.0001);
    vec2 q = max(abs(qt_TexCoord0 * size - size * 0.5) - size * 0.5 + extent, vec2(0.0)) / extent;
    // Distance-like value: 0 on the contour, negative inside.
    float d = (pow(q.x*q.x*q.x + q.y*q.y*q.y, 1.0/3.0) - 1.0) * extent;
    // Straight edges: the plain distance to the nearest side.
    vec2 p = abs(qt_TexCoord0 * size - size * 0.5) - size * 0.5;
    d = max(d, max(p.x, p.y));
    float aa = max(fwidth(d), 0.0001);
    float inside = 1.0 - smoothstep(-0.5 * aa, 0.5 * aa, d);
    float band = smoothstep(-ringWidth - 0.5 * aa, -ringWidth + 0.5 * aa, d);
    // Premultiplied output.
    fragColor = vec4(ringColor.rgb * ringColor.a, ringColor.a) * (inside * band * qt_Opacity);
}
