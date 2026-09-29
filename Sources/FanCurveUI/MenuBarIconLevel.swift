/// The menubar wheel's level (0…5) for a given fan speed. Below 5% is 0; above that, one
/// level per 20% of the controllable range (5-20% -> 1, 20-40% -> 2, 40-60% -> 3, 60-80% -> 4,
/// 80-100% -> 5). A 2% hysteresis against `previous` keeps the level from flickering right on a
/// boundary: it only moves once `percent` has crossed the boundary by at least 2%.
func fanIconLevel(percent: Double, previous: Int) -> Int {
    // Lower edges of levels 1...5.
    let boundaries: [Double] = [5, 20, 40, 60, 80]
    let hysteresis = 2.0
    var level = min(max(previous, 0), boundaries.count)
    while level < boundaries.count, percent >= boundaries[level] + hysteresis {
        level += 1
    }
    while level > 0, percent <= boundaries[level - 1] - hysteresis {
        level -= 1
    }
    return level
}
