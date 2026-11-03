// SPDX-License-Identifier: GPL-3.0-only
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf { mat4 qt_Matrix; float qt_Opacity; };
layout(binding = 1) uniform sampler2D glowSource;
void main() {
    // Mirror CONTENT only. Coverage is exactly zero at the left edge and
    // rises gently towards the content seam, with no full-sidebar colour wash.
    float fade = smoothstep(0.0, 1.0, qt_TexCoord0.x);
    fade *= fade;
    vec4 colour = texture(glowSource, vec2(1.0-qt_TexCoord0.x, qt_TexCoord0.y));
    // Sub-LSB spatial dithering prevents contour bands after desktop 8-bit
    // compositing; fade also removes noise outside the edge treatment.
    float noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056,0.00583715))))-0.5;
    colour.rgb = clamp(colour.rgb + vec3(noise/255.0)*colour.a, vec3(0.0), vec3(colour.a));
    fragColor = colour * (fade * qt_Opacity);
}
