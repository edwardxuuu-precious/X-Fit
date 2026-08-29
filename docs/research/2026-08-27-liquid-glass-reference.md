# X-Fit 首页漂浮毛玻璃：Apple 官方参考

日期：2026-08-27
范围：只研究首页卡片视觉与 SwiftUI 实现边界；不修改产品代码。

## 结论

1. **“1:1 复刻”应复刻材质行为，不应照抄静态颜色。** Apple 的 Liquid Glass 会根据背后内容、尺寸、交互和系统辅助设置动态改变亮度、阴影、折射与透明度，因此不存在一组固定色值可以在所有设备上像素级复刻。
2. **X-Fit 的深色首页应保留有明暗变化的底层。** 毛玻璃只有在背后存在柔和梯度或环境光晕时才看得出透景和折射；纯黑底会让材质退化成半透明灰卡片。
3. **取消所有常驻外框线。** Liquid Glass 本身通过 lensing、几何高光和自适应阴影定义轮廓；再叠一圈均匀 `stroke` 会形成“双重边缘”，让卡片更像描边面板而不是漂浮玻璃。旧系统的 `Material` 降级也应靠背景透出和柔和阴影分层，不画常驻边框。这个判断是基于 Apple 光学原理对本项目的实现推论；“Increase Contrast”由系统为无障碍临时产生的对比边缘应保留。
4. **整张首页状态卡严格按 HIG 属于内容层，首选标准 `Material`。** Apple 明确建议 Liquid Glass 主要形成控制/导航的顶层，不要铺满内容层。若产品仍决定把单个高优先级操作卡当作自定义浮动控件，则 iOS 26 可谨慎使用 `.glassEffect(.regular, …)`，但不要让多个玻璃层互相叠加。
5. **含文字的深色卡片选 `regular`，不选 `clear`。** `regular` 会自动调节模糊与亮度来保证文字可读；`clear` 只适合照片/视频等丰富媒体背景，并要求粗亮前景。明亮媒体下使用 `clear` 时，Apple 建议考虑约 35% 的暗化层。

## 对 X-Fit 的可执行设计规则

- 背景：深炭灰到黑色的渐变，叠加一处低强度冷白环境光和一处极弱品牌绿反射；不要使用均匀纯黑。
- 卡片：连续圆角；材质直接裁进形状；**删除 `.stroke(...)`、渐变描边和 1px 发光边**。
- 悬浮：使用一到两层低不透明度、较大模糊半径的向下阴影；不要用锐利黑边。Apple 说明玻璃的阴影会随下方内容变化，阴影比静态框线更符合材质逻辑。
- 层级：整张卡只出现一个玻璃底。卡内图标、文字、分隔和按钮使用普通填充、透明度或 vibrant 前景，不再套第二层玻璃，避免 glass-on-glass。
- 交互：只有真实可点击的玻璃控件使用交互玻璃；纯展示外壳不要加 `.interactive()`。系统交互玻璃会随触摸缩放、回弹和闪光。
- 色彩：品牌绿只用于主操作或有语义的强调，不给每个玻璃元素染色；Apple 明确反对所有元素同时 tint。
- 几何：圆角和内边距保持同心关系。iOS 26 可使用 `ConcentricRectangle`；iOS 17–25 继续用相同连续圆角与稳定内边距近似。

## SwiftUI API 与本机 SDK 事实

本机为 Xcode 26.6（17F113）、iPhoneOS SDK 26.5；项目最低版本是 iOS 17.0，因此所有 Liquid Glass 新 API 都必须放在 `if #available(iOS 26.0, *)` 分支中。

本机 SwiftUI/SwiftUICore 接口确认：

```swift
// iOS 26+
func glassEffect(
    _ glass: Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape()
) -> some View

struct Glass {
    static var regular: Glass { get }
    static var clear: Glass { get }
    static var identity: Glass { get }
    func tint(_ color: Color?) -> Glass
    func interactive(_ isEnabled: Bool = true) -> Glass
}

struct GlassEffectContainer<Content: View>: View {
    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content)
}

func glassEffectID(
    _ id: (some Hashable & Sendable)?,
    in namespace: Namespace.ID
) -> some View

func glassEffectUnion(
    id: (some Hashable & Sendable)?,
    namespace: Namespace.ID
) -> some View

func glassEffectTransition(
    _ transition: GlassEffectTransition
) -> some View

// iOS 26+
.buttonStyle(.glass)
.buttonStyle(.glassProminent)
```

- `.glassEffect(.regular.interactive(), in: shape)`：仅用于自定义可交互控件；触摸时由系统提供缩放、回弹和闪光。
- `GlassEffectContainer(spacing:)`：同一区域有多个玻璃形状时必须共享采样区域；Apple 说明玻璃不能采样另一个玻璃，分散到不同容器会造成不一致。容器还能提升渲染效率，并配合 `glassEffectID` 做形态融合。
- `.glassEffectID` / `.glassEffectTransition`：只在确有展开、收起或元素合并动画时使用；静态单卡无需引入。
- `ConcentricRectangle`：iOS 26+，用于自动保持内外圆角同心；不是毛玻璃成立的必要条件。

本机接口证据：

- `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface`
- `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`
- `FitnessApp.xcodeproj/project.pbxproj`：`IPHONEOS_DEPLOYMENT_TARGET = 17.0`

## iOS 17–25 降级

标准 `Material` 自 iOS 15 可用，项目的 iOS 17 下限无需额外兼容桥接：

```swift
// iOS 17–25
content
    .background(.thinMaterial, in: shape)
    .shadow(color: .black.opacity(0.40), radius: 28, y: 18)
```

- 内容多、底层复杂时优先 `.regularMaterial`；想让背景梯度更多透出时用 `.thinMaterial`。`.ultraThinMaterial` 最透明，深色页面上容易显灰且降低文字稳定性，不应仅因为“更玻璃”就默认使用。
- 不叠加白色描边。若仍需增加立体感，调整背景的明暗层次和阴影，而不是补一圈边。
- 不用手绘高光去冒充系统 Liquid Glass 的实时 lensing；旧系统只保证“磨砂与悬浮”的视觉语义，不伪造 iOS 26 的动态光学行为。

## 无障碍与验收

- `@Environment(\.accessibilityReduceTransparency)` 为 `true` 时，Apple 要求半透明背景改为不透明；降级分支应使用实色 `elevatedSurface`。iOS 26 系统 Glass 会自动变得更磨砂，但自定义叠层仍需检查。
- `@Environment(\.accessibilityReduceMotion)` 为 `true` 时，不增加自定义弹性、视差或持续漂移动画；系统 Glass 会自动降低弹性效果。
- `@Environment(\.colorSchemeContrast)` 为 `.increased` 时，优先加厚/变实材质并验证文字对比；不要为了满足“无框线”而移除系统为无障碍生成的对比边缘。
- 验收至少覆盖：标准深色、Reduce Transparency、Increase Contrast、Reduce Motion、Accessibility XXXL；卡片文字和图标不能只靠玻璃明暗区分。

## 官方一手来源

- Apple HIG — [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- Apple Developer — [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- Apple Developer — [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- WWDC25 — [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- WWDC25 — [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- WWDC25 — [Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- Apple Developer — [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- Apple Developer — [`accessibilityReduceTransparency`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)
- Apple HIG — [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
