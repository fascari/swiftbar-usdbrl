import AppKit

import Combine
import SwiftUI

enum KeypadTarget: Identifiable {
    case payment(UUID)
    case simulation

    var id: String {
        switch self {
        case .payment(let id): return id.uuidString
        case .simulation: return "simulation"
        }
    }
}

@MainActor
struct ConverterView: View {
    private enum Field: Hashable {
        case name(UUID)
        case amount(UUID)

        var payment: UUID {
            switch self {
            case .name(let id), .amount(let id): return id
            }
        }
    }
    @ObservedObject var draft: ConverterModel
    @FocusState private var focusedField: Field?

    private let accent = Color(red: 0.03, green: 0.48, blue: 0.43)

    private var language: Locale { Locale(identifier: draft.portuguese ? "pt_BR" : "en_US") }

    private var total: Decimal? {
        guard let rate = draft.rate, !draft.payments.isEmpty else { return nil }
        let amounts = draft.payments.compactMap { draft.amount($0.amount) }
        let results = amounts.compactMap { converted($0, rate: rate) }
        let total = results.reduce(Decimal.zero, +)
        guard results.count == amounts.count, total <= Decimal(Int64.max) / 100 else { return nil }
        return total
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heading
                summary
                paymentEditor
                simulationEditor
                if let error = draft.error {
                    Text(errorMessage(error)).font(.footnote).foregroundColor(.orange)
                    if error == "conflict" {
                        Button(draft.text("Descartar edições e recarregar", "Discard edits and reload")) { draft.reload() }
                    }
                }
                Text(draft.text("A taxa de referência pode diferir da taxa no momento do saque.",
                                "The reference rate may differ from the rate at withdrawal."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .sheet(item: $draft.keypad) { target in
            NumericKeypad(value: keypadValue(target), portuguese: draft.portuguese, normalize: draft.keypadText) {
                draft.keypad = nil
                if case .payment(let id) = target { draft.save(id) }
            }
                .tint(accent)
        }
        .onChange(of: focusedField) { new in
            if let old = previousFocus.field, old.payment != new?.payment, draft.keypad == nil {
                draft.save(old.payment)
            }
            previousFocus.field = new
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @StateObject private var previousFocus = PreviousFocus()

    private final class PreviousFocus: ObservableObject {
        var field: Field?
    }

    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(draft.text("Conversor de pagamentos", "Payment converter")).font(.largeTitle.bold())
                Text("\(draft.providerName)  ·  \(draft.currency) → BRL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.text("Total mensal estimado", "Estimated monthly total")).font(.subheadline.weight(.medium))
                    Text(total.map(money) ?? "—")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                Button(draft.text("Atualizar cotação", "Update rate")) { draft.refresh() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(!draft.ready || draft.busy)
            }
            Divider().overlay(.white.opacity(0.25))
            HStack(alignment: .top, spacing: 32) {
                rateLabel(draft.text("Taxa efetiva", "Effective rate"), value: draft.rate, unit: draft.currency)
                rateLabel(draft.text("Dólar comercial", "USD/BRL market rate"), value: draft.market, unit: "USD")
                Spacer()
                if let checked = draft.checked {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(draft.stale ? draft.text("Cotação desatualizada", "Rate is out of date") :
                             draft.text("Última consulta", "Last checked"))
                        Text(checked.formatted(date: .abbreviated, time: .shortened))
                    }.font(.caption)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.33, blue: 0.32), accent],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private func rateLabel(_ label: String, value: Decimal?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).opacity(0.90)
            Text(value.map { $0.formatted(.currency(code: "BRL").precision(.fractionLength(4)).locale(language)) + " / \(unit)" } ?? "—")
                .font(.body.weight(.semibold).monospacedDigit())
        }
    }

    private var paymentEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(draft.text("Pagamentos mensais", "Monthly payments")).font(.title3.bold())
                Spacer()
                if draft.removed != nil {
                    Button(draft.text("Desfazer remoção", "Undo removal")) { draft.undo() }
                }
                Button {
                    focusedField = .amount(draft.add())
                } label: {
                    Label(draft.text("Adicionar pagamento", "Add payment"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            VStack(spacing: 10) {
                HStack {
                    columnTitle(draft.text("Nome (opcional)", "Name (optional)")).frame(maxWidth: .infinity, alignment: .leading)
                    columnTitle(draft.text("Valor em", "Amount in") + " " + draft.currency).frame(width: 135, alignment: .leading)
                    columnTitle(draft.text("Estimativa em BRL", "Estimate in BRL")).frame(width: 146, alignment: .trailing)
                    Color.clear.frame(width: 27, height: 1)
                }
                ForEach($draft.payments) { $payment in
                    let index = draft.payments.firstIndex { $0.id == payment.id } ?? 0
                    HStack {
                        TextField(draft.text("Pagamento", "Payment") + " \(index + 1)", text: $payment.name)
                            .focused($focusedField, equals: .name(payment.id))
                            .onSubmit { draft.save(payment.id) }
                        HStack(spacing: 4) {
                            TextField("0,00", text: $payment.amount)
                                .focused($focusedField, equals: .amount(payment.id))
                                .onSubmit { draft.save(payment.id) }
                            keypadButton(
                                .payment(payment.id),
                                label: "Teclado do pagamento \(index + 1)"
                            )
                        }
                        .frame(width: 135)
                        Text(output(payment.amount))
                            .foregroundStyle(draft.amount(payment.amount) != nil ? Color.primary : Color.secondary)
                            .monospacedDigit()
                            .frame(width: 146, alignment: .trailing)
                        if draft.canSave(payment) {
                            Button {
                                draft.save(payment.id)
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help(draft.text("Salvar pagamento", "Save payment"))
                        }
                        Button(role: .destructive) {
                            draft.remove(payment.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .frame(width: 27)
                        .help(draft.text("Remover pagamento", "Remove payment"))
                    }
                    .textFieldStyle(.roundedBorder)
                }
                if draft.payments.isEmpty {
                    Text(draft.text("Adicione um pagamento para calcular o total.", "Add a payment to calculate the total."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(15)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
        }
        .disabled(!draft.ready || draft.busy)
    }

    private var simulationEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(draft.text("Simulação avulsa", "Quick simulation")).font(.title3.bold())
                Spacer()
                Text(draft.text("Não entra no total", "Excluded from the total")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    TextField("0,00", text: $draft.simulation)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Valor da simulação avulsa em USDC")
                        .onChange(of: draft.simulation) { [previous = draft.simulation] text in
                            let amount = text.trimmingCharacters(in: .whitespaces)
                            if amount.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789.,").inverted) != nil {
                                draft.simulation = previous
                            }
                        }
                    keypadButton(.simulation, label: "Teclado da simulação")
                }
                .frame(width: 135)
                Text(draft.currency).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(output(draft.simulation))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Spacer()
            }
            .padding(15)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
        }
    }

    private func columnTitle(_ title: String) -> Text {
        Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
    }

    private var calculatorIcon: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .frame(width: 8, height: 3)
            ForEach(0..<2) { _ in
                HStack(spacing: 2) {
                    Circle().frame(width: 2.5, height: 2.5)
                    Circle().frame(width: 2.5, height: 2.5)
                }
            }
        }
        .frame(width: 12, height: 16)
        .background(RoundedRectangle(cornerRadius: 2).strokeBorder(lineWidth: 1))
        .frame(width: 25, height: 23)
        .contentShape(Rectangle())
    }

    private func paymentAmount(_ id: UUID) -> Binding<String> {
        Binding {
            draft.payments.first { $0.id == id }?.amount ?? ""
        } set: { text in
            if let index = draft.payments.firstIndex(where: { $0.id == id }) {
                draft.payments[index].amount = text
            }
        }
    }

    private func keypadValue(_ target: KeypadTarget) -> Binding<String> {
        switch target {
        case .payment(let id): return paymentAmount(id)
        case .simulation: return $draft.simulation
        }
    }

    private func keypadButton(_ target: KeypadTarget, label: String) -> some View {
        Button {
            draft.keypad = target
        } label: {
            calculatorIcon
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help("Abrir teclado numérico")
        .accessibilityLabel(label)
    }

    private func converted(_ amount: Decimal, rate: Decimal) -> Decimal? {
        var exact = amount * rate
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &exact, 2, .plain)
        guard rounded <= Decimal(Int64.max) / 100 else { return nil }
        return rounded
    }

    private func output(_ input: String) -> String {
        guard let rate = draft.rate, let amount = draft.amount(input),
              let result = converted(amount, rate: rate) else { return "—" }
        return money(result)
    }

    private func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: "BRL").locale(language))
    }

    private func errorMessage(_ error: String) -> String {
        switch error {
        case "rate": return draft.text("Falha ao consultar a cotação.", "Could not update the rate.")
        case "conflict": return draft.text("O pagamento mudou em outra janela.", "The payment changed in another window.")
        case "pending": return draft.text("Conclua as edições antes de trocar de provedor.", "Finish editing before switching providers.")
        case "invalid": return draft.text("Confira o nome e o valor do pagamento.", "Check the payment name and amount.")
        default: return draft.text("Não foi possível acessar o estado do plugin.", "Could not access plugin state.")
        }
    }
}

private final class KeypadEntry: ObservableObject {
    @Published var replacesValue = true
}

private struct NumericKeypad: View {
    @Binding var value: String
    let portuguese: Bool
    let normalize: (String) -> String
    let finish: () -> Void
    @StateObject private var entry = KeypadEntry()

    private var rows: [[String]] { [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
        [portuguese ? "," : ".", "0", "⌫"]
    ] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(portuguese ? "Teclado numérico" : "Numeric keypad").font(.headline)
            Text(value.isEmpty ? "0" : value)
                .font(.title2.monospacedDigit())
                .padding(.horizontal, 6)
                .background(entry.replacesValue && !value.isEmpty ? Color.accentColor.opacity(0.25) : .clear)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
                .accessibilityLabel("Valor: \(value)")
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Text(key)
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.primary)
                        .accessibilityLabel(key == "⌫" ? "Apagar último caractere" : key)
                    }
                }
            }
            HStack {
                Button(portuguese ? "Limpar" : "Clear") {
                    value = ""
                    entry.replacesValue = false
                }
                    .foregroundColor(.primary)
                    .tint(Color.primary)
                Spacer()
                Button(portuguese ? "Concluir" : "Done", action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 250)
    }

    private func press(_ key: String) {
        if key == "⌫" {
            if entry.replacesValue { value = normalize(value) }
            if !value.isEmpty { value.removeLast() }
            entry.replacesValue = false
            return
        }
        let separator = key == "," || key == "."
        if entry.replacesValue {
            value = separator ? "0" + key : key
            entry.replacesValue = false
            return
        }
        if separator {
            if !value.contains(","), !value.contains(".") {
                value += value.isEmpty ? "0" + key : key
            }
            return
        }
        let candidate = value + key
        if candidate.range(of: #"^[0-9]{1,18}([,.][0-9]{1,2})?$"#, options: .regularExpression) != nil {
            value = candidate
        }
    }
}
