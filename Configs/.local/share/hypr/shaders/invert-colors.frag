// Known to have some quirks with some frames, example: when exiting an application,animations, and some blur effects
// TODO: Reduce artifacts during animation and blur transitions.

// Any #ifndef default below can be predefined in invert-colors.inc, which window/shaders.sh compiles in first.

#ifndef INVERT_COLORS_INTENSITY
#define INVERT_COLORS_INTENSITY 1.0
#endif

#version 300 es
precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

const float INTENSITY=INVERT_COLORS_INTENSITY;

void main(){
    vec4 pixColor=texture(tex,v_texcoord);
    
    vec3 invertedColor=mix(pixColor.rgb,1.-pixColor.rgb,INTENSITY);
    fragColor=vec4(invertedColor,pixColor.a);
}
