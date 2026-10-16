import SwiftUI

/// The robot's saved map: rooms colored and labeled, dock and robot marked. Tapping a room toggles it
/// in `selection` (if given).
struct MapView: View {
    let map: RobotMap
    var selection: Binding<Set<Int>>?
    var robot: MapPoint?
    /// Room names from the room list (may be newer than the names stored in the map).
    var roomNames: [Int: String] = [:]

    @State private var hoveredRoomID: Int?

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(map: map, size: geometry.size)
            ZStack(alignment: .topLeading) {
                Image(decorative: MapRenderer.image(for: map, selected: selection?.wrappedValue ?? [], hovered: hoveredRoomID), scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: layout.size.width, height: layout.size.height)
                    .offset(x: layout.origin.x, y: layout.origin.y)

                ForEach(map.rooms) { room in
                    if let x = room.x, let y = room.y {
                        Text(roomNames[room.id] ?? room.name)
                            .font(.caption.weight(isSelected(room.id) ? .bold : .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.background.opacity(0.75), in: .capsule)
                            .fixedSize()
                            .position(layout.point(x: x, y: y))
                            .allowsHitTesting(false)
                    }
                }

                if let charger = map.charger {
                    marker(systemImage: "bolt.fill", color: .green)
                        .position(layout.point(x: charger.x, y: charger.y))
                }
                if let robot {
                    marker(systemImage: "robotic.vacuum.fill", color: .accentColor)
                        .position(layout.point(x: robot.x, y: robot.y))
                        .animation(.easeInOut(duration: 1), value: robot)
                }
            }
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoveredRoomID = selection == nil ? nil : layout.roomID(at: location)
                case .ended: hoveredRoomID = nil
                }
            }
            .onTapGesture { location in
                guard let selection, let id = layout.roomID(at: location) else { return }
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

    private func isSelected(_ id: Int) -> Bool {
        selection?.wrappedValue.contains(id) == true
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

    /// Aspect-fit placement of the map image and conversions between map pixels and view points.
    private struct Layout {
        let map: RobotMap
        let scale: CGFloat
        let origin: CGPoint
        let size: CGSize

        init(map: RobotMap, size available: CGSize) {
            self.map = map
            scale = min(available.width / CGFloat(map.width), available.height / CGFloat(map.height))
            size = CGSize(width: CGFloat(map.width) * scale, height: CGFloat(map.height) * scale)
            origin = CGPoint(x: (available.width - size.width) / 2, y: (available.height - size.height) / 2)
        }

        /// Map coordinates refer to pixel centers.
        func point(x: Double, y: Double) -> CGPoint {
            CGPoint(x: origin.x + (x + 0.5) * scale, y: origin.y + (y + 0.5) * scale)
        }

        func roomID(at location: CGPoint) -> Int? {
            let x = Int(((location.x - origin.x) / scale).rounded(.down))
            let y = Int(((location.y - origin.y) / scale).rounded(.down))
            return map.roomID(x: x, y: y)
        }
    }
}

enum MapRenderer {
    /// Soft room colors; selected rooms use the accent color.
    private static let palette: [(UInt8, UInt8, UInt8)] = [
        (186, 214, 235), (198, 228, 199), (240, 214, 180), (222, 205, 234), (246, 220, 158),
        (243, 200, 205), (196, 222, 222), (225, 225, 190), (210, 210, 228),
    ]
    private static let edge: (UInt8, UInt8, UInt8) = (88, 98, 110)
    private static let floor: (UInt8, UInt8, UInt8) = (222, 222, 222)
    private static let selected: (UInt8, UInt8, UInt8) = (10, 132, 255)

    static func image(for map: RobotMap, selected selection: Set<Int>, hovered: Int?) -> CGImage {
        var rgba = [UInt8](repeating: 0, count: map.width * map.height * 4)
        for (index, value) in map.pixels.enumerated() where value != 0 {
            let room = value <= 63 ? Int(value) : (101...163).contains(value) ? Int(value) - 100 : nil
            var color: (UInt8, UInt8, UInt8)
            if (101...163).contains(value) || value == 255 {
                color = edge
            } else if let room {
                color = selection.contains(room) ? selected : palette[room % palette.count]
                if room == hovered { color = blend(color, with: selected, amount: selection.contains(room) ? 0 : 0.35) }
            } else {
                color = floor
            }
            let offset = index * 4
            rgba[offset] = color.0
            rgba[offset + 1] = color.1
            rgba[offset + 2] = color.2
            rgba[offset + 3] = 255
        }
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(
            width: map.width, height: map.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: map.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private static func blend(_ a: (UInt8, UInt8, UInt8), with b: (UInt8, UInt8, UInt8), amount: Double) -> (UInt8, UInt8, UInt8) {
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(Double(x) * (1 - amount) + Double(y) * amount) }
        return (mix(a.0, b.0), mix(a.1, b.1), mix(a.2, b.2))
    }
}

#Preview {
    @Previewable @State var selection: Set<Int> = [6]
    MapView(map: .mock, selection: $selection, robot: MapPoint(x: 12, y: 4))
        .padding()
        .frame(width: 500, height: 220)
}
