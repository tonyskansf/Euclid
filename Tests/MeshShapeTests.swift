//
//  MeshShapeTests.swift
//  EuclidTests
//
//  Created by Nick Lockwood on 06/02/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import Euclid
import XCTest

private extension Mesh {
    var isActuallyConvex: Bool {
        BSP(Mesh(polygons)) { false }.isConvex
    }
}

class MeshShapeTests: XCTestCase {
    // MARK: Fill

    func testFillClockwiseQuad() {
        let shape = Path([
            .point(0, 0),
            .point(1, 0),
            .point(1, 1),
            .point(0, 1),
            .point(0, 0),
        ])
        let mesh = Mesh.fill(shape)
        XCTAssertEqual(mesh.polygons.count, 2)
        XCTAssertEqual(mesh.polygons.first?.plane.normal, .unitZ)
    }

    func testFillAnticlockwiseQuad() {
        let shape = Path([
            .point(1, 0),
            .point(0, 0),
            .point(0, 1),
            .point(1, 1),
            .point(1, 0),
        ])
        let mesh = Mesh.fill(shape)
        XCTAssertEqual(mesh.polygons.count, 2)
        XCTAssertEqual(mesh.polygons.first?.plane.normal, -.unitZ)
    }

    func testFillSelfIntersectingPath() {
        let path = Path([
            .point(0, 0),
            .point(1, 1),
            .point(1, 0),
            .point(0, 1),
        ])
        let mesh = Mesh.fill(path)
        XCTAssert(mesh.polygons.isEmpty)
    }

    func testFillNonPlanarQuad() {
        let shape = Path([
            .point(0, 0),
            .point(1, 0),
            .point(1, 1, 1),
            .point(0, 1),
            .point(0, 0),
        ])
        let mesh = Mesh.fill(shape)
        XCTAssertEqual(mesh.polygons.count, 4)
    }

    // MARK: Lathe

    func testLatheSelfIntersectingPath() {
        let path = Path([
            .point(0, 0),
            .point(1, 1),
            .point(1, 0),
            .point(0, 1),
        ])
        let mesh = Mesh.lathe(path)
        XCTAssert(!mesh.polygons.isEmpty)
    }

    // MARK: Loft

    func testLoftParallelEdges() {
        let shapes = [
            Path.square(),
            Path.square().translated(by: Vector(0.0, 1.0, 0.0)),
        ]

        let loft = Mesh.loft(shapes)

        // Every vertex in the loft should be contained by one of our shapes
        let vertices = loft.polygons.flatMap { $0.vertices }
        XCTAssert(vertices.allSatisfy { vertex in
            shapes.contains(where: { $0.points.contains(where: { $0.position == vertex.position }) })
        })
    }

    func testLoftNonParallelEdges() {
        let shapes = [
            Path.square(),
            Path([
                PathPoint.point(-2.0, 1.0, 1.0),
                PathPoint.point(-2.0, 1.0, -1.0),
                PathPoint.point(2.0, 1.0, -1.0),
                PathPoint.point(2.0, 1.0, 1.0),
                PathPoint.point(-2.0, 1.0, 1.0),
            ]),
        ]

        let loft = Mesh.loft(shapes)

        XCTAssert(loft.polygons.allSatisfy { pointsAreCoplanar($0.vertices.map { $0.position }) })

        // Every vertex in the loft should be contained by one of our shapes
        let vertices = loft.polygons.flatMap { $0.vertices }
        XCTAssert(vertices.allSatisfy { vertex in
            shapes.contains(where: { $0.points.contains(where: { $0.position == vertex.position }) })
        })
    }

    func testExtrudeSelfIntersectingPath() {
        let path = Path([
            .point(0, 0),
            .point(1, 1),
            .point(1, 0),
            .point(0, 1),
        ])
        let mesh = Mesh.extrude(path)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(mesh, .extrude(path, faces: .frontAndBack))
    }

    func testExtrudeClosedLine() {
        let path = Path([
            .point(0, 0),
            .point(0, 1),
            .point(0, 0),
        ])
        let mesh = Mesh.extrude(path)
        XCTAssertEqual(mesh.polygons.count, 2)
        XCTAssertEqual(mesh, .extrude(path, faces: .front))
    }

    func testExtrudeOpenLine() {
        let path = Path([
            .point(0, 0),
            .point(0, 1),
        ])
        let mesh = Mesh.extrude(path)
        XCTAssertEqual(mesh.polygons.count, 2)
        XCTAssertEqual(mesh, .extrude(path, faces: .frontAndBack))
    }

    // MARK: Stroke

    func testStrokeLine() {
        let path = Path.line(Vector(-1, 0), Vector(1, 0))
        let mesh = Mesh.stroke(path, detail: 2)
        XCTAssertEqual(mesh.polygons.count, 2)
    }

    func testStrokeLineSingleSided() {
        let path = Path.line(Vector(-1, 0), Vector(1, 0))
        let mesh = Mesh.stroke(path, detail: 1)
        XCTAssertEqual(mesh.polygons.count, 1)
    }

    func testStrokeLineWithTriangle() {
        let path = Path.line(Vector(-1, 0), Vector(1, 0))
        let mesh = Mesh.stroke(path, detail: 3)
        XCTAssertEqual(mesh.polygons.count, 5)
    }

    func testStrokeSquareWithTriangle() {
        let mesh = Mesh.stroke(.square(), detail: 3)
        XCTAssertEqual(mesh.polygons.count, 12)
    }

    // MARK: Convex Hull

    func testConvexHullOfCubes() {
        let mesh1 = Mesh.cube().translated(by: Vector(-1, 0.5, 0.7))
        let mesh2 = Mesh.cube().translated(by: Vector(1, 0))
        let mesh = Mesh.convexHull(of: [mesh1, mesh2])
        XCTAssert(mesh.isKnownConvex)
        XCTAssert(mesh.isActuallyConvex)
        XCTAssert(mesh.isWatertight)
        XCTAssert(mesh.polygons.areWatertight)
        XCTAssertEqual(mesh.bounds, mesh1.bounds.union(mesh2.bounds))
        XCTAssertEqual(mesh.bounds, Bounds(polygons: mesh.polygons))
    }

    func testConvexHullOfSpheres() {
        let mesh1 = Mesh.sphere().translated(by: Vector(-1, 0.2, -0.1))
        let mesh2 = Mesh.sphere().translated(by: Vector(1, 0))
        let mesh = Mesh.convexHull(of: [mesh1, mesh2])
        XCTAssert(mesh.isKnownConvex)
        XCTAssert(mesh.isActuallyConvex)
        XCTAssert(mesh.isWatertight)
        XCTAssert(mesh.polygons.areWatertight)
        XCTAssertEqual(mesh.bounds, mesh1.bounds.union(mesh2.bounds))
        XCTAssertEqual(mesh.bounds, Bounds(polygons: mesh.polygons))
    }

    func testConvexHullOfCubeIsItself() {
        let cube = Mesh.cube()
        let mesh = Mesh.convexHull(of: [cube])
        XCTAssertEqual(cube, mesh)
        let mesh2 = Mesh.convexHull(of: cube.polygons)
        XCTAssertEqual(
            Set(cube.polygons.flatMap { $0.vertices }),
            Set(mesh2.polygons.flatMap { $0.vertices })
        )
        XCTAssertEqual(cube.polygons.count, mesh2.detessellate().polygons.count)
    }

    func testConvexHullOfNothing() {
        let mesh = Mesh.convexHull(of: [] as [Mesh])
        XCTAssertEqual(mesh, .empty)
    }

    func testConvexHullOfSingleTriangle() {
        let triangle = Polygon(unchecked: [
            Vector(0, 0),
            Vector(1, 0),
            Vector(1, 1),
        ])
        let mesh = Mesh.convexHull(of: [triangle])
        XCTAssert(mesh.isKnownConvex)
        XCTAssert(mesh.isActuallyConvex)
        XCTAssert(mesh.isWatertight)
        XCTAssert(mesh.polygons.areWatertight)
        XCTAssertEqual(mesh.bounds, triangle.bounds)
        XCTAssertEqual(mesh.bounds, Bounds(polygons: mesh.polygons))
    }

    func testConvexHullOfConcavePolygon() {
        let shape = Polygon(unchecked: [
            Vector(0, 0),
            Vector(1, 0),
            Vector(1, 1),
            Vector(0.5, 1),
            Vector(0.5, 0.5),
        ])
        let mesh = Mesh.convexHull(of: [shape])
        XCTAssert(mesh.isKnownConvex)
        XCTAssert(mesh.isActuallyConvex)
        XCTAssert(mesh.isWatertight)
        XCTAssert(mesh.polygons.areWatertight)
        XCTAssertEqual(mesh.bounds, shape.bounds)
        XCTAssertEqual(mesh.bounds, Bounds(polygons: mesh.polygons))
    }
}
