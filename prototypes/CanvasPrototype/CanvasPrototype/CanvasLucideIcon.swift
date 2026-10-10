import SwiftUI

/*
 Lucide icon paths: https://github.com/lucide-icons/lucide/tree/main/icons
 ISC License. Copyright (c) 2026 Lucide Icons and Contributors.
 Permission to use, copy, modify, and/or distribute this software for any purpose
 with or without fee is hereby granted, provided that the above copyright notice
 and this permission notice appear in all copies.
 THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
 REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
 AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
 INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
 LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
 OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 PERFORMANCE OF THIS SOFTWARE.
 */

/// Native paths from Lucide SVGs. No external renderer is needed.
struct CanvasLucideIcon: View {
    enum Kind {
        case pen, marker, eraser, text, rectangle, lasso, box, undo, more, settings, folder, notebook, plus, arrowLeft, home, trash
    }

    let kind: Kind

    var body: some View {
        GeometryReader { geometry in
            iconPath
                .applying(CGAffineTransform(scaleX: geometry.size.width / 24, y: geometry.size.height / 24))
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var iconPath: Path {
        var path = Path()
        switch kind {
        case .trash:
            path.move(to: CGPoint(x: 3, y: 6))
            path.addLine(to: CGPoint(x: 21, y: 6))
            path.move(to: CGPoint(x: 19, y: 6))
            path.addLine(to: CGPoint(x: 19, y: 20))
            path.addQuadCurve(to: CGPoint(x: 17, y: 22), control: CGPoint(x: 19, y: 22))
            path.addLine(to: CGPoint(x: 7, y: 22))
            path.addQuadCurve(to: CGPoint(x: 5, y: 20), control: CGPoint(x: 5, y: 22))
            path.addLine(to: CGPoint(x: 5, y: 6))
            path.move(to: CGPoint(x: 8, y: 6))
            path.addLine(to: CGPoint(x: 8, y: 4))
            path.addQuadCurve(to: CGPoint(x: 10, y: 2), control: CGPoint(x: 8, y: 2))
            path.addLine(to: CGPoint(x: 14, y: 2))
            path.addQuadCurve(to: CGPoint(x: 16, y: 4), control: CGPoint(x: 16, y: 2))
            path.addLine(to: CGPoint(x: 16, y: 6))
            for x in [10, 14] {
                path.move(to: CGPoint(x: x, y: 11))
                path.addLine(to: CGPoint(x: x, y: 17))
            }
        case .home:
            path.move(to: CGPoint(x: 15, y: 21))
            path.addLine(to: CGPoint(x: 15, y: 13))
            path.addQuadCurve(to: CGPoint(x: 14, y: 12), control: CGPoint(x: 15, y: 12))
            path.addLine(to: CGPoint(x: 10, y: 12))
            path.addQuadCurve(to: CGPoint(x: 9, y: 13), control: CGPoint(x: 9, y: 12))
            path.addLine(to: CGPoint(x: 9, y: 21))
            path.move(to: CGPoint(x: 3, y: 10))
            path.addQuadCurve(to: CGPoint(x: 3.709, y: 8.472), control: CGPoint(x: 3, y: 9.1))
            path.addLine(to: CGPoint(x: 10.709, y: 2.472))
            path.addQuadCurve(to: CGPoint(x: 13.291, y: 2.472), control: CGPoint(x: 12, y: 1.366))
            path.addLine(to: CGPoint(x: 20.291, y: 8.472))
            path.addQuadCurve(to: CGPoint(x: 21, y: 10), control: CGPoint(x: 21, y: 9.1))
            path.addLine(to: CGPoint(x: 21, y: 19))
            path.addQuadCurve(to: CGPoint(x: 19, y: 21), control: CGPoint(x: 21, y: 21))
            path.addLine(to: CGPoint(x: 5, y: 21))
            path.addQuadCurve(to: CGPoint(x: 3, y: 19), control: CGPoint(x: 3, y: 21))
            path.closeSubpath()
        case .folder:
            path.move(to: CGPoint(x: 20, y: 20))
            path.addQuadCurve(to: CGPoint(x: 22, y: 18), control: CGPoint(x: 22, y: 20))
            path.addLine(to: CGPoint(x: 22, y: 8))
            path.addQuadCurve(to: CGPoint(x: 20, y: 6), control: CGPoint(x: 22, y: 6))
            path.addLine(to: CGPoint(x: 12.1, y: 6))
            path.addQuadCurve(to: CGPoint(x: 10.41, y: 5.1), control: CGPoint(x: 11, y: 6))
            path.addLine(to: CGPoint(x: 9.6, y: 3.9))
            path.addQuadCurve(to: CGPoint(x: 7.93, y: 3), control: CGPoint(x: 9, y: 3))
            path.addLine(to: CGPoint(x: 4, y: 3))
            path.addQuadCurve(to: CGPoint(x: 2, y: 5), control: CGPoint(x: 2, y: 3))
            path.addLine(to: CGPoint(x: 2, y: 18))
            path.addQuadCurve(to: CGPoint(x: 4, y: 20), control: CGPoint(x: 2, y: 20))
            path.closeSubpath()
        case .notebook:
            path.addRoundedRect(in: CGRect(x: 4, y: 2, width: 16, height: 20), cornerSize: CGSize(width: 2, height: 2))
            path.move(to: CGPoint(x: 16, y: 2))
            path.addLine(to: CGPoint(x: 16, y: 22))
            for y in [6, 10, 14, 18] {
                path.move(to: CGPoint(x: 2, y: y))
                path.addLine(to: CGPoint(x: 6, y: y))
            }
        case .plus:
            path.move(to: CGPoint(x: 5, y: 12))
            path.addLine(to: CGPoint(x: 19, y: 12))
            path.move(to: CGPoint(x: 12, y: 5))
            path.addLine(to: CGPoint(x: 12, y: 19))
        case .arrowLeft:
            path.move(to: CGPoint(x: 12, y: 19))
            path.addLine(to: CGPoint(x: 5, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 5))
            path.move(to: CGPoint(x: 19, y: 12))
            path.addLine(to: CGPoint(x: 5, y: 12))
        case .pen:
            path.move(to: CGPoint(x: 13, y: 21))
            path.addLine(to: CGPoint(x: 21, y: 21))
            path.move(to: CGPoint(x: 21.174, y: 6.812))
            path.addCurve(to: CGPoint(x: 21.1745, y: 2.8255), control1: CGPoint(x: 22.275, y: 5.7113), control2: CGPoint(x: 22.2752, y: 3.92648))
            path.addCurve(to: CGPoint(x: 17.188, y: 2.825), control1: CGPoint(x: 20.0738, y: 1.72452), control2: CGPoint(x: 18.289, y: 1.7243))
            path.addLine(to: CGPoint(x: 3.842, y: 16.174))
            path.addCurve(to: CGPoint(x: 3.342, y: 17.004), control1: CGPoint(x: 3.60982, y: 16.4055), control2: CGPoint(x: 3.43811, y: 16.6905))
            path.addLine(to: CGPoint(x: 2.021, y: 21.356))
            path.addCurve(to: CGPoint(x: 2.1468, y: 21.853), control1: CGPoint(x: 1.96835, y: 21.5322), control2: CGPoint(x: 2.01666, y: 21.7231))
            path.addCurve(to: CGPoint(x: 2.644, y: 21.978), control1: CGPoint(x: 2.27693, y: 21.9829), control2: CGPoint(x: 2.46789, y: 22.0309))
            path.addLine(to: CGPoint(x: 6.997, y: 20.658))
            path.addCurve(to: CGPoint(x: 7.827, y: 20.161), control1: CGPoint(x: 7.31017, y: 20.5628), control2: CGPoint(x: 7.59517, y: 20.3921))
            path.addLine(to: CGPoint(x: 21.174, y: 6.812))
            path.closeSubpath()
        case .marker:
            path.move(to: CGPoint(x: 9, y: 11))
            path.addLine(to: CGPoint(x: 3, y: 17))
            path.addLine(to: CGPoint(x: 3, y: 20))
            path.addLine(to: CGPoint(x: 12, y: 20))
            path.addLine(to: CGPoint(x: 15, y: 17))
            path.move(to: CGPoint(x: 22, y: 12))
            path.addLine(to: CGPoint(x: 17.4, y: 16.6))
            path.addCurve(to: CGPoint(x: 14.6, y: 16.6), control1: CGPoint(x: 16.6223, y: 17.3623), control2: CGPoint(x: 15.3777, y: 17.3623))
            path.addLine(to: CGPoint(x: 9.4, y: 11.4))
            path.addCurve(to: CGPoint(x: 9.4, y: 8.6), control1: CGPoint(x: 8.63771, y: 10.6223), control2: CGPoint(x: 8.63771, y: 9.37769))
            path.addLine(to: CGPoint(x: 14, y: 4))
        case .eraser:
            path.move(to: CGPoint(x: 21, y: 21))
            path.addLine(to: CGPoint(x: 8, y: 21))
            path.addCurve(to: CGPoint(x: 6.58, y: 20.413), control1: CGPoint(x: 7.46739, y: 21.0012), control2: CGPoint(x: 6.95629, y: 20.7899))
            path.addLine(to: CGPoint(x: 2.586, y: 16.414))
            path.addCurve(to: CGPoint(x: 2.586, y: 13.586), control1: CGPoint(x: 1.80524, y: 15.633), control2: CGPoint(x: 1.80524, y: 14.367))
            path.addLine(to: CGPoint(x: 12.586, y: 3.586))
            path.addCurve(to: CGPoint(x: 15.415, y: 3.586), control1: CGPoint(x: 13.3671, y: 2.80457), control2: CGPoint(x: 14.6339, y: 2.80457))
            path.addLine(to: CGPoint(x: 21.414, y: 9.586))
            path.addCurve(to: CGPoint(x: 21.414, y: 12.414), control1: CGPoint(x: 22.1948, y: 10.367), control2: CGPoint(x: 22.1948, y: 11.633))
            path.addLine(to: CGPoint(x: 12.834, y: 21))
            path.move(to: CGPoint(x: 5.082, y: 11.09))
            path.addLine(to: CGPoint(x: 13.91, y: 19.918))
        case .text:
            path.move(to: CGPoint(x: 12, y: 20))
            path.addLine(to: CGPoint(x: 11, y: 20))
            path.addCurve(to: CGPoint(x: 9, y: 18), control1: CGPoint(x: 9.89543, y: 20), control2: CGPoint(x: 9, y: 19.1046))
            path.addCurve(to: CGPoint(x: 7, y: 20), control1: CGPoint(x: 9, y: 19.1046), control2: CGPoint(x: 8.10457, y: 20))
            path.addLine(to: CGPoint(x: 6, y: 20))
            path.move(to: CGPoint(x: 13, y: 8))
            path.addLine(to: CGPoint(x: 20, y: 8))
            path.addCurve(to: CGPoint(x: 22, y: 10), control1: CGPoint(x: 21.1046, y: 8), control2: CGPoint(x: 22, y: 8.89543))
            path.addLine(to: CGPoint(x: 22, y: 14))
            path.addCurve(to: CGPoint(x: 20, y: 16), control1: CGPoint(x: 22, y: 15.1046), control2: CGPoint(x: 21.1046, y: 16))
            path.addLine(to: CGPoint(x: 13, y: 16))
            path.move(to: CGPoint(x: 5, y: 16))
            path.addLine(to: CGPoint(x: 4, y: 16))
            path.addCurve(to: CGPoint(x: 2, y: 14), control1: CGPoint(x: 2.89543, y: 16), control2: CGPoint(x: 2, y: 15.1046))
            path.addLine(to: CGPoint(x: 2, y: 10))
            path.addCurve(to: CGPoint(x: 4, y: 8), control1: CGPoint(x: 2, y: 8.89543), control2: CGPoint(x: 2.89543, y: 8))
            path.addLine(to: CGPoint(x: 5, y: 8))
            path.move(to: CGPoint(x: 6, y: 4))
            path.addLine(to: CGPoint(x: 7, y: 4))
            path.addCurve(to: CGPoint(x: 9, y: 6), control1: CGPoint(x: 8.10457, y: 4), control2: CGPoint(x: 9, y: 4.89543))
            path.addCurve(to: CGPoint(x: 11, y: 4), control1: CGPoint(x: 9, y: 4.89543), control2: CGPoint(x: 9.89543, y: 4))
            path.addLine(to: CGPoint(x: 12, y: 4))
            path.move(to: CGPoint(x: 9, y: 6))
            path.addLine(to: CGPoint(x: 9, y: 18))
        case .rectangle:
            path.move(to: CGPoint(x: 4, y: 6))
            path.addLine(to: CGPoint(x: 20, y: 6))
            path.addCurve(to: CGPoint(x: 22, y: 8), control1: CGPoint(x: 21.1046, y: 6), control2: CGPoint(x: 22, y: 6.89543))
            path.addLine(to: CGPoint(x: 22, y: 16))
            path.addCurve(to: CGPoint(x: 20, y: 18), control1: CGPoint(x: 22, y: 17.1046), control2: CGPoint(x: 21.1046, y: 18))
            path.addLine(to: CGPoint(x: 4, y: 18))
            path.addCurve(to: CGPoint(x: 2, y: 16), control1: CGPoint(x: 2.89543, y: 18), control2: CGPoint(x: 2, y: 17.1046))
            path.addLine(to: CGPoint(x: 2, y: 8))
            path.addCurve(to: CGPoint(x: 4, y: 6), control1: CGPoint(x: 2, y: 6.89543), control2: CGPoint(x: 2.89543, y: 6))
            path.closeSubpath()
        case .lasso:
            path.move(to: CGPoint(x: 3.704, y: 14.467))
            path.addCurve(to: CGPoint(x: 5.54913, y: 3.88542), control1: CGPoint(x: 0.85338, y: 11.08), control2: CGPoint(x: 1.64868, y: 6.51905))
            path.addCurve(to: CGPoint(x: 18.8981, y: 4.20779), control1: CGPoint(x: 9.44959, y: 1.25179), control2: CGPoint(x: 15.2033, y: 1.39074))
            path.addCurve(to: CGPoint(x: 19.942, y: 14.8591), control1: CGPoint(x: 22.5929, y: 7.02484), control2: CGPoint(x: 23.0428, y: 11.6158))
            path.addCurve(to: CGPoint(x: 6.819, y: 16.842), control1: CGPoint(x: 16.8412, y: 18.1025), control2: CGPoint(x: 11.1849, y: 18.9571))
            path.move(to: CGPoint(x: 7, y: 22))
            path.addCurve(to: CGPoint(x: 5, y: 18.006), control1: CGPoint(x: 5.74266, y: 21.057), control2: CGPoint(x: 5.00189, y: 19.5777))
            path.move(to: CGPoint(x: 3, y: 16))
            path.addCurve(to: CGPoint(x: 5, y: 14), control1: CGPoint(x: 3, y: 14.8954), control2: CGPoint(x: 3.89543, y: 14))
            path.addCurve(to: CGPoint(x: 7, y: 16), control1: CGPoint(x: 6.10457, y: 14), control2: CGPoint(x: 7, y: 14.8954))
            path.addCurve(to: CGPoint(x: 5, y: 18), control1: CGPoint(x: 7, y: 17.1046), control2: CGPoint(x: 6.10457, y: 18))
            path.addCurve(to: CGPoint(x: 3, y: 16), control1: CGPoint(x: 3.89543, y: 18), control2: CGPoint(x: 3, y: 17.1046))
        case .box:
            path.move(to: CGPoint(x: 5, y: 3))
            path.addCurve(to: CGPoint(x: 3, y: 5), control1: CGPoint(x: 3.89543, y: 3), control2: CGPoint(x: 3, y: 3.89543))
            path.move(to: CGPoint(x: 19, y: 3))
            path.addCurve(to: CGPoint(x: 21, y: 5), control1: CGPoint(x: 20.1046, y: 3), control2: CGPoint(x: 21, y: 3.89543))
            path.move(to: CGPoint(x: 21, y: 19))
            path.addCurve(to: CGPoint(x: 19, y: 21), control1: CGPoint(x: 21, y: 20.1046), control2: CGPoint(x: 20.1046, y: 21))
            path.move(to: CGPoint(x: 5, y: 21))
            path.addCurve(to: CGPoint(x: 3, y: 19), control1: CGPoint(x: 3.89543, y: 21), control2: CGPoint(x: 3, y: 20.1046))
            path.move(to: CGPoint(x: 9, y: 3))
            path.addLine(to: CGPoint(x: 10, y: 3))
            path.move(to: CGPoint(x: 9, y: 21))
            path.addLine(to: CGPoint(x: 10, y: 21))
            path.move(to: CGPoint(x: 14, y: 3))
            path.addLine(to: CGPoint(x: 15, y: 3))
            path.move(to: CGPoint(x: 14, y: 21))
            path.addLine(to: CGPoint(x: 15, y: 21))
            path.move(to: CGPoint(x: 3, y: 9))
            path.addLine(to: CGPoint(x: 3, y: 10))
            path.move(to: CGPoint(x: 21, y: 9))
            path.addLine(to: CGPoint(x: 21, y: 10))
            path.move(to: CGPoint(x: 3, y: 14))
            path.addLine(to: CGPoint(x: 3, y: 15))
            path.move(to: CGPoint(x: 21, y: 14))
            path.addLine(to: CGPoint(x: 21, y: 15))
        case .undo:
            path.move(to: CGPoint(x: 9, y: 14))
            path.addLine(to: CGPoint(x: 4, y: 9))
            path.addLine(to: CGPoint(x: 9, y: 4))
            path.move(to: CGPoint(x: 4, y: 9))
            path.addLine(to: CGPoint(x: 14.5, y: 9))
            path.addCurve(to: CGPoint(x: 20, y: 14.5), control1: CGPoint(x: 17.5376, y: 9), control2: CGPoint(x: 20, y: 11.4624))
            path.addCurve(to: CGPoint(x: 14.5, y: 20), control1: CGPoint(x: 20, y: 17.5376), control2: CGPoint(x: 17.5376, y: 20))
            path.addLine(to: CGPoint(x: 11, y: 20))
        case .more:
            path.move(to: CGPoint(x: 11, y: 12))
            path.addCurve(to: CGPoint(x: 12, y: 11), control1: CGPoint(x: 11, y: 11.4477), control2: CGPoint(x: 11.4477, y: 11))
            path.addCurve(to: CGPoint(x: 13, y: 12), control1: CGPoint(x: 12.5523, y: 11), control2: CGPoint(x: 13, y: 11.4477))
            path.addCurve(to: CGPoint(x: 12, y: 13), control1: CGPoint(x: 13, y: 12.5523), control2: CGPoint(x: 12.5523, y: 13))
            path.addCurve(to: CGPoint(x: 11, y: 12), control1: CGPoint(x: 11.4477, y: 13), control2: CGPoint(x: 11, y: 12.5523))
            path.move(to: CGPoint(x: 18, y: 12))
            path.addCurve(to: CGPoint(x: 19, y: 11), control1: CGPoint(x: 18, y: 11.4477), control2: CGPoint(x: 18.4477, y: 11))
            path.addCurve(to: CGPoint(x: 20, y: 12), control1: CGPoint(x: 19.5523, y: 11), control2: CGPoint(x: 20, y: 11.4477))
            path.addCurve(to: CGPoint(x: 19, y: 13), control1: CGPoint(x: 20, y: 12.5523), control2: CGPoint(x: 19.5523, y: 13))
            path.addCurve(to: CGPoint(x: 18, y: 12), control1: CGPoint(x: 18.4477, y: 13), control2: CGPoint(x: 18, y: 12.5523))
            path.move(to: CGPoint(x: 4, y: 12))
            path.addCurve(to: CGPoint(x: 5, y: 11), control1: CGPoint(x: 4, y: 11.4477), control2: CGPoint(x: 4.44772, y: 11))
            path.addCurve(to: CGPoint(x: 6, y: 12), control1: CGPoint(x: 5.55228, y: 11), control2: CGPoint(x: 6, y: 11.4477))
            path.addCurve(to: CGPoint(x: 5, y: 13), control1: CGPoint(x: 6, y: 12.5523), control2: CGPoint(x: 5.55228, y: 13))
            path.addCurve(to: CGPoint(x: 4, y: 12), control1: CGPoint(x: 4.44772, y: 13), control2: CGPoint(x: 4, y: 12.5523))
        case .settings:
            path.move(to: CGPoint(x: 10, y: 5))
            path.addLine(to: CGPoint(x: 3, y: 5))
            path.move(to: CGPoint(x: 12, y: 19))
            path.addLine(to: CGPoint(x: 3, y: 19))
            path.move(to: CGPoint(x: 14, y: 3))
            path.addLine(to: CGPoint(x: 14, y: 7))
            path.move(to: CGPoint(x: 16, y: 17))
            path.addLine(to: CGPoint(x: 16, y: 21))
            path.move(to: CGPoint(x: 21, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 12))
            path.move(to: CGPoint(x: 21, y: 19))
            path.addLine(to: CGPoint(x: 16, y: 19))
            path.move(to: CGPoint(x: 21, y: 5))
            path.addLine(to: CGPoint(x: 14, y: 5))
            path.move(to: CGPoint(x: 8, y: 10))
            path.addLine(to: CGPoint(x: 8, y: 14))
            path.move(to: CGPoint(x: 8, y: 12))
            path.addLine(to: CGPoint(x: 3, y: 12))
        }
        return path
    }
}
