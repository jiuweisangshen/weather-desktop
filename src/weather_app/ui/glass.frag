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
    float light;
    float refract;
    float disperse;
    vec3 tintRGB;
    float tintAlpha;
    float cardScale;
    vec2 sunDir;        // 由时间与太阳位置算出的光源方向（屏幕空间，指向光源）
    float sunLevel;     // 太阳光强度 0~1
    float lightBlend;   // 0=太阳光，1=鼠标跟随光（动画平滑过渡）
    vec2 mouseScreen;   // 全窗口共享的鼠标光点（bgCapture 坐标系）
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
    // 折射只保留贴边很窄的一圈：大卡片上不会把整片背景向中心压缩
    float band = min(min(cardSize.x, cardSize.y) * 0.30, 28.0);
    float t = clamp(1.0 - edgeDist / band, 0.0, 1.0);

    // 极轻的边缘折射：只做 2~3px 的镜片弯折，厚度感交给边缘切面高光。
    // 旧版 4% 径向压缩 + 21px 弯折会把月相卡后的楼群拉弯，已移除。
    float lens = pow(t, 1.8);
    float bend = lens * min(refract * 0.22, 3.0);
    vec2 center = cardSize * 0.5;
    vec2 local = p - center;
    vec2 lensLocal = local;
    // 卡片放大时玻璃后的背景仍保持原位 1:1，不跟着 scale 放大
    vec2 screenPos = cardPos + center + lensLocal * cardScale - n * bend * cardScale;
    vec2 uv = screenPos / winSize;

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

    // 立体光源：太阳方向为基底，鼠标跟随光优先级更高。
    // lightBlend 由 QML 做 360ms 缓动，太阳光 → 鼠标光的切换是丝滑的。
    vec2 sunL = normalize(mix(vec2(-0.6, -0.8), sunDir, sunLevel));
    // 鼠标光点是全窗口共享的：换算到本卡未缩放的局部坐标。
    // 卡片 hover 放大 1.03 时，屏幕坐标要先绕中心反缩放，光斑才会正好落在指针下。
    float safeScale = max(cardScale, 0.001);
    vec2 mouseLocal = center + (mouseScreen - cardPos - center) / safeScale;
    vec2 mvec = mouseLocal - center;
    float mlen = length(mvec);
    // 指针靠近卡片中心时方向不稳定，平滑退回太阳方向，避免高光跳变
    vec2 mouseDir = mlen > 0.001 ? mvec / mlen : sunL;
    float dirW = smoothstep(6.0, 30.0, mlen);
    vec2 mouseL = normalize(mix(sunL, mouseDir, dirW) + vec2(1e-4, 1e-4));
    float blend = clamp(lightBlend, 0.0, 1.0);
    vec2 L = normalize(mix(sunL, mouseL, blend) + vec2(1e-4, 1e-4));
    float lam = dot(n, L);
    float hi = clamp(lam, 0.0, 1.0);
    float lo = clamp(-lam, 0.0, 1.0);
    float lm = light > 0.5 ? 0.75 : 1.0;

    // 16px 宽的主切面：迎光侧提亮、背光侧压暗，只在边缘生效
    float bevelWide = 1.0 - smoothstep(0.0, 16.0, edgeDist);
    col += vec3(0.78, 0.88, 1.0) * bevelWide * hi * 0.18 * lm;
    col *= 1.0 - bevelWide * lo * 0.10 * lm;

    // 6px 内层切面：再叠一层冷白高光，形成玻璃的“厚度分层”
    float bevelInner = 1.0 - smoothstep(0.0, 6.0, edgeDist);
    col += vec3(0.90, 0.96, 1.0) * bevelInner * hi * 0.12 * lm;

    // 外缘 2px 镜面亮线
    float line = smoothstep(2.2, 0.2, edgeDist);
    col += vec3(1.0) * line * (0.06 + 0.18 * hi) * lm;

    // 内侧 4~7px 暗线：玻璃厚底的内阴影，只影响一条细边
    float innerLine = smoothstep(3.0, 4.5, edgeDist) * (1.0 - smoothstep(5.5, 7.5, edgeDist));
    col *= 1.0 - innerLine * lo * 0.06;

    // 左上大面柔光：极淡，给玻璃一点整体起伏
    float sheen = pow(hi, 3.0) * (1.0 - smoothstep(0.0, 46.0, edgeDist));
    col += vec3(0.82, 0.90, 1.0) * sheen * 0.05 * lm;

    // 鼠标跟随高光：只做指针附近的小范围镜面光斑 + 指针侧边缘反光，
    // 避免旧版大范围柔光把整张卡提亮成灰白
    if (hover > 0.001) {
        vec2 md = p - mouseLocal;
        float md2 = dot(md, md);
        float glow = exp(-md2 / 4200.0);   // 柔光半径约 65px
        float spec = exp(-md2 / 300.0);    // 镜面核半径约 17px
        vec2 toMouse = mouseL;
        float side = clamp(dot(n, toMouse), 0.0, 1.0);
        float rimHover = pow(t, 3.0) * side;
        float hk = light > 0.5 ? 0.40 : 1.0;

        col += vec3(0.86, 0.93, 1.0) * glow * hover * 0.07 * hk;
        col += vec3(1.0) * spec * hover * 0.20 * hk;
        col += vec3(0.92, 0.96, 1.0) * rimHover * hover * 0.07 * hk;
    }

    fragColor = vec4(col, alpha * qt_Opacity);
}
