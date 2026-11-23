#version 460 core
#include <flutter/runtime_effect.glsl>

// ImageFilter supplies the first vec2 and sampler. Coordinates are physical
// texture pixels; the remaining geometry is expressed in logical Flutter dp.
uniform vec2 u_textureSize;
uniform vec2 u_logicalSize;
uniform float u_radius;
uniform float u_dark;
uniform vec2 u_origin;
uniform float u_scale;
uniform sampler2D u_background;
out vec4 fragColor;

float roundedBox(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

vec4 sampleBackdrop(vec2 texturePoint) {
  vec2 uv = clamp(texturePoint / u_textureSize, vec2(0.001), vec2(0.999));
  return texture(u_background, uv);
}

void main() {
  // A backdrop texture can contain the whole scene. Never normalize the
  // panel's dp bounds to the texture: that shrinks unrelated content into it.
  vec2 texturePoint = FlutterFragCoord().xy;
  vec2 p = texturePoint / u_scale - u_origin;
  vec2 halfSize = u_logicalSize * 0.5;
  float r = min(u_radius, min(halfSize.x, halfSize.y));
  vec2 centered = p - halfSize;
  vec2 q = abs(centered) - halfSize + r;
  vec2 cornerNormal = normalize(max(q, vec2(0.0)) + vec2(0.0001));
  vec2 faceNormal = q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec2 normal = (max(q.x, q.y) > 0.0 ? cornerNormal : faceNormal) * sign(centered);
  float inside = -roundedBox(centered, halfSize, r);
  float edge = 1.0 - smoothstep(0.0, 10.0, max(inside, 0.0));
  // Apple Liquid Glass lens bend: refracts scrolling color inward along the
  // rounded capsule rim while keeping center text distortion-free.
  vec2 refracted = texturePoint - normal * (3.6 * edge * edge * u_scale);
  vec4 scene = sampleBackdrop(refracted);
  float luma = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 chroma = scene.rgb - vec3(luma);
  // Preserve and gently enrich backdrop saturation (like CSS saturate(170%))
  // while softly compressing luminance extremes for crisp foreground legibility.
  float lightLuma = mix(0.76, 0.98, luma);
  float darkLuma = mix(0.08, 0.26, luma);
  vec3 lightGlass = clamp(vec3(lightLuma) + chroma * 0.65, 0.0, 1.0);
  vec3 darkGlass = clamp(vec3(darkLuma) + chroma * 0.72, 0.0, 1.0);
  vec3 glass = mix(lightGlass, darkGlass, u_dark);
  vec3 rimChroma = clamp(vec3(mix(lightLuma, darkLuma, u_dark)) + chroma * 1.15, 0.0, 1.0);
  // Bright Fresnel optical glint along the top-left rim.
  float topLight = clamp((-normal.y * 0.7 - normal.x * 0.3) * 0.5 + 0.5, 0.0, 1.0);
  glass = mix(glass, rimChroma, 0.35 * edge * edge);
  glass += vec3(mix(0.14, 0.10, u_dark)) * edge * edge * edge * topLight;
  fragColor = vec4(clamp(glass, 0.0, 1.0), 1.0);
}
