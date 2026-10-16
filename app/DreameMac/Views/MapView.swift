import SwiftUI

/// The robot's saved map as a clean floor plan: rooms filled and labeled, walls drawn, dock and robot
/// marked. Clicking a room toggles it in `selection` (if given). With `editRects`, shows handles on
/// every room wall to drag it instead (floor plan editor).
struct MapView: View {
    let map: RobotMap
    var selection: Binding<Set<Int>>?
    var robot: MapPoint?
    /// Room names from the room list (may be newer than the names stored in the map).
    var roomNames: [Int: String] = [:]
    /// Edit mode: called with all room rectangles whenever a wall is dragged.
    var editRects: (([Int: MapRect]) -> Void)?

    @State private var hoveredRoomID: Int?
    @State private var drag: WallDrag?

    private struct WallDrag {
        let walls: [(Int, RectEdge)]
        let startRects: [Int: MapRect]
    }

    private var isEditing: Bool { editRects != nil }
    @Environment(\.colorScheme) private var colorScheme

    /// Soft room hues; drawn translucent over the floor so they work in light and dark mode.
    private static let palette: [Color] = [
        .blue, .green, .orange, .purple, .yellow, .pink, .teal, .mint, .indigo,
    ]

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(map: map, size: geometry.size)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(in: &context, layout: layout) }

                ForEach(map.rooms) { room in
                    label(for: room)
                        .position(layout.point(room.x, room.y))
                }
                if let charger = map.charger, !isEditing {
                    marker(systemImage: "bolt.fill", color: .green)
                        .position(layout.point(charger.x, charger.y))
                }
                if isEditing {
                    wallHandles(layout: layout)
                } else if let robot {
                    marker(systemImage: "robotic.vacuum.fill", color: .accentColor)
                        .position(layout.point(robot.x, robot.y))
                        .animation(.easeInOut(duration: 1), value: robot)
                }
            }
            .coordinateSpace(.named(Self.space))
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoveredRoomID = selection == nil || isEditing ? nil : map.roomID(at: layout.mapPoint(location))
                case .ended: hoveredRoomID = nil
                }
            }
            .onTapGesture { location in
                guard !isEditing, let selection, let id = map.roomID(at: layout.mapPoint(location)) else { return }
                if selection.wrappedValue.contains(id) {
                    selection.wrappedValue.remove(id)
                } else {
                    selection.wrappedValue.insert(id)
                }
            }
        }
        .aspectRatio(CGFloat(map.width) / CGFloat(map.height), contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map")
    }

    private func draw(in context: inout GraphicsContext, layout: Layout) {
        let home = map.rooms.reduce(Path()) { $0.union(layout.path($1.outline), eoFill: true) }
        let floor = colorScheme == .dark ? Color(white: 0.17) : .white
        let wallWidth = max(2, layout.scale * 0.9)

        var shadow = context
        shadow.addFilter(.shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12), radius: 10, y: 4))
        shadow.fill(home, with: .color(floor))

        for room in map.rooms {
            let path = layout.path(room.outline)
            let selected = selection?.wrappedValue.contains(room.id) == true
            let tint = Self.palette[room.id % Self.palette.count]
            context.fill(path, with: .color(selected ? .accentColor.opacity(0.75) : tint.opacity(0.22)), style: FillStyle(eoFill: true))
            if room.id == hoveredRoomID && !selected {
                context.fill(path, with: .color(.accentColor.opacity(0.18)), style: FillStyle(eoFill: true))
            }
        }
        // Interior walls: thin floor-colored lines where rooms meet; then the exterior wall on top.
        for room in map.rooms {
            context.stroke(layout.path(room.outline), with: .color(floor), style: StrokeStyle(lineWidth: wallWidth * 0.6, lineJoin: .round))
        }
        context.stroke(home, with: .color(.primary.opacity(0.8)), style: StrokeStyle(lineWidth: wallWidth, lineJoin: .round))
    }

    private static let space = "map"

    private struct WallHandle: Identifiable {
        let id: String
        let roomID: Int
        let edge: RectEdge
        let line: Double
        let middle: Double
    }

    /// One handle per wall; a wall shared by two rooms gets a single handle in the middle of the shared
    /// part. Dragging moves the wall (and walls flush with it).
    private func wallHandles(layout: Layout) -> some View {
        let rects = Dictionary(uniqueKeysWithValues: map.rooms.compactMap { room in room.rect.map { (room.id, $0) } })
        var handles: [WallHandle] = []
        var seen = Set<String>()
        for (id, rect) in rects.sorted(by: { $0.key < $1.key }) {
            for edge in RectEdge.allCases {
                let walls = FloorPlanEditing.linkedEdges(of: id, edge, in: rects)
                let key = walls.map { "\($0.0)-\($0.1)" }.sorted().joined(separator: ",")
                guard seen.insert(key).inserted else { continue }
                // Place the handle on the longest room edge of the wall, in its middle.
                let (longestID, longestEdge) = walls.max { a, b in
                    let sa = a.1.span(of: rects[a.0]!), sb = b.1.span(of: rects[b.0]!)
                    return sa.upperBound - sa.lowerBound < sb.upperBound - sb.lowerBound
                }!
                let span = longestEdge.span(of: rects[longestID]!)
                handles.append(WallHandle(
                    id: key, roomID: id, edge: edge, line: edge.value(of: rect),
                    middle: (span.lowerBound + span.upperBound) / 2
                ))
            }
        }
        return ForEach(handles) { handle in
            let id = handle.roomID, edge = handle.edge, line = handle.line, middle = handle.middle
            Capsule()
                .fill(Color.accentColor)
                .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                .frame(width: edge.isVertical ? 7 : 28, height: edge.isVertical ? 28 : 7)
                .shadow(radius: 1.5)
                .padding(6)  // larger hit area
                .contentShape(.rect)
                .position(edge.isVertical ? layout.point(line, middle) : layout.point(middle, line))
                .pointerStyle(.frameResize(position: edge.resizePosition))
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                        .onChanged { value in
                            // ⌥ Option: move only this room's wall, detaching it from its neighbors.
                            let current = drag ?? WallDrag(
                                walls: NSEvent.modifierFlags.contains(.option)
                                    ? [(id, edge)] : FloorPlanEditing.linkedEdges(of: id, edge, in: rects),
                                startRects: rects
                            )
                            drag = current
                            let location = layout.mapPoint(value.location)
                            let target = FloorPlanEditing.snap(
                                edge.isVertical ? location.x : location.y,
                                vertical: edge.isVertical,
                                excluding: current.walls,
                                in: current.startRects,
                                tolerance: 8 / layout.scale
                            )
                            editRects?(FloorPlanEditing.move(current.walls, to: target, in: current.startRects))
                        }
                        .onEnded { _ in drag = nil }
                )
                .help("Drag to move this wall. Hold ⌥ to move only this room's side.")
        }
    }

    private func label(for room: MapRoom) -> some View {
        let selected = selection?.wrappedValue.contains(room.id) == true
        return VStack(spacing: 0) {
            Text(roomNames[room.id] ?? room.name)
                .font(.caption.weight(.semibold))
            Text("\(room.area, format: .number.precision(.fractionLength(0))) m²")
                .font(.caption2)
                .opacity(0.7)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .fixedSize()
        .allowsHitTesting(false)
    }

    private func marker(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
            .allowsHitTesting(false)
    }

    /// Aspect-fit placement of the map and conversions between map and view coordinates.
    private struct Layout {
        let scale: CGFloat
        let origin: CGPoint

        init(map: RobotMap, size available: CGSize) {
            scale = min(available.width / CGFloat(map.width), available.height / CGFloat(map.height))
            origin = CGPoint(
                x: (available.width - CGFloat(map.width) * scale) / 2,
                y: (available.height - CGFloat(map.height) * scale) / 2
            )
        }

        /// Map coordinates are pixel indices; draw at pixel centers.
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + (x + 0.5) * scale, y: origin.y + (y + 0.5) * scale)
        }

        func mapPoint(_ location: CGPoint) -> MapPoint {
            MapPoint(x: (location.x - origin.x) / scale - 0.5, y: (location.y - origin.y) / scale - 0.5)
        }

        func path(_ rings: [MapRing]) -> Path {
            var path = Path()
            for ring in rings where ring.points.count > 2 {
                path.addLines(ring.points.map { point($0.x, $0.y) })
                path.closeSubpath()
            }
            return path
        }
    }
}

private extension RectEdge {
    var resizePosition: FrameResizePosition {
        switch self {
        case .left: .leading
        case .top: .top
        case .right: .trailing
        case .bottom: .bottom
        }
    }
}

#Preview {
    @Previewable @State var selection: Set<Int> = [6]
    MapView(map: .mock, selection: $selection, robot: MapPoint(x: 12, y: 2))
        .padding()
        .frame(width: 500, height: 220)
}
