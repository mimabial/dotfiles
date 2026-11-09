// Author: khing

// Any #ifndef default below can be predefined in color-vision.inc, which window/shaders.sh compiles in first.

#version 300 es

#ifndef COLOR_VISION_MODE
    #define COLOR_VISION_MODE 0
#endif
#ifndef COLOR_VISION_INTENSITY
    #define COLOR_VISION_INTENSITY 0.0
#endif

precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

const int NORMAL_VISION = 0;
const int PROTANOPIA = 1;
const int DEUTERANOPIA = 2;
const int TRITANOPIA = 3;

const int MODE = COLOR_VISION_MODE;
const float INTENSITY = COLOR_VISION_INTENSITY;

const vec3 REC709_LUMA = vec3(0.2126, 0.7152, 0.0722);
const float MAX_SATURATION_GAIN = 1.5;

const vec3 PROTANOPIA_ERROR_SHIFT = vec3(0.0, 0.7, 0.3);
const vec3 DEUTERANOPIA_ERROR_SHIFT = vec3(0.7, 0.0, 0.3);
const vec3 TRITANOPIA_ERROR_SHIFT = vec3(0.5, 0.5, 0.0);

const float protanopia_r = 2.02344;
const float protanopia_g = -2.52581;

const float deuteranopia_r = 0.494207;
const float deuteranopia_g = 1.24827;

const float tritanopia_r = -0.395913;
const float tritanopia_g = 0.801109;

const mat3 RGB2LMS = mat3(
    17.8824, 43.5161, 4.11935,
    3.45565, 27.1554, 3.86714,
    0.0299566, 0.184309, 1.46709
);

const mat3 LMS2RGB = mat3(
    0.0809444479, -0.130504409, 0.116721066,
    -0.0102485335, 0.0540193266, -0.113614708,
    -0.000365296938, -0.00412161469, 0.693511405
);

vec3 simulateColorVisionDeficiency(vec3 color) {
    vec3 lms = RGB2LMS * color;
    mat3 m = mat3(1.0);
    if (MODE == PROTANOPIA) {
        m = mat3(
            0.0, protanopia_r, protanopia_g,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0
        );
    } else if (MODE == DEUTERANOPIA) {
        m = mat3(
            1.0, 0.0, 0.0,
            deuteranopia_r, 0.0, deuteranopia_g,
            0.0, 0.0, 1.0
        );
    } else if (MODE == TRITANOPIA) {
        m = mat3(
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            tritanopia_r, tritanopia_g, 0.0
        );
    }
    return LMS2RGB * (m * lms);
}

vec3 daltonize(vec3 color, vec3 simulation) {
    vec3 error = color - simulation;
    vec3 correction = vec3(0.0);
    if (MODE == PROTANOPIA) {
        correction = error.r * PROTANOPIA_ERROR_SHIFT;
    } else if (MODE == DEUTERANOPIA) {
        correction = error.g * DEUTERANOPIA_ERROR_SHIFT;
    } else if (MODE == TRITANOPIA) {
        correction = error.b * TRITANOPIA_ERROR_SHIFT;
    }
    return color + correction;
}

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 color = pixColor.rgb;

    if (MODE == NORMAL_VISION && INTENSITY == 0.0) {
        fragColor = pixColor;
        return;
    }

    vec3 simulated = simulateColorVisionDeficiency(color);
    vec3 corrected = daltonize(color, simulated);
    vec3 result;

    // The sign of INTENSITY picks the effect: in normal vision positive saturates and
    // negative desaturates; in a CVD mode positive simulates and negative daltonizes.
    if (MODE == NORMAL_VISION) {
        vec3 luminance = vec3(dot(color, REC709_LUMA));
        float saturation = INTENSITY >= 0.0 ? mix(1.0, MAX_SATURATION_GAIN, INTENSITY) : 1.0 + INTENSITY;
        result = mix(luminance, color, saturation);
    } else if (INTENSITY >= 0.0) {
        result = mix(color, simulated, INTENSITY);
    } else {
        result = mix(color, corrected, -INTENSITY);
    }

    fragColor = vec4(result, pixColor.a);
}
