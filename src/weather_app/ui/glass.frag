#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// Qt 6 ShaderEffect 要求：qt_Matrix / qt_Opacity 必须位于 block 最前
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;      // offset 0
    float qt_Opacity;    // offset 64
    vec2 winSize;
    vec2 cardPos;
    vec2 cardSize;
    float radius;
    float hover;
    vec2 mouse;
    float light;
    float refract;
    float disperse;
    vec3 tintRGB;
    float tintAlpha;
    float cardScale;
};

layout(binding = 1) uniform sampler2D bg;

// 圆角矩形 SDF：负值在内部
float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * cardSize;
    vec2 c = cardSize * 0.5;
    float d = sdRoundBox(p - c, c, radius);

    // 1px 抗锯齿边缘
    float alpha = smoothstep(0.75, -0.75, d);
    if (alpha < 0.004) discard;

    // 有限差分求 SDF 法线
    float e = 1.0;
    float dx = sdRoundBox(p - c + vec2(e, 0.0), c, radius)
             - sdRoundBox(p - c - vec2(e, 0.0), c, radius);
    float dy = sdRoundBox(p - c + vec2(0.0, e), c, radius)
             - sdRoundBox(p - c - vec2(0.0, e), c, radius);
    vec2 n = normalize(vec2(dx, dy) + vec2(1e-5, 1e-5));

    float edgeDist = max(-d, 0.0);
    float band = min(min(cardSize.x, cardSize.y) * 0.36, 40.0);
    float t = clamp(1.0 - edgeDist / band, 0.0, 1.0);

    // 边缘折射：越靠近边缘，采样点越向卡片内部偏移（透镜压缩感）
    float bend = pow(t, 2.2) * refract;
    // 用屏幕坐标采样：卡片放大时外框变大，但玻璃后的背景保持原位 1:1，
    // 不随 scale 一起被放大
    vec2 center = cardSize * 0.5;
    vec2 screenPos = cardPos + center + (p - center) * cardScale;
    vec2 uv = (screenPos - n * bend * cardScale) / winSize;

    // RGB 色散：R/B 沿法线反方向轻微错开
    // 背景纹理带 mipmap，用 textureLod 直接取模糊层，不增加采样次数
    // LOD 0：半分辨率原图，保留月亮/云层细节；磨砂感主要来自 1/2 抓取
    const float BLUR_LOD = 0.0;
    vec2 duv = (n * bend * disperse) / winSize;
    vec3 col;
    col.r = textureLod(bg, uv + duv, BLUR_LOD).r;
    col.g = textureLod(bg, uv, BLUR_LOD).g;
    col.b = textureLod(bg, uv - duv, BLUR_LOD).b;

    // 玻璃 tint：整体更透，仅边缘保留一点厚度色
    float tintMix = tintAlpha * (0.75 + 0.25 * t);
    col = mix(col, tintRGB, tintMix);

    // 顶部受光、底部微暗，制造厚度感（保持很轻，避免灰膜感）
    float v = clamp(p.y / cardSize.y, 0.0, 1.0);
    col += (0.5 - v) * (light > 0.5 ? 0.005 : 0.008);

    // 边缘菲涅尔：左上迎光侧更亮
    vec2 L = normalize(vec2(-0.45, -1.0));
    float facing = clamp(dot(n, -L), 0.0, 1.0);
    float rim = pow(t, 2.0);
    float edgeGain = 0.35 + 0.65 * facing;
    col += vec3(0.92, 0.96, 1.0) * rim
         * (0.025 + 0.12 * facing) * (light > 0.5 ? 0.75 : 1.0);

    // 1px 亮边（玻璃厚度的高光切面），背光侧衰减
    float line = smoothstep(1.8, 0.15, edgeDist);
    col += vec3(1.0) * line * edgeGain * (light > 0.5 ? 0.08 : 0.07);

    // 玻璃厚度：顶/左迎光侧提亮、底/背光侧微暗，只作用在 7px 内缘。
    // 不叠加整面暗层，因此不会降低背景可视程度。
    float bevel = smoothstep(0.5, 2.5, edgeDist) * (1.0 - smoothstep(2.5, 7.0, edgeDist));
    float bevLight = clamp(dot(n, normalize(vec2(-0.7, -1.0))), 0.0, 1.0);
    col += vec3(0.80, 0.90, 1.0) * bevel * bevLight * 0.09;
    col -= vec3(0.02, 0.04, 0.08) * bevel * (1.0 - bevLight) * 0.05;

    // 鼠标跟随高光：只做指针附近的小范围镜面光斑 + 指针侧边缘反光，
    // 避免旧版大范围柔光把整张卡提亮成灰白
    if (hover > 0.001) {
        vec2 md = p - mouse;
        float md2 = dot(md, md);
        float glow = exp(-md2 / 4200.0);   // 柔光半径约 65px
        float spec = exp(-md2 / 300.0);    // 镜面核半径约 17px
        vec2 toMouse = normalize(mouse - c + vec2(1e-5, 1e-5));
        float side = clamp(dot(n, toMouse), 0.0, 1.0);
        float rimHover = pow(t, 3.0) * side;
        float hk = light > 0.5 ? 0.40 : 1.0;

        col += vec3(0.86, 0.93, 1.0) * glow * hover * 0.07 * hk;
        col += vec3(1.0) * spec * hover * 0.20 * hk;
        col += vec3(0.92, 0.96, 1.0) * rimHover * hover * 0.07 * hk;
    }

    fragColor = vec4(col, alpha * qt_Opacity);
}
