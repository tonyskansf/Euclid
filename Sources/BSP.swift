//
//  BSP.swift
//  Euclid
//
//  Created by Nick Lockwood on 20/01/2020.
//  Copyright © 2020 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/Euclid
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

struct BSP {
    private var root: BSPNode?

    init(_ mesh: Mesh) {
        root = BSPNode(polygons: mesh.polygons, isConvex: mesh.isKnownConvex)
    }

    private init(root: BSPNode) {
        self.root = root
    }
}

// MARK: - Iterator
fileprivate extension BSP {
    struct BSPIterator: Sequence, IteratorProtocol {
        var stack: [BSPNode] = []
        var currentNode: BSPNode?
        var polygonIndex = 0

        init(node: BSPNode?) {
            currentNode = node
            pushChildren()
        }

        mutating func pushChildren() {
            guard let node = currentNode else {
                return
            }

            if let front = node.front {
                stack.append(front)
            }

            if let back = node.back {
                stack.append(back)
            }
        }

        mutating func next() -> Polygon? {
            guard let node = currentNode else {
                return nil
            }

            while polygonIndex >= node.polygons.count {
                if stack.isEmpty {
                    return nil
                } else {
                    currentNode = stack.popLast()!
                    polygonIndex = 0
                    pushChildren()
                }
            }

            let polygon = node.polygons[polygonIndex]
            polygonIndex += 1
            return polygon
        }

        func makeIterator() -> BSPIterator {
            self
        }
    }

    var polygons: BSPIterator {
        BSPIterator(node: root)
    }
}

extension BSP {
    enum ClipRule {
        case greaterThan
        case greaterThanEqual
        case lessThan
        case lessThanEqual
    }

    func clip(_ polygons: [Polygon], _ keeping: ClipRule) -> [Polygon] {
        var id = 0
        return root?.clip(polygons.map { $0.with(id: 0) }, keeping, &id) ?? polygons
    }

    func duplicate() -> BSP {
        self
    }

    mutating func merge(_ bsp: BSP) {
        guard root != nil else {
            self.root = bsp.duplicate().root
            return
        }

        var stack : [BSPNode] = [self.root!]
        while !stack.isEmpty {
            let node = stack.popLast()!
            if (node !== root) {
                root!.merge(node)
            }
            if node.front != nil {
                stack.append(node.front!)
            }
            if node.back != nil {
                stack.append(node.back!)
            }
        }
    }

    func translated(by translation: Vector) -> BSP {
        guard root != nil else {
            return self
        }

        return BSP(root: root!.translated(by: translation))
    }
}

private extension BSP {
    final class BSPNode {
        weak var parent: BSPNode?
        var front: BSPNode?
        var back: BSPNode?
        var polygons = [Polygon]()
        var plane: Plane

        init(plane: Plane) {
            self.plane = plane
        }

        init(polygon: Polygon) {
            self.polygons = [polygon]
            self.plane = polygon.plane
        }

        init(plane: Plane, parent: BSPNode?) {
            self.plane = plane
            self.parent = parent
        }

        init?(polygons: [Polygon], isConvex: Bool) {
            guard !polygons.isEmpty else {
                return nil
            }

            guard isConvex else {
                plane = polygons[0].plane
                insert(polygons)
                return
            }

            // Shuffle polygons to reduce average number of splits and sort by plane.
            var rng = DeterministicRNG()
            let polygons = polygons
                .shuffled(using: &rng)
                .sortedByPlane()

            // Use fast bsp construction
            plane = polygons[0].plane
            var parent = self
            parent.polygons = [polygons[0]]
            for polygon in polygons.dropFirst() {
                if polygon.plane.isEqual(to: parent.plane) {
                    parent.polygons.append(polygon)
                    continue
                }
                let node = BSPNode(plane: polygon.plane, parent: parent)
                node.polygons = [polygon]
                parent.back = node
                parent = node
            }
        }
    }

    // See https://github.com/wangyi-fudan/wyhash/
    struct DeterministicRNG: RandomNumberGenerator {
        private var seed: UInt64 = 0

        mutating func next() -> UInt64 {
            seed &+= 0xA0761D6478BD642F
            let result = seed.multipliedFullWidth(by: seed ^ 0xE7037ED1A0B428DB)
            return result.high ^ result.low
        }
    }
}

private extension BSP.BSPNode {
    func insert(_ polygons: [Polygon]) {
        var polygons = polygons
        var currentNode = self

        while !polygons.isEmpty {
            var front = [Polygon](), back = [Polygon]()

            // Split polygons by the current node's plane.
            for polygon in polygons {
                switch polygon.compare(with: currentNode.plane) {
                case .coplanar:
                    if currentNode.plane.normal.dot(polygon.plane.normal) > 0 {
                        currentNode.polygons.append(polygon)
                    } else {
                        back.append(polygon)
                    }
                case .front:
                    front.append(polygon)
                case .back:
                    back.append(polygon)
                case .spanning:
                    var id = 0
                    polygon.split(spanning: currentNode.plane, &front, &back, &id)
                }
            }

            currentNode.front = currentNode.front ?? front.first.map { BSP.BSPNode(plane: $0.plane, parent: currentNode) }
            currentNode.back = currentNode.back ?? back.first.map { BSP.BSPNode(plane: $0.plane, parent: currentNode) }

            if front.count > back.count {
                currentNode.back?.insert(back)
                polygons = front
                currentNode = currentNode.front!
            } else {
                currentNode.front?.insert(front)
                polygons = back
                currentNode = currentNode.back ?? currentNode
            }
        }
    }

    func clip(
        _ polygons: [Polygon],
        _ keeping: BSP.ClipRule,
        _ id: inout Int
    ) -> [Polygon] {
        var polygons = polygons
        var currentNode = self
        var total = [Polygon]()
        let keepFront = [.greaterThan, .greaterThanEqual].contains(keeping)

        func addPolygons(_ polygons: [Polygon]) {
            for a in polygons {
                guard a.id != 0 else {
                    total.append(a)
                    continue
                }
                var a = a
                for i in total.indices.reversed() {
                    let b = total[i]
                    if a.id == b.id, let c = a.merge(unchecked: b, ensureConvex: false) {
                        a = c
                        total.remove(at: i)
                    }
                }
                total.append(a)
            }
        }

        while !polygons.isEmpty {
            var coplanar = [Polygon](), front = [Polygon](), back = [Polygon]()

            // Split polygons by the current node's plane.
            for polygon in polygons {
                polygon.split(along: currentNode.plane, &coplanar, &front, &back, &id)
            }

            // Clip coplanar polygons with the current node's polygons based on the keeping logic.
            for polygon in coplanar {
                switch keeping {
                case .greaterThan, .lessThanEqual:
                    polygon.clip(to: currentNode.polygons, &back, &front, &id)
                case .greaterThanEqual, .lessThan:
                    if currentNode.plane.normal.dot(polygon.plane.normal) > 0 {
                        front.append(polygon)
                    } else {
                        polygon.clip(to: currentNode.polygons, &back, &front, &id)
                    }
                }
            }

            if front.count > back.count {
                addPolygons(currentNode.back?.clip(back, keeping, &id) ?? (keepFront ? [] : back))
                if currentNode.front == nil {
                    addPolygons(keepFront ? front : [])
                    return total
                }
                polygons = front
                currentNode = currentNode.front!
            } else {
                addPolygons(currentNode.front?.clip(front, keeping, &id) ?? (keepFront ? front : []))
                if currentNode.back == nil {
                    addPolygons(keepFront ? [] : back)
                    return total
                }
                polygons = back
                currentNode = currentNode.back!
            }
        }
        return total
    }

    func translated(by translation: Vector, parent: BSP.BSPNode? = nil) -> BSP.BSPNode {
        let translated = BSP.BSPNode(
            plane: self.plane.translated(by: translation),
            parent: parent
        )

        translated.polygons.append(contentsOf: polygons.map { $0.translated(by: translation) })

        if front != nil {
            translated.front = front!.translated(by: translation, parent: translated)
        }

        if back != nil {
            translated.back = back!.translated(by: translation, parent: translated)
        }
        return translated
    }

    func merge(_ node: BSP.BSPNode) {
        insert(node.polygons)
    }
}
