import SwiftUI

struct LeaderRow: View {
    let rank: Int
    let entry: LeaderEntry
    let metric: LeaderMetric
    private let startingBankroll = 10_000  // $100 in cents
    var onDelete: (() -> Void)? = nil   // optional trailing delete handler

    // MARK: - Formatters
    private func currencyString(cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = dollars.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return nf.string(from: NSNumber(value: dollars)) ?? "$\(Int(dollars))"
    }

    private var rightText: String {
        switch metric {
        case .dollars: return currencyString(cents: entry.dollarsWonCents)
        case .wins:    return "\(entry.gamesWon)"
        case .streak:  return "\(entry.longestStreak)"
        case .balance: return currencyString(cents: entry.bankrollCents)
        }
    }

    private var metricIconName: String {
        switch metric {
        case .dollars: return "dollarsign.circle.fill"
        case .wins:    return "trophy.fill"
        case .streak:  return "flame.fill"
        case .balance: return "creditcard.fill"
        }
    }

    // MARK: - Color logic (only for Current Balance)
    private var balanceStyle: AnyShapeStyle {
        guard metric == .balance else { return AnyShapeStyle(.primary) }
        if entry.bankrollCents < 0 {
            return AnyShapeStyle(Color.red)
        } else if entry.bankrollCents > startingBankroll {
            return AnyShapeStyle(Color.green)
        } else {
            return AnyShapeStyle(.primary) // black in light, white in dark
        }
    }

    // MARK: - Body
    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank).")
                .font(.headline)
                .frame(width: 28, alignment: .trailing)

            // Icon + name
            HStack(spacing: 8) {
                Image(systemName: metricIconName)
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
                    .accessibilityHidden(true)
                Text(entry.name)
                    .font(.headline)
            }

            Spacer()

            // Big metric value
            Text(rightText)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(balanceStyle)
                .accessibilityLabel({
                    switch metric {
                    case .dollars: return Text("Total dollars won \(rightText)")
                    case .wins:    return Text("Total wins \(rightText)")
                    case .streak:  return Text("Longest streak \(rightText)")
                    case .balance: return Text("Current balance \(rightText)")
                    }
                }())

            // Trailing overflow menu — only if handler provided
            if let onDelete = onDelete {
                Menu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                        .padding(.leading, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }
}
