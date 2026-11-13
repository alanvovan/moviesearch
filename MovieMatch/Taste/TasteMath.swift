//
//  TasteMath.swift
//  MovieMatch
//

import Foundation

/// Плотная симметричная матрица d×d по строкам. Размер модели вкуса — 29, поэтому без BLAS.
nonisolated enum TasteMath {
    static func normalCDF(_ x: Double) -> Double {
        guard x.isFinite else { return x > 0 ? 1 : 0 }
        return 0.5 * erfc(-x / 2.0.squareRoot())
    }

    /// Разложение Холецкого A = L·Lᵀ. Диагональ подпирается снизу, чтобы матрица оставалась положительно определённой.
    static func cholesky(_ a: [Double], size n: Int) -> [Double] {
        var l = [Double](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in 0...i {
                var sum = a[i * n + j]
                for k in 0..<j {
                    sum -= l[i * n + k] * l[j * n + k]
                }
                if i == j {
                    l[i * n + i] = max(sum, 1e-12).squareRoot()
                } else {
                    l[i * n + j] = sum / l[j * n + j]
                }
            }
        }
        return l
    }

    /// Решает L·Lᵀ·x = b.
    static func solve(cholesky l: [Double], size n: Int, _ b: [Double]) -> [Double] {
        var y = b
        for i in 0..<n {
            var sum = y[i]
            for k in 0..<i { sum -= l[i * n + k] * y[k] }
            y[i] = sum / l[i * n + i]
        }
        var x = y
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = x[i]
            for k in (i + 1)..<n { sum -= l[k * n + i] * x[k] }
            x[i] = sum / l[i * n + i]
        }
        return x
    }

    static func inverse(cholesky l: [Double], size n: Int) -> [Double] {
        var result = [Double](repeating: 0, count: n * n)
        var unit = [Double](repeating: 0, count: n)
        for column in 0..<n {
            unit[column] = 1
            let x = solve(cholesky: l, size: n, unit)
            unit[column] = 0
            for row in 0..<n { result[row * n + column] = x[row] }
        }
        for i in 0..<n {
            for j in 0..<i {
                let mean = (result[i * n + j] + result[j * n + i]) / 2
                result[i * n + j] = mean
                result[j * n + i] = mean
            }
        }
        return result
    }

    static func dot(_ a: [Double], _ b: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<min(a.count, b.count) { sum += a[i] * b[i] }
        return sum
    }

    static func quadratic(_ m: [Double], size n: Int, _ x: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<n where x[i] != 0 {
            var row = 0.0
            for j in 0..<n where x[j] != 0 { row += m[i * n + j] * x[j] }
            sum += x[i] * row
        }
        return sum
    }

    /// Детерминированная стандартная нормальная величина по ключу (Бокс — Мюллер над splitmix64).
    static func gaussian(seed: UInt64) -> Double {
        var state = seed
        func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return (Double(z >> 11) + 0.5) / Double(1 << 53)
        }
        let u1 = next()
        let u2 = next()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
