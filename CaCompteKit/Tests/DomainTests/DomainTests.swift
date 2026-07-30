import Testing

@Suite("Fondations")
struct FoundationsTests {
    @Test("Le package se charge")
    func packageLoads() {
        #expect(1 + 1 == 2)
    }
}
