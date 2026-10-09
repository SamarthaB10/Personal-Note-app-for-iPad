import CoreGraphics
import PencilKit
import UIKit

enum CanvasSelectionGeometry {
    /// A lasso tap selects one complete object without starting text editing.
    static func selectObject(
        at point: CGPoint,
        drawing: PKDrawing,
        textBoxes: [CanvasTextBox],
        shapes: [CanvasShape]
    ) -> CanvasSelection {
        if let box = textBoxes.reversed().first(where: { textContentBounds($0).contains(point) }) {
            return CanvasSelection(textBoxIDs: [box.id])
        }
        if let shape = shapes.reversed().first(where: { $0.renderBounds.contains(point) }) {
            return CanvasSelection(shapeIDs: [shape.id])
        }
        if let index = drawing.strokes.indices.reversed().first(where: { index in
            strokeSamples(drawing.strokes[index]).contains { sample in
                hypot(point.x - sample.location.x, point.y - sample.location.y) <= sample.radius + 6
            }
        }) {
            return CanvasSelection(strokeIndices: [index])
        }

        // Do not guess which invisible box area the user meant when frames overlap.
        let boxes = textBoxes.filter { $0.frame.contains(point) }
        guard boxes.count == 1, let box = boxes.first else { return CanvasSelection() }
        return CanvasSelection(textBoxIDs: [box.id])
    }

    /// Includes nearby visible text so stacked boxes can be chosen by their preview.
    static func textBoxCandidates(at point: CGPoint, in textBoxes: [CanvasTextBox]) -> [CanvasTextBox] {
        let directBounds = textBoxes.map(textContentBounds).filter { $0.contains(point) }
        let visible = textBoxes.filter { box in
            let bounds = textContentBounds(box)
            guard !bounds.isNull, !bounds.isEmpty else { return false }
            return bounds.insetBy(dx: -18, dy: -18).contains(point)
                || directBounds.contains { $0.intersects(bounds) }
        }
        // Direct frame hits include empty and obscured boxes in the explicit chooser.
        let visibleIDs = Set(visible.map(\.id))
        return Array(textBoxes.filter { visibleIDs.contains($0.id) || $0.frame.contains(point) }.reversed())
    }

    /// A drag includes gaps in selected handwriting and avoids other visible targets.
    static func directSelectionContains(_ point: CGPoint, selection: CanvasSelection, in page: CanvasPageData) -> Bool {
        let drawing = (try? PKDrawing(data: page.inkDrawingData)) ?? PKDrawing()
        if page.textBoxes.contains(where: {
            !selection.textBoxIDs.contains($0.id) && textContentBounds($0).contains(point)
        }) || page.shapes.contains(where: {
            !selection.shapeIDs.contains($0.id) && $0.renderBounds.contains(point)
        }) || drawing.strokes.enumerated().contains(where: { index, stroke in
            !selection.strokeIndices.contains(index) && strokeContains(point, stroke: stroke, padding: 6)
        }) { return false }

        let inkBounds = selection.strokeIndices.compactMap { index in
            drawing.strokes.indices.contains(index) ? drawing.strokes[index].renderBounds : nil
        }.reduce(CGRect.null) { $0.union($1) }
        return (!inkBounds.isNull && inkBounds.insetBy(dx: -12, dy: -12).contains(point))
            || page.textBoxes.contains { selection.textBoxIDs.contains($0.id) && $0.frame.contains(point) }
            || page.shapes.contains { selection.shapeIDs.contains($0.id) && $0.renderBounds.contains(point) }
    }

    private static func strokeContains(_ point: CGPoint, stroke: PKStroke, padding: CGFloat) -> Bool {
        guard stroke.renderBounds.insetBy(dx: -padding, dy: -padding).contains(point) else { return false }
        return strokeSamples(stroke).contains { sample in
            hypot(point.x - sample.location.x, point.y - sample.location.y) <= sample.radius + padding
        }
    }

    static func select(
        in rectangle: CGRect,
        drawing: PKDrawing,
        textBoxes: [CanvasTextBox],
        shapes: [CanvasShape]
    ) -> CanvasSelection {
        let area = rectangle.standardized
        return CanvasSelection(
            strokeIndices: Set(drawing.strokes.enumerated().compactMap { index, stroke in
                area.contains(stroke.renderBounds) ? index : nil
            }),
            textBoxIDs: Set(textBoxes.compactMap { area.contains($0.frame) ? $0.id : nil }),
            shapeIDs: Set(shapes.compactMap { area.contains($0.renderBounds) ? $0.id : nil })
        )
    }

    static func select(
        inside polygon: [CGPoint],
        drawing: PKDrawing,
        textBoxes: [CanvasTextBox],
        shapes: [CanvasShape]
    ) -> CanvasSelection {
        guard polygon.count >= 3 else { return CanvasSelection() }

        return CanvasSelection(
            strokeIndices: Set(drawing.strokes.enumerated().compactMap { index, stroke in
                strokeIsContained(stroke, in: polygon) ? index : nil
            }),
            textBoxIDs: Set(textBoxes.compactMap { contains($0.frame, in: polygon) ? $0.id : nil }),
            shapeIDs: Set(shapes.compactMap { contains($0.renderBounds, in: polygon) ? $0.id : nil })
        )
    }

    static func bounds(of selection: CanvasSelection, in page: CanvasPageData) -> CGRect? {
        guard !selection.isEmpty else { return nil }

        let drawing = (try? PKDrawing(data: page.inkDrawingData)) ?? PKDrawing()
        var result: CGRect?

        for index in selection.strokeIndices where drawing.strokes.indices.contains(index) {
            result = result.map { $0.union(drawing.strokes[index].renderBounds) } ?? drawing.strokes[index].renderBounds
        }
        for box in page.textBoxes where selection.textBoxIDs.contains(box.id) {
            result = result.map { $0.union(box.frame) } ?? box.frame
        }
        for shape in page.shapes where selection.shapeIDs.contains(shape.id) {
            result = result.map { $0.union(shape.renderBounds) } ?? shape.renderBounds
        }

        return result
    }

    static func transformed(
        _ page: CanvasPageData,
        selection: CanvasSelection,
        scale: CGFloat = 1,
        translation: CGPoint = .zero,
        around anchor: CGPoint = .zero
    ) -> CanvasPageData {
        guard !selection.isEmpty else { return page }
        let uniformScale = max(0.25, min(scale, 4))
        let worldTransform = CGAffineTransform(
            a: uniformScale,
            b: 0,
            c: 0,
            d: uniformScale,
            tx: anchor.x * (1 - uniformScale) + translation.x,
            ty: anchor.y * (1 - uniformScale) + translation.y
        )
        var updated = page

        if let drawing = try? PKDrawing(data: page.inkDrawingData) {
            var strokes = drawing.strokes
            for index in selection.strokeIndices where strokes.indices.contains(index) {
                var stroke = strokes[index]
                stroke.transform = compose(worldTransform, with: stroke.transform)
                strokes[index] = stroke
            }
            updated.inkDrawingData = PKDrawing(strokes: strokes).dataRepresentation()
        }

        updated.textBoxes = page.textBoxes.map { box in
            guard selection.textBoxIDs.contains(box.id) else { return box }
            var moved = box
            moved.frame = box.frame.applying(worldTransform).standardized
            moved.fontSize *= uniformScale
            return moved
        }
        updated.shapes = page.shapes.map { shape in
            guard selection.shapeIDs.contains(shape.id) else { return shape }
            var moved = shape
            moved.frame = shape.frame.applying(worldTransform).standardized
            moved.lineWidth *= uniformScale
            return moved
        }
        return updated
    }

    static func strokesTouched(by scratchPath: [CGPoint], radius: CGFloat, in drawing: PKDrawing) -> Set<Int> {
        guard scratchPath.count >= 2 else { return [] }
        let xs = scratchPath.map(\.x)
        let ys = scratchPath.map(\.y)
        let scratchBounds = CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        ).insetBy(dx: -radius, dy: -radius)
        return Set(drawing.strokes.enumerated().compactMap { index, stroke in
            guard stroke.renderBounds.intersects(scratchBounds) else { return nil }
            let touched = strokeSamples(stroke).contains { sample in
                distance(sample.location, toOpenPolyline: scratchPath) <= radius + sample.radius
            }
            return touched ? index : nil
        })
    }

    static func removingStrokes(_ indices: Set<Int>, from drawing: PKDrawing) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.enumerated().compactMap { index, stroke in
            indices.contains(index) ? nil : stroke
        })
    }

    static func contains(_ rectangle: CGRect, in polygon: [CGPoint]) -> Bool {
        guard !rectangle.isNull, !rectangle.isEmpty else { return false }
        guard corners(of: rectangle).allSatisfy({ contains($0, in: polygon) }) else { return false }
        return !polygonEdges(polygon).contains { edge in
            segmentEntersInterior(edge.0, edge.1, of: rectangle)
        }
    }

    static func textContentBounds(_ box: CanvasTextBox) -> CGRect {
        let contentFrame = box.frame.insetBy(dx: 5, dy: 5)
        guard !box.text.isEmpty, contentFrame.width > 0, contentFrame.height > 0 else { return .null }
        let measured = (box.text as NSString).boundingRect(
            with: contentFrame.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: box.fontSize)],
            context: nil
        )
        return CGRect(origin: contentFrame.origin, size: measured.size).intersection(contentFrame)
    }

    private static func corners(of rectangle: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rectangle.minX, y: rectangle.minY),
            CGPoint(x: rectangle.maxX, y: rectangle.minY),
            CGPoint(x: rectangle.maxX, y: rectangle.maxY),
            CGPoint(x: rectangle.minX, y: rectangle.maxY)
        ]
    }

    static func contains(_ point: CGPoint, in polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var previous = polygon[polygon.count - 1]

        for current in polygon {
            if isOnSegment(point, from: previous, to: current) { return true }
            let crosses = (current.y > point.y) != (previous.y > point.y)
            if crosses {
                let crossingX = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < crossingX { inside.toggle() }
            }
            previous = current
        }

        return inside
    }

    private static func strokeIsContained(_ stroke: PKStroke, in polygon: [CGPoint]) -> Bool {
        guard !stroke.renderBounds.isEmpty else { return false }
        let samples = strokeSamples(stroke)
        guard !samples.isEmpty else { return false }

        for sample in samples {
            guard contains(sample.location, in: polygon), distanceToBoundary(sample.location, in: polygon) >= sample.radius + 2 else {
                return false
            }
        }
        return true
    }

    private static func strokeSamples(_ stroke: PKStroke) -> [(location: CGPoint, radius: CGFloat)] {
        let path = stroke.path
        guard path.count > 0 else { return [] }

        let transformScale = max(hypot(stroke.transform.a, stroke.transform.b), hypot(stroke.transform.c, stroke.transform.d))
        var samples: [(location: CGPoint, radius: CGFloat)] = []

        let ranges: [ClosedRange<CGFloat>]
        if stroke.mask == nil {
            ranges = [0...CGFloat(path.count - 1)]
        } else {
            ranges = stroke.maskedPathRanges
        }

        for range in ranges {
            var parameter = range.lowerBound
            while parameter <= range.upperBound {
                let point = path.interpolatedPoint(at: parameter)
                samples.append((
                    point.location.applying(stroke.transform),
                    max(point.size.width, point.size.height) * transformScale / 2 + 1
                ))
                let next = path.parametricValue(parameter, offsetBy: .distance(2))
                guard next > parameter else { break }
                parameter = next
            }

            let end = path.interpolatedPoint(at: range.upperBound)
            let location = end.location.applying(stroke.transform)
            if samples.last?.location != location {
                samples.append((location, max(end.size.width, end.size.height) * transformScale / 2 + 1))
            }
        }
        return samples
    }

    private static func distance(_ point: CGPoint, toOpenPolyline path: [CGPoint]) -> CGFloat {
        polylineSegments(path).map { distance(from: point, toSegmentFrom: $0.0, to: $0.1) }.min() ?? .infinity
    }

    private static func distanceToBoundary(_ point: CGPoint, in polygon: [CGPoint]) -> CGFloat {
        polygonEdges(polygon).map { distance(from: point, toSegmentFrom: $0.0, to: $0.1) }.min() ?? .infinity
    }

    private static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let nearest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }

    private static func polygonEdges(_ points: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard points.count >= 2 else { return [] }
        return points.indices.map { index in
            (points[index], points[(index + 1) % points.count])
        }
    }

    private static func polylineSegments(_ points: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard points.count >= 2 else { return [] }
        return (0..<(points.count - 1)).map { (points[$0], points[$0 + 1]) }
    }

    private static func segmentEntersInterior(_ start: CGPoint, _ end: CGPoint, of rectangle: CGRect) -> Bool {
        let interior = rectangle.insetBy(dx: 0.01, dy: 0.01)
        guard interior.width > 0, interior.height > 0 else { return false }

        let dx = end.x - start.x
        let dy = end.y - start.y
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        let clips = [
            (-dx, start.x - interior.minX),
            (dx, interior.maxX - start.x),
            (-dy, start.y - interior.minY),
            (dy, interior.maxY - start.y)
        ]

        for (direction, distance) in clips {
            if abs(direction) < 0.000001 {
                if distance < 0 { return false }
            } else {
                let ratio = distance / direction
                if direction < 0 {
                    lower = max(lower, ratio)
                } else {
                    upper = min(upper, ratio)
                }
                if lower > upper { return false }
            }
        }
        return upper - lower > 0.000001
    }

    private static func isOnSegment(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> Bool {
        let cross = (point.y - start.y) * (end.x - start.x) - (point.x - start.x) * (end.y - start.y)
        guard abs(cross) < 0.01 else { return false }
        return point.x >= min(start.x, end.x) - 0.01
            && point.x <= max(start.x, end.x) + 0.01
            && point.y >= min(start.y, end.y) - 0.01
            && point.y <= max(start.y, end.y) + 0.01
    }

    private static func compose(_ world: CGAffineTransform, with local: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(
            a: world.a * local.a + world.c * local.b,
            b: world.b * local.a + world.d * local.b,
            c: world.a * local.c + world.c * local.d,
            d: world.b * local.c + world.d * local.d,
            tx: world.a * local.tx + world.c * local.ty + world.tx,
            ty: world.b * local.tx + world.d * local.ty + world.ty
        )
    }
}
