import SwiftUI

/// 判定一次课表拖动是否算翻页、翻向哪一侧（纯计算，便于单测）。
enum PageSwipe {

    /// 判定为翻页的最小横向位移（pt）。
    static let distanceThreshold: CGFloat = 44

    /// 横向位移至少要达到纵向的多少倍才算「横着滑」。
    static let dominance: CGFloat = 1.5

    /// 翻页方向：`1` = 下一页（向左滑），`-1` = 上一页（向右滑），`nil` = 不翻页。
    static func direction(translation: CGSize) -> Int? {
        let horizontal = translation.width
        let vertical = translation.height

        guard abs(horizontal) >= distanceThreshold,
              abs(horizontal) > abs(vertical) * dominance
        else { return nil }

        return horizontal < 0 ? 1 : -1
    }
}

/// 把左右滑动接到视图上（周 / 日 / 月三个课表视图共用），并补「下一页 / 上一页」无障碍动作。
struct PageSwipeModifier: ViewModifier {

    /// 下一页的无障碍动作名（周视图是「下一周」，日视图是「后一天」…）
    var nextTitle: String
    /// 上一页的无障碍动作名
    var previousTitle: String
    /// 往哪边翻（`1` = 下一页，`-1` = 上一页）
    var onSwipe: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        guard let delta = PageSwipe.direction(translation: value.translation) else { return }
                        onSwipe(delta)
                    }
            )
            .accessibilityAction(named: Text(nextTitle)) { onSwipe(1) }
            .accessibilityAction(named: Text(previousTitle)) { onSwipe(-1) }
    }
}

extension View {

    /// 左右滑动翻页（越界由调用方忽略）。
    func pageSwipe(
        next nextTitle: String,
        previous previousTitle: String,
        onSwipe: @escaping (Int) -> Void
    ) -> some View {
        modifier(
            PageSwipeModifier(
                nextTitle: nextTitle,
                previousTitle: previousTitle,
                onSwipe: onSwipe
            )
        )
    }
}
