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
  float edge = 1.0 - smoothstep(0.0, 8.0, max(inside, 0.0));
  // The rim compresses the scene inward; the readable center stays undistorted.
  vec2 refracted = texturePoint - normal * (3.0 * edge * edge * u_scale);
  // The inner Gaussian filter already scatters the scene. A single displaced
  // sample avoids text ghosting and redundant full-resolution texture reads.
  vec4 scene = sampleBackdrop(refracted);
  // Keep transmission neutral and monotonic. The material's tint and diffusion
  // supply readability; the shader only compresses contrast and bends the rim.
  float luma = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 chroma = scene.rgb - vec3(luma);
  float lightLuma = mix(0.69, 0.95, luma);
  float darkLuma = mix(0.06, 0.21, luma);
  vec3 lightGlass = vec3(lightLuma) + chroma * 0.12;
  vec3 darkGlass = vec3(darkLuma) + chroma * 0.14;
  vec3 glass = mix(lightGlass, darkGlass, u_dark);
  vec3 transmitted = vec3(luma) + chroma * 0.26;
  // A narrow, slightly clearer edge reveals the actual refracted backdrop.
  glass = mix(glass, transmitted, 0.12 * edge * edge);
  fragColor = vec4(glass, 1.0);
}
