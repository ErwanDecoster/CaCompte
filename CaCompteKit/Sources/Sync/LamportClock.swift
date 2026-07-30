/// Doc 09 — un compteur par pair : `tick()` à chaque événement émis, `observe(_:)` à chaque
/// événement reçu. Le tri final se fait sur `(lamport, deviceID)`, jamais sur l'horloge murale.
struct LamportClock: Sendable, Equatable {
    private(set) var value: UInt64

    init(startingAt value: UInt64 = 0) {
        self.value = value
    }

    mutating func tick() -> UInt64 {
        value += 1
        return value
    }

    mutating func observe(_ received: UInt64) {
        value = max(value, received) + 1
    }
}
