#version 440

// cloth.frag — FullScreen.qml. From lukpednoi's Anserin (https://github.com/lukpednoi/Anserin,
// AGPL-3.0-or-later): src/quickshell/blankpanel/pages/bubble/shaders/bubble_cloth.frag at 1909479.
// Added here: the cloth has the popup's rounded corners (`radius`), so it takes over from the popup unseen.

// The cloth's colour (cloth.vert moves it): the UI, lighter and darker along the ripple's folds.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) in float fold;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float prog;
    float swirl;
    float radius;
    vec2 size;
    vec2 target;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    c.rgb *= 1.0 + 0.18 * fold;
    vec2 corner = abs(qt_TexCoord0 - 0.5) * size - (size * 0.5 - radius);
    float outside = length(max(corner, 0.0)) - radius;
    fragColor = c * qt_Opacity * (1.0 - smoothstep(-0.5, 0.5, outside));
}
