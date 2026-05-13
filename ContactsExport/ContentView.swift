//
//  ContentView.swift
//  ContactsExport
//
//  Created by Cem on 7.05.2026.
//

import SwiftUI
import Contacts

// MARK: - Copyright Footer

struct CopyrightFooter: View {
    var body: some View {
        Text("© 2026 Cem Süngü")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

struct ContentView: View {
    @StateObject private var manager = ContactManager()
    @State private var showDuplicatePreview = false
    @State private var showAllContacts = false
    @State private var showAccountList = false
    @State private var showDuplicateList = false
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            Group {
                switch manager.authorizationStatus {
                case .notDetermined:
                    requestAccessView
                case .authorized, .limited:
                    contactListView
                case .denied, .restricted:
                    deniedView
                @unknown default:
                    deniedView
                }
            }
            .navigationTitle("Kişilerimi Yedekle")
            .toolbar {
                if manager.authorizationStatus == .authorized || manager.authorizationStatus == .limited {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            manager.loadAllContacts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .sheet(isPresented: $showDuplicatePreview) {
                DuplicatePreviewView(manager: manager)
            }
            .sheet(isPresented: $showAllContacts) {
                AllContactsView(manager: manager)
            }
            .sheet(isPresented: $showAccountList) {
                AccountListView(manager: manager)
            }
            .sheet(isPresented: $showDuplicateList) {
                DuplicateListView(manager: manager)
            }
        }
        .onAppear {
            manager.checkAuthorizationStatus()
        }
    }

    // MARK: - Request Access View

    private var requestAccessView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Kişilerimi Yedekle")
                .font(.title2.bold())

            Text("Tüm hesaplarınızdaki kişileri Gmail ve Outlook/Hotmail uyumlu vCard (.vcf) formatında dışa aktarın.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task {
                    await manager.requestAccess()
                }
            } label: {
                Label("Devam Et", systemImage: "lock.open")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            Spacer()

            CopyrightFooter()
        }
        .padding()
    }

    // MARK: - Denied View

    private var deniedView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Kişi Erişimi Reddedildi")
                .font(.title2.bold())

            Text("Kişilerinizi dışa aktarabilmek için Ayarlar'dan kişi erişim iznini etkinleştirmeniz gerekmektedir.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Ayarları Aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            CopyrightFooter()
        }
        .padding()
    }

    // MARK: - Contact List View

    private var contactListView: some View {
        List {
            if manager.isLoading {
                ProgressView("Kişiler yükleniyor...")
            }

            if let error = manager.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            if manager.authorizationStatus == .limited {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Kısıtlı Erişim", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("Tüm kişilerinizi dışa aktarabilmek için tam erişim izni vermeniz gerekiyor. Şu an sadece seçili kişiler görünüyor.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Ayarlardan Tam Erişim Ver") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !manager.containers.isEmpty {
                // Summary Section
                Section {
                    Button {
                        showAllContacts = true
                    } label: {
                        HStack {
                            Label("Toplam Kişi", systemImage: "person.2")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(manager.totalContactCount)")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Button {
                        showAccountList = true
                    } label: {
                        HStack {
                            Label("Hesap Sayısı", systemImage: "tray.2")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(manager.containers.count)")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if manager.duplicatesRemoved > 0 {
                        Button {
                            showDuplicateList = true
                        } label: {
                            HStack {
                                Label("Kaldırılan Duplike", systemImage: "doc.on.doc")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(manager.duplicatesRemoved)")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if manager.hasDeletableContacts {
                        Button {
                            showDuplicatePreview = true
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Duplike & Bozuk Kişileri Temizle")
                                        .font(.subheadline)
                                    Text("Tekrarlanan ve karakter bozukluğu olan kişileri sil")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "trash.circle")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("Özet")
                }

                // Export All Button
                Section {
                    Button {
                        exportAll()
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Tümünü Dışa Aktar")
                                        .font(.headline)
                                    Text("Tüm hesaplardan \(manager.totalContactCount) kişi • vCard (.vcf)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                if isExporting {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .disabled(isExporting)
                } footer: {
                    Text("Gmail ve Outlook/Hotmail ile uyumlu vCard 3.0 formatında dışa aktarır.")
                }

                // Copyright
                Section {
                    CopyrightFooter()
                        .listRowBackground(Color.clear)
                }
            }
        }
    }

    // MARK: - Actions

    private func exportAll() {
        isExporting = true
        Task.detached {
            let urls = await manager.exportAllContactsToVCard()
            await MainActor.run {
                isExporting = false
                if !urls.isEmpty {
                    if urls.count > 1 {
                        manager.errorMessage = String(format: NSLocalizedString("%d parça oluşturuldu. Her biri sırayla paylaşılacak.", comment: "Multiple parts created message"), urls.count)
                    }
                    ShareUtility.share(urls: urls)
                }
            }
        }
    }
}

// MARK: - All Contacts View

struct AllContactsView: View {
    let manager: ContactManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var allContacts: [CNContact] {
        manager.containers.flatMap { $0.contacts }
    }

    private var filteredContacts: [CNContact] {
        if searchText.isEmpty {
            return allContacts
        }
        return allContacts.filter { contact in
            let name = manager.displayName(for: contact).lowercased()
            return name.contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredContacts, id: \.identifier) { contact in
                        ContactRow(contact: contact, manager: manager)
                    }
                } header: {
                    Text("Kişiler (\(filteredContacts.count))")
                }

                Section {
                    CopyrightFooter()
                        .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $searchText, prompt: "Kişi ara...")
            .navigationTitle("Tüm Kişiler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Account List View

struct AccountListView: View {
    let manager: ContactManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(manager.containers) { container in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(container.name)
                                .font(.headline)
                            Text(container.typeLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(container.contacts.count) kişi")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }

                Section {
                    CopyrightFooter()
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Hesaplar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Duplicate List View (read-only review of removed duplicates)

struct DuplicateListView: View {
    let manager: ContactManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if manager.removedDuplicates.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                        Text("Duplike bulunamadı")
                            .font(.title3.bold())
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            Text("Otomatik olarak kaldırılan \(manager.removedDuplicates.count) duplike kişi")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Section {
                            ForEach(manager.removedDuplicates) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(manager.displayName(for: item.contact))
                                            .font(.body)
                                        Spacer()
                                        Text(item.reason.label)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(item.reason == .mojibake ? Color.purple.opacity(0.15) : Color.orange.opacity(0.15))
                                            .foregroundStyle(item.reason == .mojibake ? .purple : .orange)
                                            .clipShape(Capsule())
                                    }

                                    if let phone = item.contact.phoneNumbers.first {
                                        Text(phone.value.stringValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let kept = item.keptContact {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.green)
                                            Text("Korunan: \(manager.displayName(for: kept))")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("Kaldırılan Duplikeler")
                        }

                        Section {
                            CopyrightFooter()
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("Duplike Detay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: CNContact
    let manager: ContactManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(manager.displayName(for: contact))
                .font(.body)

            if !contact.organizationName.isEmpty {
                Text(contact.organizationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let phone = contact.phoneNumbers.first {
                Text(phone.value.stringValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let email = contact.emailAddresses.first {
                Text(email.value as String)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Duplicate Preview View

struct DuplicatePreviewView: View {
    let manager: ContactManager
    @Environment(\.dismiss) private var dismiss
    @State private var deletables: [ContactManager.DeletableContact] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var showConfirmation = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Analiz ediliyor...")
                } else if deletables.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                        Text("Temiz!")
                            .font(.title2.bold())
                        Text("Duplike veya karakter bozukluğu olan kişi bulunamadı.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            HStack {
                                Text("Silinecek: \(selected.count) / \(deletables.count)")
                                    .font(.headline)
                                Spacer()
                                Button(selected.count == deletables.count ? "Hiçbirini Seçme" : "Tümünü Seç") {
                                    if selected.count == deletables.count {
                                        selected.removeAll()
                                    } else {
                                        selected = Set(deletables.map(\.id))
                                    }
                                }
                                .font(.subheadline)
                            }
                        }

                        if let error = deleteError {
                            Section {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                            }
                        }

                        Section {
                            ForEach(deletables) { item in
                                DeletableContactRow(
                                    item: item,
                                    manager: manager,
                                    isSelected: selected.contains(item.id),
                                    toggle: {
                                        if selected.contains(item.id) {
                                            selected.remove(item.id)
                                        } else {
                                            selected.insert(item.id)
                                        }
                                    }
                                )
                            }
                        } header: {
                            Text("Silinecek Kişiler")
                        }
                    }
                }
            }
            .navigationTitle("Duplike Temizleme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sil (\(selected.count))") {
                        showConfirmation = true
                    }
                    .foregroundStyle(.red)
                    .bold()
                    .disabled(selected.isEmpty || isDeleting)
                }
            }
            .alert("Kişileri Sil", isPresented: $showConfirmation) {
                Button("İptal", role: .cancel) { }
                Button("Sil", role: .destructive) {
                    performDeletion()
                }
            } message: {
                Text("\(selected.count) kişi kalıcı olarak silinecek. Bu işlem geri alınamaz.")
            }
            .onAppear {
                Task {
                    deletables = manager.findDeletableContacts()
                    selected = Set(deletables.map(\.id))
                    isLoading = false
                }
            }
        }
    }

    private func performDeletion() {
        isDeleting = true
        let toDelete = deletables.filter { selected.contains($0.id) }.map(\.contact)
        do {
            try manager.deleteContacts(toDelete)
            dismiss()
        } catch {
            deleteError = String(format: NSLocalizedString("Silme hatası: %@", comment: "Delete error with reason"), error.localizedDescription)
            isDeleting = false
        }
    }
}

struct DeletableContactRow: View {
    let item: ContactManager.DeletableContact
    let manager: ContactManager
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .red : .gray)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(manager.displayName(for: item.contact))
                            .font(.body)
                            .strikethrough(isSelected, color: .red)
                        Spacer()
                        Text(item.reason.label)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.reason == .mojibake ? Color.purple.opacity(0.15) : Color.orange.opacity(0.15))
                            .foregroundStyle(item.reason == .mojibake ? .purple : .orange)
                            .clipShape(Capsule())
                    }

                    if let phone = item.contact.phoneNumbers.first {
                        Text(phone.value.stringValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let kept = item.keptContact {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("Korunan: \(manager.displayName(for: kept))")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share Utility

enum ShareUtility {
    static func share(urls: [URL]) {
        shareNext(urls: urls, index: 0)
    }

    private static func shareNext(urls: [URL], index: Int) {
        guard index < urls.count else { return }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.keyWindow?.rootViewController else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let url = urls[index]
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        activityVC.completionWithItemsHandler = { _, _, _, _ in
            if index + 1 < urls.count {
                // Small delay to let the previous sheet fully dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    shareNext(urls: urls, index: index + 1)
                }
            }
        }

        topVC.present(activityVC, animated: true)
    }
}

#Preview {
    ContentView()
}
