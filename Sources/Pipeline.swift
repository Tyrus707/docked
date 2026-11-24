import Foundation

// The engine says nothing during its pipeline step, but it works through a list in parts of 1,000 and leaves a file after each.
enum Pipeline {
    static let part = 1000

    // How many parts the list makes. Read once: the list is up to a few hundred MB, so it is mapped, not loaded.
    static func total(_ work: URL) -> Int? {
        guard let d = try? Data(contentsOf: work.appendingPathComponent("pso/mac-work/bases.mtl4-json"), options: .alwaysMapped), !d.isEmpty else { return nil }
        let key = Array("vertex_function".utf8)
        let n: Int = d.withUnsafeBytes { raw in
            guard var p = raw.baseAddress else { return 0 }
            var left = raw.count, n = 0
            while let f = memmem(p, left, key, key.count) { n += 1; let step = p.distance(to: f) + key.count; p = p.advanced(by: step); left -= step }
            return n
        }
        return n > 0 ? (n + part - 1) / part : nil
    }

    // Parts are made in order, so the highest one written since the step began says how far it is.
    static func done(_ work: URL, since: Date) -> Int {
        let fm = FileManager.default, dir = work.appendingPathComponent("pso/mac-work")
        var best = 0
        for b in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []) where b.hasPrefix("batches.") {
            for n in ((try? fm.contentsOfDirectory(atPath: dir.path + "/" + b)) ?? []) {
                guard let k = Int(n), k > best else { continue }
                let f = dir.path + "/" + b + "/" + n
                for a in ((try? fm.contentsOfDirectory(atPath: f)) ?? []) where a.hasSuffix(".mtl4a") {
                    if let m = (try? fm.attributesOfItem(atPath: f + "/" + a))?[.modificationDate] as? Date, m >= since { best = k }
                }
            }
        }
        return best
    }
}
