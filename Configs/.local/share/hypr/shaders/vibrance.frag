// Author: khing
// Vibrance raises saturation more in muted colours than in saturated ones, so it reads
// more natural than plain saturation; skin tones are protected and nothing clips.

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


// HDTV (Rec. 709) coefficients.
float getLuminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float skinToneLikelihood(vec3 color) {
    float r = color.r;
    float g = color.g;
    float b = color.b;

    bool warmChannelOrder = r > g && g > b;
    float inSkinRange = 0.0;
    if (r >= 0.4 && r <= 0.85 && g >= 0.2 && g <= 0.7 && b >= 0.1 && b <= 0.5) {
        inSkinRange = 1.0;
    }

    return float(warmChannelOrder) * inSkinRange;
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
    float skinProtection = skinToneLikelihood(color) * SKIN_TONE_PROTECTION;

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
