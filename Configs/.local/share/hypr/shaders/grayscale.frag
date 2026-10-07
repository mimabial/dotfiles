// Any #ifndef default below can be predefined in grayscale.inc, which window/shaders.sh compiles in first.

#ifndef GRAYSCALE_TYPE
    #define GRAYSCALE_TYPE 0
#endif
#ifndef GRAYSCALE_LUMA
    #define GRAYSCALE_LUMA 1
#endif

#version 300 es
precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

const int LUMINOSITY = 0;
const int LIGHTNESS = 1;
const int AVERAGE = 2;

const int PAL = 0;
const int HDTV = 1;
const int HDR = 2;

const int Type = GRAYSCALE_TYPE;
const int LuminosityType = GRAYSCALE_LUMA;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);

    float gray;
    if (Type == LUMINOSITY) {
        // https://en.wikipedia.org/wiki/Grayscale#Luma_coding_in_video_systems
        if (LuminosityType == PAL) {
            gray = dot(pixColor.rgb, vec3(0.299, 0.587, 0.114));
        } else if (LuminosityType == HDTV) {
            gray = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));
        } else if (LuminosityType == HDR) {
            gray = dot(pixColor.rgb, vec3(0.2627, 0.6780, 0.0593));
        }
    } else if (Type == LIGHTNESS) {
        float maxPixColor = max(pixColor.r, max(pixColor.g, pixColor.b));
        float minPixColor = min(pixColor.r, min(pixColor.g, pixColor.b));
        gray = (maxPixColor + minPixColor) / 2.0;
    } else if (Type == AVERAGE) {
        gray = (pixColor.r + pixColor.g + pixColor.b) / 3.0;
    }
    vec3 grayscale = vec3(gray);

    fragColor = vec4(grayscale, pixColor.a);
}
