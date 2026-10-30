import SwiftUI
import UIKit
import CoreGraphics

/// 先完整显示课表，放大后可横向、纵向滚动核对细节。
struct TimetableImagePreview: View {
    let image: UIImage
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private var displayedZoom: CGFloat { min(max(zoom * pinch, 1), 4) }

    var body: some View {
        GeometryReader { geometry in
            let factor = min(
                geometry.size.width / max(image.size.width, 1),
                geometry.size.height / max(image.size.height, 1)
            )
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: image.size.width * factor * displayedZoom,
                        height: image.size.height * factor * displayedZoom
                    )
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    .accessibilityLabel("本次导入的原始课表，放大后可滚动核对")
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 4) }
                    )
                    .onTapGesture(count: 2) { zoom = zoom == 1 ? 2 : 1 }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 24) {
                Button("缩小", systemImage: "minus.magnifyingglass") { zoom = max(zoom - 0.5, 1) }
                    .labelStyle(.iconOnly)
                    .disabled(zoom <= 1)
                Button("\(Int(zoom * 100))% · 适合屏幕") { zoom = 1 }
                    .font(.callout.monospacedDigit())
                Button("放大", systemImage: "plus.magnifyingglass") { zoom = min(zoom + 0.5, 4) }
                    .labelStyle(.iconOnly)
                    .disabled(zoom >= 4)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}
