import PrismCore
import SwiftUI

struct ProfilesTab: View {
    @EnvironmentObject var model: AppModel
    @Local private var selected: String?
    @Local private var newName = ""
    @Local private var showNew = false
    @Local private var duplicate = true
    @Local private var renaming: String?
    @Local private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profiles hold lighting, key colors, remaps, macros and alert settings. Export them to move your setup to another Mac.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                List(model.profileNames, id: \.self, selection: $selected) { name in
                    HStack {
                        Image(systemName: name == model.settings.activeProfile ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(name == model.settings.activeProfile ? Color.accentColor : .secondary)
                        Text(name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.switchProfile(name) }
                }
                .frame(width: 260, height: 360)

                VStack(alignment: .leading, spacing: 8) {
                    Button { model.switchProfile(selected ?? "") } label: { Label("Use profile", systemImage: "checkmark") }
                        .disabled(selected == nil || selected == model.settings.activeProfile)
                    Button { duplicate = false; newName = ""; showNew = true } label: { Label("New…", systemImage: "plus") }
                    Button { duplicate = true; newName = "\(model.settings.activeProfile) copy"; showNew = true } label: { Label("Duplicate current…", systemImage: "plus.square.on.square") }
                    Button { renaming = selected; renameText = selected ?? "" } label: { Label("Rename…", systemImage: "pencil") }
                        .disabled(selected == nil)
                    Button(role: .destructive) { if let s = selected { model.deleteProfile(s); selected = nil } } label: { Label("Delete", systemImage: "trash") }
                        .disabled(selected == nil || selected == model.settings.activeProfile)
                    Divider().frame(width: 200)
                    Button { model.importProfiles() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                    Button { model.exportProfiles(selected.map { [$0] }) } label: { Label("Export selected…", systemImage: "square.and.arrow.up") }
                        .disabled(selected == nil)
                    Button { model.exportProfiles(nil) } label: { Label("Export all…", systemImage: "square.and.arrow.up.on.square") }
                }
                .buttonStyle(.borderless)
                Spacer()
            }
        }
        .onAppear { model.refreshProfiles() }
        .sheet(isPresented: $showNew) {
            NameSheet(title: duplicate ? "Duplicate profile" : "New profile", name: $newName) {
                model.createProfile(newName, duplicate: duplicate); showNew = false
            } cancel: { showNew = false }
        }
        .sheet(item: Binding(get: { renaming.map { IdentifiedString(id: $0) } }, set: { renaming = $0?.id })) { item in
            NameSheet(title: "Rename “\(item.id)”", name: $renameText) {
                model.renameProfile(item.id, to: renameText); selected = renameText; renaming = nil
            } cancel: { renaming = nil }
        }
    }
}

struct IdentifiedString: Identifiable { let id: String }

struct NameSheet: View {
    let title: String
    @Binding var name: String
    let done: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 280).onSubmit(done)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("OK", action: done).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(20)
    }
}
