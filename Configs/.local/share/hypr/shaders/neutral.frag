/* 
  ┌─────────────────────────────────────────────────────────────────────────┐
  │ This is a neutral pass-through shader that leaves the frame unchanged.  │
  └─────────────────────────────────────────────────────────────────────────┘
 */

#version 300 es
precision mediump float;

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;

void main() {
    fragColor = texture(tex, v_texcoord);
}
