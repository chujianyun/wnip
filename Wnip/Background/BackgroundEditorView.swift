import SwiftUI
import AppKit

struct BackgroundEditorView: View {
    @ObservedObject var model: BackgroundEditorModel
    let onClose: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                preview
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        backgroundControls
                        Divider()
                        layoutControls
                        Divider()
                        styleControls
                    }.padding(22)
                }.frame(width: 310)
            }
            Divider()
            HStack(spacing: 12) {
                Button("关闭", action: onClose).keyboardShortcut(.cancelAction)
                Button("设为默认") { model.saveDefault() }
                Button("恢复初始默认") { model.resetDefault() }.foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("复制图片") { model.export(save: false) }.keyboardShortcut("c", modifiers: .command)
                Button("保存图片…") { model.export(save: true) }.keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }.padding(16).disabled(model.busy)
        }
        .frame(minWidth: 860, minHeight: 570)
        .alert("无法完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var preview: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("截图加背景").font(.title2.bold())
                    Text("调整右侧样式，实时预览效果").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.rendering { ProgressView().controlSize(.small) }
            }
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .underPageBackgroundColor))
                    if let image = model.preview {
                        Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
                            .padding(24).frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        Text("请调整样式以生成预览").foregroundStyle(.secondary)
                    }
                }
            }
            Text(model.dimensions).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Text(model.message.isEmpty ? "按原始截图像素导出，截图内容始终完整显示" : model.message)
                .font(.caption).foregroundStyle(.secondary).frame(minHeight: 28)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("背景").font(.headline)
            Picker("背景类型", selection: $model.style.kind) {
                Text("纯色").tag(BackgroundStyle.Kind.solid)
                Text("渐变").tag(BackgroundStyle.Kind.gradient)
                Text("图片").tag(BackgroundStyle.Kind.image)
            }.pickerStyle(.segmented).labelsHidden()
            switch model.style.kind {
            case .solid:
                HStack(spacing: 8) {
                    ForEach(["FFFFFF", "F4F5F7", "20242B", "CAE9DF", "BBD9FF", "FFE0DA"], id: \.self) { hex in
                        Button { model.style.solid = hex } label: {
                            Circle().fill(color(hex)).frame(width: 29, height: 29)
                                .overlay(Circle().stroke(.gray.opacity(0.4)))
                        }.buttonStyle(.plain).help("#\(hex)")
                    }
                }
                colorControl("颜色", hex: $model.style.solid)
            case .gradient:
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(GradientPreset.all) { preset in
                        Button { model.applyPreset(preset) } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(LinearGradient(colors: preset.colors.map(color), startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 36)
                                Text(preset.id).font(.caption).foregroundStyle(.primary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Picker("渐变方式", selection: $model.style.multiPoint) {
                    Text("多点柔和").tag(true)
                    Text("线性渐变").tag(false)
                }
                ForEach(0..<4, id: \.self) { index in
                    colorControl(model.style.multiPoint ? ["左上", "右上", "左下", "右下"][index] : "颜色 \(index + 1)", hex: $model.style.colors[index])
                }
                if !model.style.multiPoint { slider("方向", value: $model.style.angle, range: 0...360, suffix: "°", multiplier: 1) }
            case .image:
                HStack {
                    ForEach(BackgroundArtwork.choices, id: \.id) { item in
                        Button(item.title) {
                            var next = model.style; next.imageID = item.id; next.imageZoom = 1; next.imageX = 0.5; next.imageY = 0.5
                            model.style = next
                        }.tint(model.style.imageID == item.id ? .accentColor : .secondary)
                    }
                }
                Button("导入背景图…", systemImage: "photo.badge.plus") { model.importImage() }
                Text(model.style.imageID.hasPrefix("builtin:") ? "内置背景 · 等比铺满" : "自选图片 · 已保存在本机")
                    .font(.caption).foregroundStyle(.secondary)
                slider("缩放", value: $model.style.imageZoom, range: 1...4)
                slider("水平位置", value: $model.style.imageX, range: 0...1)
                slider("垂直位置", value: $model.style.imageY, range: 0...1)
            }
        }
    }
    private var layoutControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("画布").font(.headline)
            Picker("比例", selection: $model.style.aspect) {
                ForEach(BackgroundStyle.Aspect.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if model.style.aspect == .custom {
                HStack {
                    TextField("宽", value: $model.style.customWidth, format: .number).accessibilityLabel("自定义比例宽")
                    Text(":")
                    TextField("高", value: $model.style.customHeight, format: .number).accessibilityLabel("自定义比例高")
                }.textFieldStyle(.roundedBorder)
                Text("宽、高为 1–100；比例范围 1:10–10:1").font(.caption2).foregroundStyle(.secondary)
            }
            slider("四周留白", value: $model.style.padding, range: 0...0.6)
        }
    }
    private var styleControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("截图样式").font(.headline)
            slider("圆角", value: $model.style.radius, range: 0...0.15)
            slider("阴影", value: $model.style.shadow, range: 0...1)
            slider("白色边框", value: $model.style.border, range: 0...0.05)
            Text("留白、圆角和边框以截图短边为基准").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "%", multiplier: Double = 100) -> some View {
        VStack(spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue * multiplier))\(suffix)").foregroundStyle(.secondary).monospacedDigit() }
                .font(.callout)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
    private func colorControl(_ title: String, hex: Binding<String>) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(get: { color(hex.wrappedValue) }, set: { newColor in
                if let rgb = NSColor(newColor).usingColorSpace(.sRGB) {
                    hex.wrappedValue = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                }
            }), supportsOpacity: false)
            HexField(hex: hex).frame(width: 83)
        }
    }
    private func color(_ hex: String) -> Color { Color(cgColor: (HexRGB(hex) ?? HexRGB("FFFFFF")!).cgColor) }
}

private struct HexField: View {
    @Binding var hex: String
    @State private var text = ""
    var body: some View {
        TextField("HEX", text: $text)
            .font(.system(.caption, design: .monospaced)).textFieldStyle(.roundedBorder)
            .onAppear { text = hex }
            .onChange(of: hex) { _, new in text = new }
            .onChange(of: text) { _, new in if HexRGB(new) != nil { hex = new.replacingOccurrences(of: "#", with: "").uppercased() } }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(HexRGB(text) == nil ? Color.red : .clear))
            .help("6 位 HEX 颜色，例如 00AABB")
    }
}
