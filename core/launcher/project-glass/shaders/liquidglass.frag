// SPDX-License-Identifier: GPL-3.0-only
// Project Glass: original rounded lens, local geometry / window-space sampling.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewportSize;
    vec2 surfaceSize;
    vec2 sharpTextureSize;
    vec2 blurredTextureSize;
    vec4 panelRect;
    float cornerRadius;
    float circularShape;
    vec4 shapeA;
    vec4 shapeB;
    vec4 fusionConfig;
    float darkAppearance;
    float blurStrength;
    float reduceTransparency;
    vec4 tintColor;
    vec4 strokeColor;
    float strokeWidth;
    float materialDensity;
    float refractionStrength;
    float glareStrength;
    vec4 interaction;
    vec4 optics; // index, bevel width, dispersion, magnification
    vec4 lighting; // Fresnel, specular, edge, light angle (radians)
    vec4 appearance; // saturation, brightness, shadow, reserved
    vec2 touch; // strength, radius
    float refractionDirection;
    vec4 capsuleConfig;
    vec4 capsuleOne;
    vec4 capsuleTwo;
    vec4 capsuleThree;
    vec4 capsuleFour;
    vec4 capsuleFive;
    float flatBevel; // 1 = pressed lens: squeezed backdrop, drawn rim
    float foregroundAmount; // 1 = foregroundSource is seen through the lens
    float foregroundBevel; // width of the band that bends foregroundSource
};
layout(binding = 1) uniform sampler2D sharpSource;
layout(binding = 2) uniform sampler2D blurredSource;
layout(binding = 3) uniform sampler2D foregroundSource;
float roundedDistance(vec2 p, vec2 halfSize, float radius) {
    float r = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    if (r < 0.01) { vec2 q=abs(p)-halfSize; return length(max(q,vec2(0)))+min(max(q.x,q.y),0.0); }
    float capsule = smoothstep(0.85, 1.0, r / max(min(halfSize.x,halfSize.y),0.01));
    float extent = min(r * mix(1.5,1.0,capsule), min(halfSize.x,halfSize.y));
    float power = mix(3.0,2.2,capsule);
    vec2 q = abs(p) - halfSize + extent;
    vec2 v = max(q,vec2(0)) / extent;
    float norm = pow(pow(v.x,power)+pow(v.y,power),1.0/power);
    return (norm-1.0)*extent + min(max(q.x,q.y),0.0);
}
float distanceToPanel(vec2 p, vec2 halfSize, float radius) {
    if (capsuleConfig.x > 0.5) {
        vec4 shapes[5] = vec4[5](capsuleOne, capsuleTwo, capsuleThree, capsuleFour, capsuleFive);
        vec2 local = p + halfSize;
        float d = 10000.0;
        for (int i=0; i<5; ++i) {
            if (float(i) >= capsuleConfig.x) break;
            vec4 s = shapes[i];
            // An empty capsule is a point at the origin; fusing with it grows a horn.
            if (s.z < 0.01 || s.w < 0.01) continue;
            float b = roundedDistance(local-s.xy-s.zw*0.5, s.zw*0.5, s.w*0.5);
            bool neighbour = abs(float(i)-capsuleConfig.z)<0.1 || abs(float(i-1)-capsuleConfig.z)<0.1;
            float k = neighbour ? capsuleConfig.y*capsuleConfig.w : 0.0;
            if (i>0 && k>0.001) {
                float h = max(k-abs(d-b),0.0)/k;
                d = min(d,b)-h*h*k*0.25;
            } else d = min(d,b);
        }
        return d;
    }
    if (fusionConfig.x > 0.5) {
        vec2 local = p + halfSize;
        float a = roundedDistance(local-shapeA.xy-shapeA.zw*0.5,shapeA.zw*0.5,fusionConfig.z);
        float b = length(local-shapeB.xy-shapeB.zw*0.5)-shapeB.z*0.5;
        float k = fusionConfig.y;
        float h = max(k-abs(a-b),0.0)/k;
        return min(a,b)-h*h*k*0.25;
    }
    if (circularShape > 0.5) return length(p)-min(halfSize.x,halfSize.y);
    return roundedDistance(p,halfSize,radius);
}
void main() {
    vec2 size = max(surfaceSize, vec2(1));
    vec2 localPixel = qt_TexCoord0 * (size + vec2(24.0)) - vec2(12.0);
    vec2 screenScale = panelRect.zw / size;
    vec2 screenUV = (panelRect.xy + localPixel * screenScale) / max(viewportSize, vec2(1.0));
    vec2 p = localPixel - size * 0.5;
    float radius = min(cornerRadius, min(size.x,size.y)*0.5);
    float d = distanceToPanel(p,size*0.5,radius);
    float aa = max(fwidth(d),0.65);
    float coverage = 1.0-smoothstep(-aa,aa,d);
    // Separate contact and diffuse shadows give the thin material some lift.
    float shadowDistance = distanceToPanel(p - vec2(0.0, 2.0), size * 0.5, radius);
    float shadow = (0.045 * exp(-max(shadowDistance, 0.0) / 2.0)
                  + 0.018 * exp(-max(shadowDistance, 0.0) / 3.0));
    shadow *= 1.0 - smoothstep(7.0, 11.0, max(d, 0.0));
    shadow *= appearance.z;
    float outsideShadow = shadow * (1.0 - coverage);
    if (coverage <= 0.0) {
        fragColor = vec4(0.0, 0.0, 0.0, outsideShadow * qt_Opacity);
        return;
    }
    if (reduceTransparency > 0.5) {
        vec3 solid = mix(vec3(0.94), vec3(0.12), darkAppearance);
        float edge = strokeWidth > 0.0 ? smoothstep(-strokeWidth-aa, -strokeWidth+aa, d) : 0.0;
        solid = strokeColor.rgb * edge + solid * (1.0 - strokeColor.a * edge);
        fragColor = vec4(solid * coverage, coverage + outsideShadow) * qt_Opacity;
        return;
    }
    vec2 normal = normalize(vec2(
        distanceToPanel(p+vec2(0.5,0),size*0.5,radius)-distanceToPanel(p-vec2(0.5,0),size*0.5,radius),
        distanceToPanel(p+vec2(0,0.5),size*0.5,radius)-distanceToPanel(p-vec2(0,0.5),size*0.5,radius)) + vec2(0.00001));
    float inside = max(-d,0.0);
    float bevel = min(optics.y, min(size.x, size.y) * 0.30);
    float t = clamp(inside / max(bevel, 1.0), 0.0, 1.0);
    float rim = 1.0 - smoothstep(0.0, 1.0, t);
    // Circular bevel normal. Flat centres have zero lateral refraction.
    // Ease the join into the flat centre; avoid a visible ring at the bevel end.
    float lateral = 1.0 - t * t * (3.0 - 2.0 * t);
    float vertical = sqrt(max(0.0, 1.0 - lateral * lateral));
    // Press increases lens depth near the pointer, without moving the label
    // or changing the control's hit region. No idle/time-driven animation.
    vec2 pointerDelta = localPixel - interaction.xy;
    float pointerFalloff = exp(-dot(pointerDelta, pointerDelta) / (2.0 * touch.y * touch.y)) * touch.x;
    float pressure = interaction.w * pointerFalloff;
    // A local depression changes the optical normal, including the flat face.
    // Pointer easing supplies the viscous lag; no continuously ticking shader.
    vec2 touchSlope = pointerDelta / touch.y * pointerFalloff
                    * (0.045 * interaction.z + 0.16 * interaction.w);
    vec3 surfaceNormal = normalize(vec3(normal * lateral + touchSlope, max(vertical, 0.03)));
    vec3 ray = refract(vec3(0.0, 0.0, -1.0), surfaceNormal, 1.0 / optics.x);
    float lensDepth = min(bevel * 1.8, 26.0) * refractionStrength;
    vec2 displacement = ray.xy / max(-ray.z, 0.15) * lensDepth * (1.0 + 0.25 * pressure) * refractionDirection;
    vec2 halfTexel = 0.5 / max(sharpTextureSize, vec2(1));
    vec2 zoomOffset = (localPixel-size*0.5) * (1.0/optics.w-1.0);
    // A pressed lens squeezes what is behind it vertically and enlarges it
    // sideways: the bar looks lower inside the lens, its contents bigger.
    zoomOffset.x *= 1.0 - 1.36 * flatBevel;
    vec2 uv = clamp(screenUV + (displacement+zoomOffset) * screenScale / max(viewportSize, vec2(1)), halfTexel, vec2(1.0) - halfTexel);
    vec2 dispersion = displacement * optics.z * screenScale / max(viewportSize, vec2(1));
    vec3 clearColor = vec3(
        texture(sharpSource, clamp(uv + dispersion, halfTexel, vec2(1.0) - halfTexel)).r,
        texture(sharpSource, uv).g,
        texture(sharpSource, clamp(uv - dispersion, halfTexel, vec2(1.0) - halfTexel)).b);
    vec2 blurHalfTexel = 0.5 / max(blurredTextureSize, vec2(1));
    vec3 frost = texture(blurredSource, clamp(uv, blurHalfTexel, vec2(1)-blurHalfTexel)).rgb;
    // Diffuse the centre strongly enough to suppress readable background
    // text, while leaving a narrow refracting rim and a true clear endpoint.
    float frostMix = 1.0 - pow(1.0 - clamp(blurStrength, 0.0, 1.0), 2.0);
    vec3 col = mix(clearColor, frost, frostMix * (1.0 - 0.30 * rim));
    float backdropLuma = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(backdropLuma), col, appearance.x) * appearance.y;
    // Neutral dark glass remains distinct over black, while retaining colour
    // from the content behind it instead of adding a blue wash.
    vec3 tint = mix(vec3(0.98), vec3(0.12), darkAppearance);
    float density = clamp(materialDensity, 0.0, 1.0);
    col = mix(col, tint, mix(0.24 + 0.26 * density, 0.40 + 0.28 * density, darkAppearance));
    vec3 controlTint = tintColor.a > 0.001 ? tintColor.rgb / tintColor.a : tint;
    col = mix(col, controlTint, tintColor.a * 0.22);
    // Labels under the lens: not tinted or scaled, so the flat centre stays
    // 1:1 sharp, while the bevel bends them and splits their colours.
    if (foregroundAmount > 0.001) {
        // Its own band: wider than the bevel, which stays clear of the bar's
        // edges. Under half the height, or labels on the centre line would tear.
        float labelBevel = min(foregroundBevel, min(size.x, size.y) * 0.45);
        float labelT = clamp(inside / max(labelBevel, 1.0), 0.0, 1.0);
        float labelLateral = 1.0 - labelT * labelT * (3.0 - 2.0 * labelT);
        vec3 labelNormal = normalize(vec3(normal * labelLateral, max(sqrt(max(0.0, 1.0 - labelLateral * labelLateral)), 0.03)));
        vec3 labelRay = refract(vec3(0.0, 0.0, -1.0), labelNormal, 1.0 / optics.x);
        vec2 labelShift = labelRay.xy / max(-labelRay.z, 0.15) * min(labelBevel * 1.8, 26.0) * refractionStrength * refractionDirection;
        vec2 bend = labelShift * screenScale / max(viewportSize, vec2(1));
        // Wider than a glyph's stroke, the channels part into colour blocks;
        // the limit follows the dispersion setting so that it stays adjustable.
        vec2 labelFringe = labelShift * optics.z * 3.0;
        labelFringe *= min(1.0, (0.8 + 16.0 * optics.z) / max(length(labelFringe), 0.001));
        vec2 fringe = labelFringe * screenScale / max(viewportSize, vec2(1));
        vec4 fgR = texture(foregroundSource, clamp(screenUV + bend + fringe, halfTexel, vec2(1.0) - halfTexel));
        vec4 fgG = texture(foregroundSource, clamp(screenUV + bend, halfTexel, vec2(1.0) - halfTexel));
        vec4 fgB = texture(foregroundSource, clamp(screenUV + bend - fringe, halfTexel, vec2(1.0) - halfTexel));
        vec3 fgAlpha = vec3(fgR.a, fgG.a, fgB.a) * foregroundAmount;
        col = col * (1.0 - fgAlpha) + vec3(fgR.r, fgG.g, fgB.b) * foregroundAmount;
    }
    vec2 pointerDirection = normalize((interaction.xy - size * 0.5) / max(size, vec2(1)) + vec2(0.00001, -0.25));
    vec2 baseLight = vec2(cos(lighting.w), sin(lighting.w));
    vec2 lightDirection = normalize(mix(baseLight, pointerDirection, clamp(interaction.z * touch.x * 0.55,0.0,0.95)));
    float light = pow(max(dot(normal, lightDirection), 0.0), 3.0);
    float counter = pow(max(dot(normal, -baseLight), 0.0), 4.0);
    float fresnel = 0.034 + 0.966 * pow(1.0 - vertical, 5.0);
    float luminance = dot(col, vec3(0.2126, 0.7152, 0.0722));
    // Background-aware contrast: bright edges over dark images, a restrained
    // inner shade over bright images. No theme-coloured wash over the material.
    float highlightRoom = mix(1.0, 0.48, smoothstep(0.25, 0.9, luminance));
    // Reading panels use a quieter rim than floating buttons and navigation.
    highlightRoom *= mix(1.0, 0.5, density);
    col += vec3(fresnel * rim * (0.44 * light + 0.10 * counter) * highlightRoom * glareStrength * lighting.x);
    // Two broad light sources produce moving specular lobes on the bevel.
    // Keep the centre clear and highlights neutral after tinting.
    vec3 keyHalf = normalize(normalize(vec3(lightDirection * 0.9, 0.7)) + vec3(0,0,1));
    vec3 fillHalf = normalize(normalize(vec3(-lightDirection * 0.65, 0.9)) + vec3(0,0,1));
    float specular = pow(max(dot(surfaceNormal, keyHalf), 0.0), 38.0)
                   + 0.28 * pow(max(dot(surfaceNormal, fillHalf), 0.0), 22.0);
    // Keep illumination at the silhouette. A specular band across the bevel,
    // followed by an inset shade/shoulder, reads as a second nested glass shell.
    float edgeLight = exp(-inside / 1.1);
    col += vec3(specular * edgeLight * glareStrength * 0.16 * highlightRoom * lighting.y);
    float outline = exp(-abs(d + 0.35) * 2.8);
    col += vec3(outline * (0.014 + glareStrength * (0.18 * light + 0.04 * counter)) * highlightRoom * lighting.z);
    // A soft, directional reflection across the glass body keeps the centre
    // translucent while giving the surface depth on flat backgrounds.
    float topReflection = pow(1.0 - clamp(localPixel.y / size.y, 0.0, 1.0), 2.0);
    col += vec3(topReflection * mix(0.012, 0.006, darkAppearance) * highlightRoom);
    col += vec3(pointerFalloff * interaction.z * (0.008 + 0.025 * edgeLight) * highlightRoom);
    col += vec3(pressure * edgeLight * 0.018 * highlightRoom);
    // Pressed rim: a thin spectral fringe, a dark contour and a light inner line.
    if (flatBevel > 0.001) {
        vec3 spectrum = 0.5 + 0.5 * cos(6.2832 * (p.x / size.x * 3.2 + p.y / size.y * 1.4 + vec3(0.0, 0.33, 0.67)));
        col += spectrum * exp(-abs(d + 3.0) * 0.9) * 0.07 * flatBevel;
        col *= 1.0 - flatBevel * 0.7 * exp(-abs(d + 0.6) * 1.5);
        col += vec3(flatBevel * 0.09 * exp(-abs(d + 2.2) * 1.1));
    }
    float stroke = strokeWidth > 0.0 ? smoothstep(-strokeWidth-aa, -strokeWidth+aa, d) : 0.0;
    col = strokeColor.rgb * stroke + col * (1.0 - strokeColor.a * stroke);
    float alpha = coverage + outsideShadow;
    fragColor = vec4(clamp(col, 0.0, 1.0) * coverage, alpha) * qt_Opacity;
}
