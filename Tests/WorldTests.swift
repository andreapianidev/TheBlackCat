import XCTest

final class WorldTests: XCTestCase {
    private let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                    visible: CGRect(x: 0, y: 70, width: 1440, height: 805))

    func testIntervalSubtraction() {
        let base = Interval(lo: 0, hi: 100)
        XCTAssertEqual(IntervalMath.subtract(base, [Interval(lo: 20, hi: 40)]),
                       [Interval(lo: 0, hi: 20), Interval(lo: 40, hi: 100)])
        XCTAssertEqual(IntervalMath.subtract(base, [Interval(lo: -10, hi: 200)]), [])
        XCTAssertEqual(IntervalMath.subtract(base, [Interval(lo: 100, hi: 200)]), [base])
    }

    func testQuartzToCocoa() {
        let r = ScreenSpace.cocoaRect(fromQuartz: CGRect(x: 10, y: 100, width: 300, height: 200), primaryHeight: 900)
        XCTAssertEqual(r, CGRect(x: 10, y: 600, width: 300, height: 200))
        XCTAssertEqual(ScreenSpace.quartzRect(fromCocoa: r, primaryHeight: 900), CGRect(x: 10, y: 100, width: 300, height: 200))
    }

    func testFloorAndWindowTop() {
        let w = WindowInfo(id: 1, frame: CGRect(x: 200, y: 200, width: 400, height: 300), pid: 1, owner: "Safari")
        let world = WorldBuilder.build(windows: [w], screens: [screen])
        XCTAssertEqual(world.floors.count, 1)
        XCTAssertEqual(world.floors[0].y, 70)
        let top = world.ledges.filter { $0.windowID == 1 }
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top[0].y, 500)
        XCTAssertEqual(top[0].span, Interval(lo: 200, hi: 600))
        XCTAssertEqual(world.walls.filter { $0.windowID == 1 }.count, 2)
    }

    func testFrontWindowHidesPartOfTheEdgeBehind() {
        let front = WindowInfo(id: 2, frame: CGRect(x: 350, y: 300, width: 300, height: 400), pid: 2, owner: "Mail")
        let back = WindowInfo(id: 1, frame: CGRect(x: 200, y: 200, width: 400, height: 300), pid: 1, owner: "Safari")
        let world = WorldBuilder.build(windows: [front, back], screens: [screen])
        let pieces = world.ledges.filter { $0.windowID == 1 }.map(\.span)
        XCTAssertEqual(pieces, [Interval(lo: 200, hi: 350)])
        // The back window's right side is covered by the front one where they overlap.
        let rightWall = world.walls.first { $0.windowID == 1 && $0.side == .right }
        XCTAssertNotNil(rightWall)
        XCTAssertEqual(rightWall?.span, Interval(lo: 200, hi: 300))
    }

    func testMaximisedWindowHasNoTopLedge() {
        let w = WindowInfo(id: 1, frame: CGRect(x: 0, y: 70, width: 1440, height: 805), pid: 1, owner: "Xcode")
        let world = WorldBuilder.build(windows: [w], screens: [screen])
        XCTAssertTrue(world.ledges.filter { $0.windowID == 1 }.isEmpty)
    }

    func testLandingPicksHighestCrossedLedge() {
        let w = WindowInfo(id: 1, frame: CGRect(x: 200, y: 200, width: 400, height: 300), pid: 1, owner: "Safari")
        let world = WorldBuilder.build(windows: [w], screens: [screen])
        XCTAssertEqual(world.landing(x: 300, fromY: 520, toY: 480)?.windowID, 1)
        XCTAssertNil(world.landing(x: 300, fromY: 480, toY: 100))
        XCTAssertEqual(world.landing(x: 100, fromY: 90, toY: 60)?.windowID, nil)
        XCTAssertNotNil(world.landing(x: 100, fromY: 90, toY: 60))
    }
}

final class BallisticsTests: XCTestCase {
    func testJumpLandsOnTarget() {
        let g: CGFloat = 2300
        for (a, b) in [(CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 180)),
                       (CGPoint(x: 100, y: 400), CGPoint(x: -50, y: 70)),
                       (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 240))] {
            let plan = Ballistics.plan(from: a, to: b, gravity: g, lift: 20)
            let end = Ballistics.position(of: plan, at: plan.duration, gravity: g)
            XCTAssertEqual(end.x, b.x, accuracy: 0.5)
            XCTAssertEqual(end.y, b.y, accuracy: 0.5)
            // The arc rises above both ends.
            let apex = Ballistics.position(of: plan, at: plan.velocity.dy / g, gravity: g)
            XCTAssertGreaterThanOrEqual(apex.y, max(a.y, b.y) + 19)
        }
    }
}

final class NeedsTests: XCTestCase {
    func testSleepRestoresAndTimeMakesHungry() {
        var n = Needs()
        n.energy = 0.2
        n.hunger = 0
        n.tick(3600, doing: .sleeping)
        XCTAssertGreaterThan(n.energy, 0.9)
        XCTAssertGreaterThan(n.hunger, 0.15)
    }

    func testValuesStayInRange() {
        var n = Needs()
        for _ in 0..<100 { n.tick(3600, doing: .playing) }
        for v in [n.energy, n.hunger, n.boredom, n.loneliness, n.curiosity, n.grudge] {
            XCTAssertTrue((0...1).contains(v))
        }
        n.fed()
        XCTAssertEqual(n.hunger, 0)
    }

    func testCatsAreLazyAtNoon() {
        XCTAssertLessThan(Circadian.liveliness(hour: 14), Circadian.liveliness(hour: 21))
        XCTAssertGreaterThan(Circadian.sleepiness(hour: 14), Circadian.sleepiness(hour: 6))
    }
}

final class ThoughtTextTests: XCTestCase {
    func testCleaningRemovesLongDashesAndQuotes() {
        let s = ThoughtBank.clean("«Questa finestra \u{2014} è mia»\nSeconda riga")
        XCTAssertEqual(s, "Questa finestra, è mia")
        XCTAssertNil(ThoughtBank.clean("   "))
    }

    func testCleaningShortensLongLines() {
        let long = String(repeating: "miao ", count: 40)
        let s = ThoughtBank.clean(long, maxLength: 40)!
        XCTAssertLessThanOrEqual(s.count, 43)
    }

    func testHandWrittenLinesHaveNoLongDashes() {
        let topics: [ThoughtTopic] = [.idle, .sleepy, .hungry, .fed, .petted, .thrown, .scolded, .praised, .ignoredCall,
                                      .wake, .userBack, .userGone, .night, .morning, .window(owner: "Safari"),
                                      .app(name: "Xcode"), .app(name: "Altro"), .rain, .sun, .cold, .heat, .hotMac,
                                      .lowBattery, .charging, .meeting(title: "Call", minutes: 5), .music, .dog,
                                      .otherCat, .bird, .word("tonno"), .clap, .mischief, .zoomies, .onTop]
        for t in topics {
            let lines = ThoughtBank.lines(for: t, name: "Nerone")
            XCTAssertFalse(lines.isEmpty)
            for l in lines {
                XCTAssertFalse(l.contains("\u{2014}") || l.contains("\u{2013}"), l)
            }
            XCTAssertFalse(t.situation.contains("\u{2014}"))
        }
    }
}
