import Testing
@testable import Sync

@Suite("LamportClock (doc 09)")
struct LamportClockTests {
    @Test("tick() incrémente et retourne la nouvelle valeur")
    func tickIncrements() {
        var clock = LamportClock()
        #expect(clock.tick() == 1)
        #expect(clock.tick() == 2)
        #expect(clock.value == 2)
    }

    @Test("observe() adopte max(local, reçu) + 1")
    func observeAdvancesPastReceived() {
        var clock = LamportClock(startingAt: 3)
        clock.observe(10)
        #expect(clock.value == 11)
    }

    @Test("observe() n'a pas d'effet si le compteur local est déjà en avance")
    func observeIgnoresStaleValues() {
        var clock = LamportClock(startingAt: 10)
        clock.observe(2)
        #expect(clock.value == 11, "toujours max(local, reçu) + 1, même quand reçu < local")
    }
}
