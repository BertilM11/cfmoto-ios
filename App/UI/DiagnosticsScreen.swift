// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UIKit

/// Diagnóstico en vivo y exportación del informe técnico.
struct DiagnosticsScreen: View {
    @State private var sections: [Diagnostics.Section] = []
    @State private var report = ""
    @State private var copied = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        DarkPage(title: "Diagnóstico") {
            Text("Se actualiza cada segundo. Para las pruebas con el iPhone bloqueado: inicia la ruta, bloquea, desbloquea y exporta el informe; el registro guarda una línea [DIAG] cada 10 s.")
                .font(.footnote).foregroundColor(Brand.dim)
            HStack(spacing: 10) {
                ShareLink(item: report, subject: Text("Informe de MotoLink"), message: Text("Informe técnico de MotoLink")) {
                    Label("Exportar informe", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.blue)
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Brand.blue)
            }
            Text("El informe no incluye contraseñas, permisos de Spotify ni tu Client ID, y la posición va redondeada a unos 100 m.")
                .font(.caption).foregroundColor(Brand.dim)
            ForEach(sections) { section in
                Card {
                    Text(section.title).font(.headline)
                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if !row.label.isEmpty {
                                Text(row.label).font(.caption).foregroundColor(Brand.dim)
                                    .frame(width: 128, alignment: .leading)
                            }
                            Text(row.value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(row.warn ? .orange : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        sections = Diagnostics.shared.sections()
        report = Diagnostics.shared.report()
    }
}
