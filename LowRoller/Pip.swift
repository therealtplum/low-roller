// UI/Pip.swift
import SwiftUI

struct Pip: View {
    var size: CGFloat
    var body: some View {
        Circle()
            .frame(width: size, height: size)
            .foregroundStyle(.white)
    }
}

struct DiceView: View {
    let face: Int
    var selected: Bool = false
    var size: CGFloat = 54

    var body: some View {
        let pip = max(8, size * 0.14)
        ZStack {
            RoundedRectangle(cornerRadius: max(8, size * 0.18))
                .fill(
                    LinearGradient(colors: [
                        Color(red:0.11,green:0.19,blue:0.24),
                        Color(red:0.08,green:0.13,blue:0.17)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: max(8, size * 0.18))
                        .stroke(selected ? .yellow : .white.opacity(0.15), lineWidth: selected ? 2 : 1)
                )
                .shadow(radius: selected ? 6 : 2)

            pipGrid(face)
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: face)
    }

    @ViewBuilder
    private func pipGrid(_ n: Int) -> some View {
        let grid = gridFor(n)
        VStack(spacing: size * 0.14) {
            ForEach(0..<3, id:\.self) { r in
                HStack(spacing: size * 0.14) {
                    ForEach(0..<3, id:\.self) { c in
                        if grid[r][c] == 1 {
                            Pip(size: max(8, size * 0.14))
                        } else {
                            Color.clear.frame(width: max(8, size * 0.14), height: max(8, size * 0.14))
                        }
                    }
                }
            }
        }
    }

    private func gridFor(_ n: Int) -> [[Int]] {
        switch n {
        case 1: return [[0,0,0],[0,1,0],[0,0,0]]
        case 2: return [[1,0,0],[0,0,0],[0,0,1]]
        case 3: return [[1,0,0],[0,1,0],[0,0,1]]   // (3 scores 0)
        case 4: return [[1,0,1],[0,0,0],[1,0,1]]
        case 5: return [[1,0,1],[0,1,0],[1,0,1]]
        default: return [[1,1,1],[0,0,0],[1,1,1]]  // 6
        }
    }
}
