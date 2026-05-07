//
//  ContentView.swift
//  ContactsExport
//
//  Created by Cem on 7.05.2026.
//

import SwiftUI
import Contacts

struct ContentView: View {
    @StateObject private var manager = ContactManager()
    @State private var selectedContainer: ContactContainer?
    @State private var showContainerDetail = false

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
            .navigationTitle("Kişi Export")
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
            .sheet(isPresented: $showContainerDetail) {
                if let container = selectedContainer {
                    ContainerDetailView(container: container, manager: manager)
                }
            }
        }
        .onAppear {
            manager.checkAuthorizationStatus()
        }
    }

    // MARK: - Request Access View

    private var requestAccessView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Kişilerinizi Dışa Aktarın")
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
                Label("Kişilere Erişim İzni Ver", systemImage: "lock.open")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }

    // MARK: - Denied View

    private var deniedView: some View {
        VStack(spacing: 16) {
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
                    HStack {
                        Label("Toplam Kişi", systemImage: "person.2")
                        Spacer()
                        Text("\(manager.totalContactCount)")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                    HStack {
                        Label("Hesap Sayısı", systemImage: "tray.2")
                        Spacer()
                        Text("\(manager.containers.count)")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                    if manager.duplicatesRemoved > 0 {
                        HStack {
                            Label("Kaldırılan Duplike", systemImage: "doc.on.doc")
                            Spacer()
                            Text("\(manager.duplicatesRemoved)")
                                .font(.headline)
                                .foregroundStyle(.orange)
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
                        Label {
                            VStack(alignment: .leading) {
                                Text("Tümünü Dışa Aktar")
                                    .font(.headline)
                                Text("Tüm hesaplardan \(manager.totalContactCount) kişi • vCard (.vcf)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                    }
                } footer: {
                    Text("Gmail ve Outlook/Hotmail ile uyumlu vCard 3.0 formatında dışa aktarır.")
                }

                // Per-Container Sections
                Section {
                    ForEach(manager.containers) { container in
                        Button {
                            selectedContainer = container
                            showContainerDetail = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(container.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(container.typeLabel) • \(container.contacts.count) kişi")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    exportContainer(container)
                                } label: {
                                    Image(systemName: "square.and.arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("Hesaplar")
                }
            }
        }
    }

    // MARK: - Actions

    private func exportAll() {
        let urls = manager.exportAllContactsToVCard()
        if !urls.isEmpty {
            if urls.count > 1 {
                manager.errorMessage = "\(urls.count) parça oluşturuldu. Her biri sırayla paylaşılacak."
            }
            ShareUtility.share(urls: urls)
        }
    }

    private func exportContainer(_ container: ContactContainer) {
        let urls = manager.exportContainerToVCard(container)
        if !urls.isEmpty {
            if urls.count > 1 {
                manager.errorMessage = "\(urls.count) parça oluşturuldu. Her biri sırayla paylaşılacak."
            }
            ShareUtility.share(urls: urls)
        }
    }
}

// MARK: - Container Detail View

struct ContainerDetailView: View {
    let container: ContactContainer
    let manager: ContactManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredContacts: [CNContact] {
        if searchText.isEmpty {
            return container.contacts
        }
        return container.contacts.filter { contact in
            let name = manager.displayName(for: contact).lowercased()
            return name.contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Tür", systemImage: "info.circle")
                        Spacer()
                        Text(container.typeLabel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Kişi Sayısı", systemImage: "person.2")
                        Spacer()
                        Text("\(container.contacts.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        let urls = manager.exportContainerToVCard(container)
                        if !urls.isEmpty {
                            ShareUtility.share(urls: urls)
                        }
                    } label: {
                        Label("Bu Hesabı Dışa Aktar", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    ForEach(filteredContacts, id: \.identifier) { contact in
                        ContactRow(contact: contact, manager: manager)
                    }
                } header: {
                    Text("Kişiler (\(filteredContacts.count))")
                }
            }
            .searchable(text: $searchText, prompt: "Kişi ara...")
            .navigationTitle(container.name)
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
