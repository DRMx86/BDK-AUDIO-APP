#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uOutputSize;
uniform float uMinimum;
uniform float uSpan;
uniform float uSigma;
uniform float uVertical;
uniform sampler2D uSource;
out vec4 fragColor;

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  bool vertical = uVertical > 0.5;
  float count = vertical ? uOutputSize.y : uOutputSize.x;
  float node = (vertical ? pixel.y : pixel.x) - 0.5;
  float position = uMinimum + node * uSpan / (count - 1.0);
  vec3 light = vec3(0.0);
  for (int i = 0; i < 16; i++) {
    float distance = (position - float(i) - 0.5) / uSigma;
    float weight = exp(-0.5 * distance * distance) /
        (2.506628274631 * uSigma);
    vec2 uv = vertical
        ? vec2(pixel.x / uOutputSize.x, (float(i) + 0.5) / 16.0)
        : vec2((float(i) + 0.5) / 16.0, pixel.y / 16.0);
    light += texture(uSource, uv).rgb * weight;
  }
  // Preserve fractional light through both GPU passes. Exposure, matte, title
  // shade, dither and the only display quantization belong to the final shader.
  fragColor = vec4(light, 1.0);
}
