#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uOpacity;
uniform float uPixelRatio;
uniform float uTitleShade;
uniform float uUniform;
uniform vec3 uUniformColor;
uniform float uCached;
uniform sampler2D uFrame;
uniform sampler2D uCore;
uniform sampler2D uHalo;
out vec4 fragColor;

vec2 gaussian(vec2 distance, vec2 sigma) {
  vec2 normalized = distance / sigma;
  return exp(-0.5 * normalized * normalized) / (2.50662827463 * sigma);
}
float normalCdf(float value) {
  float x = abs(value);
  float t = 1.0 / (1.0 + 0.2316419 * x);
  float tail = 0.3989422804 * exp(-0.5 * x * x) * t *
      (0.319381530 + t * (-0.356563782 + t * (1.781477937 +
      t * (-1.821255978 + t * 1.330274429))));
  return value < 0.0 ? tail : 1.0 - tail;
}
float rectangle(vec2 position, float sigma) {
  return (normalCdf(position.x / sigma) - normalCdf((position.x - 16.0) / sigma)) *
      (normalCdf(position.y / sigma) - normalCdf((position.y - 16.0) / sigma));
}
void main() {
  vec2 point = FlutterFragCoord().xy;
  float core = min(uSize.x, uSize.y);
  float cover = max(uSize.x, uSize.y);
  vec2 center = point - uSize * 0.5;
  vec2 corePosition = center * (16.0 / core) + 8.0;
  vec2 coverPosition = center * (16.0 / cover) + 8.0;
  float coverSigma = 40.0 * 16.0 / cover;
  vec3 light = vec3(0.0);
  if (uUniform > 0.5) {
    // Beat Pulse and other full-panel frames have an analytic Gaussian result:
    // no matrix texture gathers and no quantized intermediate blur layers.
    light = uUniformColor * (rectangle(corePosition, 0.8) +
        0.65 * rectangle(coverPosition, coverSigma));
  } else if (uCached > 0.5) {
    // Float textures contain separable Gaussian fields, never rounded RGB8.
    // Nodes include endpoints; map them to texel centers for linear sampling.
    vec2 coreUv = ((corePosition + 4.0) / 24.0 * 255.0 + 0.5) / 256.0;
    vec2 haloUv = (coverPosition / 16.0 * 127.0 + 0.5) / 128.0;
    if (all(greaterThanEqual(corePosition, vec2(-4.0))) &&
        all(lessThanEqual(corePosition, vec2(20.0)))) {
      light = texture(uCore, coreUv).rgb;
    }
    light += 0.65 * texture(uHalo, haloUv).rgb;
  } else {
    vec2 sigma = vec2(0.8, coverSigma);
    vec2 positionX = vec2(corePosition.x, coverPosition.x);
    vec2 positionY = vec2(corePosition.y, coverPosition.y);
    vec2 weightsX[16];
    vec2 weightsY[16];
    for (int i = 0; i < 16; i++) {
      weightsX[i] = gaussian(vec2(float(i) + 0.5) - positionX, sigma);
      weightsY[i] = gaussian(vec2(float(i) + 0.5) - positionY, sigma);
    }
    // Source-cell centers: nearest sampling is intentional. Gaussian weights
    // reconstruct the continuous field without paired taps or extra glow lobes.
    for (int y = 0; y < 16; y++) {
      if (weightsY[y].x + weightsY[y].y < 0.00001) continue;
      for (int x = 0; x < 16; x++) {
        float weight = dot(weightsX[x] * weightsY[y], vec2(1.0, 0.65));
        if (weight < 0.00001) continue;
        light += texture(uFrame, (vec2(float(x), float(y)) + 0.5) / 16.0).rgb * weight;
      }
    }
  }
  light *= clamp(uOpacity, 0.0, 1.0);
  float shade = 1.0;
  if (uTitleShade > 0.5) {
    float t = clamp(point.y / uSize.y, 0.0, 1.0);
    float alpha;
    if (t < 0.35) alpha = mix(166.0, 153.0, t / 0.35);
    else if (t < 0.75) alpha = mix(153.0, 0.0, (t - 0.35) / 0.4);
    else alpha = mix(0.0, 34.0, (t - 0.75) / 0.25);
    shade = 1.0 - alpha / 255.0;
  }
  vec3 color = clamp(vec3(16.0 / 255.0) + light, 0.0, 1.0) * shade;
  vec2 pixel = floor(point * max(0.01, uPixelRatio));
  float noise = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715)))) - 0.5;
  // Dither the continuous value BEFORE its only final quantization. Grain added
  // after 8-bit blur/title layers cannot remove their stepped local means.
  // The caller bypasses all-black and zero-opacity frames. In an emitting
  // frame, the matte/title gradient also needs dither in its dark margins.
  color += noise * (2.0 / 255.0);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
