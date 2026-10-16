import SwiftUI

/// The robot's saved map as a clean floor plan: rooms filled and labeled, walls drawn, dock and robot
/// marked. Clicking a room toggles it in `selection` (if given).
struct MapView: View {
    let map: RobotMap
    var selection: Binding<Set<Int>>?
    var robot: MapPoint?
    /// Room names from the room list (may be newer than the names stored in the map).
    var roomNames: [Int: String] = [:]

    @State private var hoveredRoomID: Int?
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
                if let charger = map.charger {
                    marker(systemImage: "bolt.fill", color: .green)
                        .position(layout.point(charger.x, charger.y))
                }
                if let robot {
                    marker(systemImage: "robotic.vacuum.fill", color: .accentColor)
                        .position(layout.point(robot.x, robot.y))
                        .animation(.easeInOut(duration: 1), value: robot)
                }
            }
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoveredRoomID = selection == nil ? nil : map.roomID(at: layout.mapPoint(location))
                case .ended: hoveredRoomID = nil
                }
            }
            .onTapGesture { location in
                guard let selection, let id = map.roomID(at: layout.mapPoint(location)) else { return }
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

#Preview {
    @Previewable @State var selection: Set<Int> = [6]
    MapView(map: .mock, selection: $selection, robot: MapPoint(x: 12, y: 2))
        .padding()
        .frame(width: 500, height: 220)
}
