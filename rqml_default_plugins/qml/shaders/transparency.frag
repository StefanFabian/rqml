#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float width;
    float height;

    float xMin;
    float xMax;
    float yMin;
    float yMax;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    if (qt_TexCoord0.x < xMin || qt_TexCoord0.x > xMax ||
        qt_TexCoord0.y < yMin || qt_TexCoord0.y > yMax) {
        fragColor = vec4(0.0); // Transparent
        return;
    }
    vec4 color = texture(source, qt_TexCoord0);
    float aspect = height > 0 ? width / height : 1;
    float scale = 30.0;
    float checker = mod(floor(qt_TexCoord0.x * scale * aspect) + floor(qt_TexCoord0.y * scale), 2.0);
    vec3 backColor = mix(vec3(0.3), vec3(0.6), checker); // Dark grey and Light grey

    float bgA = 1 - color.a;
    fragColor = vec4(backColor * bgA + vec3(color.r, color.g, color.b) * color.a, 1.0);
}
