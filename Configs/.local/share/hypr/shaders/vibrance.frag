// Author: khing

// Any #ifndef default below can be predefined in vibrance.inc, which window/shaders.sh compiles in first.

#ifndef VIBRANCE_INTENSITY
    #define VIBRANCE_INTENSITY 1.0
#endif
#ifndef SHADER_VIBRANCE_SKIN_TONE_PROTECTION
    #define SHADER_VIBRANCE_SKIN_TONE_PROTECTION 0.75
#endif

#version 300 es
precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;


const float VIBRANCE = VIBRANCE_INTENSITY;
const float SKIN_TONE_PROTECTION = SHADER_VIBRANCE_SKIN_TONE_PROTECTION;
const vec3 REC709_LUMA = vec3(0.2126, 0.7152, 0.0722);
const vec3 SKIN_TONE_MIN = vec3(0.4, 0.2, 0.1);
const vec3 SKIN_TONE_MAX = vec3(0.85, 0.7, 0.5);


float getLuminance(vec3 color) {
    return dot(color, REC709_LUMA);
}

float skinToneMask(vec3 color) {
    bool warmChannelOrder = color.r > color.g && color.g > color.b;
    bool inSkinRange = all(greaterThanEqual(color, SKIN_TONE_MIN)) && all(lessThanEqual(color, SKIN_TONE_MAX));
    return float(warmChannelOrder && inSkinRange);
}

float getSaturation(vec3 color) {
    float minVal = min(min(color.r, color.g), color.b);
    float maxVal = max(max(color.r, color.g), color.b);

    return (maxVal == 0.0) ? 0.0 : (maxVal - minVal) / maxVal;
}

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 color = pixColor.rgb;

    if (VIBRANCE == 0.0) {
        fragColor = pixColor;
        return;
    }

    float saturation = getSaturation(color);
    float luma = getLuminance(color);

    float vibranceAmount = (1.0 - saturation) * abs(VIBRANCE);
    float skinProtection = skinToneMask(color) * SKIN_TONE_PROTECTION;

    vec3 result;

    if (VIBRANCE > 0.0) {
        float adjustedVibrance = vibranceAmount * (1.0 - skinProtection);
        vec3 grayColor = vec3(luma);
        result = mix(grayColor, color, 1.0 + adjustedVibrance);
    } else {
        vec3 grayColor = vec3(luma);
        result = mix(color, grayColor, vibranceAmount);
    }

    fragColor = vec4(result, pixColor.a);
}
