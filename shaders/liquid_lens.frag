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
  float edge = 1.0 - smoothstep(0.0, 9.0, max(inside, 0.0));
  // The rim compresses the scene inward; the readable center stays undistorted.
  vec2 refracted = texturePoint - normal * (3.8 * edge * edge * u_scale);
  // The inner Gaussian filter already scatters the scene. A single displaced
  // sample avoids text ghosting and redundant full-resolution texture reads.
  vec4 scene = sampleBackdrop(refracted);
  // Adapt tint to the sampled scene, retaining its hue while protecting text.
  float luma = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 base = mix(vec3(0.980, 0.988, 1.0), vec3(0.125, 0.149, 0.188), u_dark);
  float lightFill = mix(0.86, 0.18, smoothstep(0.25, 0.80, luma));
  float darkFill = mix(0.28, 0.88, smoothstep(0.10, 0.75, luma));
  vec3 glass = mix(scene.rgb, base, mix(lightFill, darkFill, u_dark));
  fragColor = vec4(glass, 1.0);
}
