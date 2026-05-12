import Foundation
import Contacts
import Combine
import UIKit

struct ContactContainer: Identifiable {
    let id: String
    let name: String
    let type: CNContainerType
    let contacts: [CNContact]

    var typeLabel: String {
        switch type {
        case .unassigned:
            return "Atanmamış"
        case .local:
            return "Yerel (Orphan)"
        case .exchange:
            return "Exchange"
        case .cardDAV:
            return "CardDAV (iCloud/Google)"
        @unknown default:
            return "Bilinmeyen"
        }
    }
}

@MainActor
final class ContactManager: ObservableObject {
    @Published var containers: [ContactContainer] = []
    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var totalContactCount = 0
    @Published var duplicatesRemoved = 0
    @Published var hasDeletableContacts = false
    @Published var removedDuplicates: [DeletableContact] = []

    private let store = CNContactStore()

    private static let keysToFetch: [CNKeyDescriptor] = [
        CNContactVCardSerialization.descriptorForRequiredKeys(),
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
        CNContactUrlAddressesKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactDepartmentNameKey as CNKeyDescriptor,
        CNContactInstantMessageAddressesKey as CNKeyDescriptor,
        CNContactSocialProfilesKey as CNKeyDescriptor,
        CNContactRelationsKey as CNKeyDescriptor,
        CNContactTypeKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactNamePrefixKey as CNKeyDescriptor,
        CNContactNameSuffixKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactDatesKey as CNKeyDescriptor,
    ]

    func requestAccess() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        // Kullanıcıya neden erişim gerektiğini açıklayın
        if status == .notDetermined {
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "Kişilere Erişim",
                    message: "Kişilerinizi Gmail ve Outlook uyumlu vCard (.vcf) formatında dışa aktarabilmek ve duplike kişileri temizleyebilmek için kişi erişim izni gerekmektedir.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Devam Et", style: .default, handler: { _ in
                    Task {
                        await self.performPermissionRequest()
                    }
                }))
                alert.addAction(UIAlertAction(title: "İptal", style: .cancel, handler: nil))
                UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
            }
        } else {
            await performPermissionRequest()
        }
    }

    private func performPermissionRequest() async {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            authorizationStatus = granted ? .authorized : .denied
            if granted {
                loadAllContacts()
            }
        } catch {
            errorMessage = "İzin hatası: \(error.localizedDescription)"
            authorizationStatus = .denied
        }
    }

    func checkAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            loadAllContacts()
        }
    }

    func loadAllContacts() {
        isLoading = true
        errorMessage = nil
        containers = []
        totalContactCount = 0
        duplicatesRemoved = 0
        hasDeletableContacts = false
        removedDuplicates = []

        do {
            let allContainers = try store.containers(matching: nil)
            var result: [ContactContainer] = []
            var allRemoved: [DeletableContact] = []

            for container in allContainers {
                let predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: Self.keysToFetch)

                let (deduplicated, removed) = deduplicateContacts(contacts)
                allRemoved.append(contentsOf: removed)

                let containerInfo = ContactContainer(
                    id: container.identifier,
                    name: container.name.isEmpty ? containerTypeDisplayName(container.type) : container.name,
                    type: container.type,
                    contacts: deduplicated
                )
                result.append(containerInfo)
                totalContactCount += deduplicated.count
            }

            removedDuplicates = allRemoved
            duplicatesRemoved = allRemoved.count
            containers = result.sorted { $0.contacts.count > $1.contacts.count }

            // Pre-compute so the UI doesn't run heavy analysis on every render
            hasDeletableContacts = !findDeletableContacts().isEmpty
        } catch {
            errorMessage = "Kişiler yüklenirken hata: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Deduplication

    private func deduplicateContacts(_ contacts: [CNContact]) -> (kept: [CNContact], removed: [DeletableContact]) {
        var seen: [String: CNContact] = [:]
        var losers: [(loser: CNContact, winnerKey: String)] = []

        // Pass 1: name-based dedup
        for contact in contacts {
            let key = deduplicationKey(for: contact)
            if key.isEmpty { 
                seen[contact.identifier] = contact
                continue
            }

            if let existing = seen[key] {
                if contactRichness(contact) > contactRichness(existing) {
                    losers.append((loser: existing, winnerKey: key))
                    seen[key] = contact
                } else {
                    losers.append((loser: contact, winnerKey: key))
                }
            } else {
                seen[key] = contact
            }
        }

        // Pass 2: phone-based dedup (catches encoding-corrupted name variants like T√ºz√ºn vs Tüzün)
        var phoneMap: [String: String] = [:] // normalized phone -> key in seen
        var keysToRemove: [String: String] = [:] // removed key -> winner key

        for (key, contact) in seen {
            for phoneValue in contact.phoneNumbers {
                let normalized = phoneValue.value.stringValue
                    .components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                guard normalized.count >= 7 else { continue }

                if let existingKey = phoneMap[normalized], existingKey != key, keysToRemove[key] == nil {
                    if let existing = seen[existingKey] {
                        if contactRichness(contact) > contactRichness(existing) {
                            keysToRemove[existingKey] = key
                            phoneMap[normalized] = key
                        } else {
                            keysToRemove[key] = existingKey
                        }
                    }
                } else if phoneMap[normalized] == nil {
                    phoneMap[normalized] = key
                }
            }
        }

        // Pass 3: email-based dedup
        var emailMap: [String: String] = [:]
        for (key, contact) in seen where keysToRemove[key] == nil {
            for emailValue in contact.emailAddresses {
                let normalized = (emailValue.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                guard !normalized.isEmpty else { continue }

                if let existingKey = emailMap[normalized], existingKey != key, keysToRemove[key] == nil {
                    if let existing = seen[existingKey] {
                        if contactRichness(contact) > contactRichness(existing) {
                            keysToRemove[existingKey] = key
                            emailMap[normalized] = key
                        } else {
                            keysToRemove[key] = existingKey
                        }
                    }
                } else if emailMap[normalized] == nil {
                    emailMap[normalized] = key
                }
            }
        }

        // Build removed list from pass 2 & 3
        for (removedKey, winnerKey) in keysToRemove {
            if let loserContact = seen[removedKey] {
                losers.append((loser: loserContact, winnerKey: winnerKey))
            }
            seen.removeValue(forKey: removedKey)
        }

        // Build DeletableContact array with winner references
        let removed = losers.map { pair -> DeletableContact in
            let winner = seen[pair.winnerKey]
            let isMojibake = hasMojibake(pair.loser)
            return DeletableContact(
                id: pair.loser.identifier,
                contact: pair.loser,
                reason: isMojibake ? .mojibake : .duplicate,
                keptContact: winner
            )
        }

        return (kept: Array(seen.values), removed: removed)
    }

    private func deduplicationKey(for contact: CNContact) -> String {
        let normalizedName = "\(contact.givenName) \(contact.familyName)"
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        // Normalize phone numbers: strip non-digits
        let phones = contact.phoneNumbers
            .map { $0.value.stringValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() }
            .sorted()

        let emails = contact.emailAddresses
            .map { ($0.value as String).lowercased().trimmingCharacters(in: .whitespaces) }
            .sorted()

        // Build composite key
        if !normalizedName.isEmpty {
            // Name + first phone or email for disambiguation
            let disambiguator = phones.first ?? emails.first ?? ""
            return "\(normalizedName)|\(disambiguator)"
        }

        // No name — match by phone or email alone
        if let phone = phones.first, !phone.isEmpty {
            return "phone|\(phone)"
        }
        if let email = emails.first, !email.isEmpty {
            return "email|\(email)"
        }

        return ""
    }

    private func contactRichness(_ contact: CNContact) -> Int {
        var score = 0
        if !contact.givenName.isEmpty { score += 1 }
        if !contact.familyName.isEmpty { score += 1 }
        if !contact.organizationName.isEmpty { score += 1 }
        if !contact.jobTitle.isEmpty { score += 1 }
        score += contact.phoneNumbers.count
        score += contact.emailAddresses.count
        score += contact.postalAddresses.count
        score += contact.urlAddresses.count
        if contact.imageData != nil { score += 2 }
        if contact.birthday != nil { score += 1 }
        score += contact.socialProfiles.count
        score += contact.instantMessageAddresses.count
        score += contact.contactRelations.count

        // Bonus for clean Unicode name — penalizes mojibake (√ º ¿ ½ etc.)
        let fullName = "\(contact.givenName)\(contact.familyName)"
        let nameChars = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "-'."))
        if !fullName.isEmpty && fullName.unicodeScalars.allSatisfy({ nameChars.contains($0) }) {
            score += 10
        }

        return score
    }

    // MARK: - Export

    private static let maxChunkSize = 5 * 1024 * 1024 // 5 MB — Gmail import safe limit
    private static let maxContactsPerChunk = 3000     // Google Contacts import limit

    private static var exportDirectory: URL {
        let docs = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let exportDir = docs.appendingPathComponent("ExportedVCards", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        return exportDir
    }

    private static func cleanExportDirectory() {
        let dir = exportDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func exportAllContactsToVCard() -> [URL] {
        let allContacts = containers.flatMap { $0.contacts }
        guard !allContacts.isEmpty else { return [] }
        let deduplicated = deduplicateContacts(allContacts)
        return writeVCardFiles(contacts: deduplicated.kept, baseName: "TumKisiler")
    }

    func exportContainerToVCard(_ container: ContactContainer) -> [URL] {
        guard !container.contacts.isEmpty else { return [] }
        let safeName = container.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return writeVCardFiles(contacts: container.contacts, baseName: safeName)
    }

    private func writeVCardFiles(contacts: [CNContact], baseName: String) -> [URL] {
        do {
            Self.cleanExportDirectory()

            let baseData = try CNContactVCardSerialization.data(with: contacts)
            guard let baseString = String(data: baseData, encoding: .utf8) else {
                errorMessage = "vCard dönüştürme hatası"
                return []
            }

            let enriched = enrichVCards(baseString: baseString, contacts: contacts)

            // Split into individual vCard blocks
            let blocks = enriched.components(separatedBy: "END:VCARD\r\n")
                .filter { $0.contains("BEGIN:VCARD") }
                .map { $0 + "END:VCARD\r\n" }

            // Chunk by size AND contact count (Google max 3000 per import)
            var chunks: [[String]] = [[]]
            var currentSize = 0
            var currentCount = 0

            for block in blocks {
                let blockSize = block.utf8.count
                let needNewChunk = !chunks[chunks.count - 1].isEmpty &&
                    (currentSize + blockSize > Self.maxChunkSize || currentCount >= Self.maxContactsPerChunk)
                if needNewChunk {
                    chunks.append([])
                    currentSize = 0
                    currentCount = 0
                }
                chunks[chunks.count - 1].append(block)
                currentSize += blockSize
                currentCount += 1
            }

            let exportDir = Self.exportDirectory
            var urls: [URL] = []

            for (index, chunk) in chunks.enumerated() {
                let content = chunk.joined()
                let suffix = chunks.count > 1 ? "_\(index + 1)" : ""
                let fileURL = exportDir.appendingPathComponent("\(baseName)\(suffix).vcf")

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }

                // Write as raw Data to prevent any platform line-ending conversion
                guard let data = content.data(using: .utf8) else { continue }
                try data.write(to: fileURL, options: .atomic)
                urls.append(fileURL)
            }

            return urls
        } catch {
            errorMessage = "Export hatası: \(error.localizedDescription)"
            return []
        }
    }

    private func enrichVCards(baseString: String, contacts: [CNContact]) -> String {
        // Normalize all line endings to \n first, we'll convert to \r\n at the end
        let normalized = baseString
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Split base vCard into individual entries
        let vcards = normalized.components(separatedBy: "END:VCARD")
            .filter { $0.contains("BEGIN:VCARD") }

        var result = ""
        for (index, contact) in contacts.enumerated() {
            guard index < vcards.count else { break }
            var card = vcards[index]

            // --- PHOTO disabled for debugging ---
            // if let imageData = contact.imageData,
            //    !card.contains("PHOTO") {
            //     let compressed = compressPhoto(imageData, maxBytes: 300_000)
            //     let base64 = compressed.base64EncodedString()
            //     let photoLine = "PHOTO;ENCODING=b;TYPE=JPEG:" + base64
            //     card += foldVCardLine(photoLine) + "\n"
            // }

            // --- BIRTHDAY ---
            if let birthday = contact.birthday,
               !card.contains("BDAY"),
               let month = birthday.month,
               let day = birthday.day {
                if let year = birthday.year {
                    card += "BDAY:\(String(format: "%04d-%02d-%02d", year, month, day))\n"
                } else {
                    card += "BDAY:--\(String(format: "%02d-%02d", month, day))\n"
                }
            }

            // --- OTHER DATES (anniversary etc.) ---
            for dateValue in contact.dates {
                let label = (dateValue.label ?? "other")
                    .replacingOccurrences(of: "_$!<", with: "")
                    .replacingOccurrences(of: ">!$_", with: "")
                let dc = dateValue.value as DateComponents
                let month = dc.month
                let day = dc.day
                if let month, let day {
                    if let year = dc.year {
                        card += "X-ABDATE;TYPE=\(label):\(String(format: "%04d-%02d-%02d", year, month, day))\n"
                    } else {
                        card += "X-ABDATE;TYPE=\(label):----\(String(format: "-%02d-%02d", month, day))\n"
                    }
                }
            }

            // --- SOCIAL PROFILES ---
            for profile in contact.socialProfiles {
                let service = profile.value.service
                let username = profile.value.username
                let urlString = profile.value.urlString
                if !username.isEmpty || !urlString.isEmpty {
                    let value = urlString.isEmpty ? username : urlString
                    card += "X-SOCIALPROFILE;TYPE=\(service):\(value)\n"
                }
            }

            // --- RELATIONS (related names) ---
            for relation in contact.contactRelations {
                let label = (relation.label ?? "other")
                    .replacingOccurrences(of: "_$!<", with: "")
                    .replacingOccurrences(of: ">!$_", with: "")
                let name = relation.value.name
                if !name.isEmpty {
                    card += "X-ABRELATEDNAMES;TYPE=\(label):\(name)\n"
                }
            }

            // --- INSTANT MESSAGING ---
            for im in contact.instantMessageAddresses where !card.contains(im.value.username) {
                let service = im.value.service
                let username = im.value.username
                if !username.isEmpty {
                    card += "IMPP;X-SERVICE-TYPE=\(service):x-apple:\(username)\n"
                }
            }

            // --- NICKNAME ---
            if !contact.nickname.isEmpty && !card.contains("NICKNAME") {
                card += "NICKNAME:\(contact.nickname)\n"
            }

            result += card + "END:VCARD\n"
        }

        // Append any remaining vCards that didn't match (shouldn't happen normally)
        for index in contacts.count..<vcards.count {
            result += vcards[index] + "END:VCARD\n"
        }

        // Convert all line endings to proper \r\n for vCard standard
        return result.replacingOccurrences(of: "\n", with: "\r\n")
    }

    private func compressPhoto(_ data: Data, maxBytes: Int) -> Data {
        guard let uiImage = UIImage(data: data) else { return data }

        // If already small enough, just re-encode at high quality
        if data.count <= maxBytes {
            return uiImage.jpegData(compressionQuality: 0.9) ?? data
        }

        // First try: reduce JPEG quality (keep original resolution)
        var quality: CGFloat = 0.85
        var compressed = uiImage.jpegData(compressionQuality: quality) ?? data
        while compressed.count > maxBytes && quality > 0.4 {
            quality -= 0.05
            compressed = uiImage.jpegData(compressionQuality: quality) ?? compressed
        }
        if compressed.count <= maxBytes { return compressed }

        // Second: scale down to max 400x400 keeping aspect ratio
        let maxDim: CGFloat = 400
        let origSize = uiImage.size
        if origSize.width > maxDim || origSize.height > maxDim {
            let ratio = min(maxDim / origSize.width, maxDim / origSize.height)
            let newSize = CGSize(width: origSize.width * ratio, height: origSize.height * ratio)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in
                uiImage.draw(in: CGRect(origin: .zero, size: newSize))
            }
            compressed = resized.jpegData(compressionQuality: 0.7) ?? compressed
        }
        return compressed
    }

    private func foldVCardLine(_ line: String) -> String {
        // vCard 3.0: max 75 octets per line, continuation lines start with a space
        let maxLen = 75
        guard line.count > maxLen else { return line }
        var result = ""
        var remaining = line
        var isFirst = true
        while !remaining.isEmpty {
            let len = isFirst ? maxLen : maxLen - 1
            let prefix = String(remaining.prefix(len))
            remaining = String(remaining.dropFirst(len))
            if isFirst {
                result += prefix
                isFirst = false
            } else {
                result += "\n " + prefix
            }
        }
        return result
    }

    // MARK: - Helpers

    private func containerTypeDisplayName(_ type: CNContainerType) -> String {
        switch type {
        case .unassigned:
            return "Atanmamış"
        case .local:
            return "Yerel Kişiler"
        case .exchange:
            return "Exchange"
        case .cardDAV:
            return "CardDAV"
        @unknown default:
            return "Diğer"
        }
    }

    func displayName(for contact: CNContact) -> String {
        let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            if let firstEmail = contact.emailAddresses.first {
                return firstEmail.value as String
            }
            if let firstPhone = contact.phoneNumbers.first {
                return firstPhone.value.stringValue
            }
            if !contact.organizationName.isEmpty {
                return contact.organizationName
            }
            return "(İsimsiz Kişi)"
        }
        return name
    }

    // MARK: - Deletable Contacts Detection

    struct DeletableContact: Identifiable {
        let id: String
        let contact: CNContact
        let reason: DeletionReason
        let keptContact: CNContact? // the "winner" this duplicates
    }

    enum DeletionReason {
        case duplicate
        case mojibake

        var label: String {
            switch self {
            case .duplicate: return "Duplike"
            case .mojibake: return "Karakter Bozuk"
            }
        }
    }

    func findDeletableContacts() -> [DeletableContact] {
        let allContacts = containers.flatMap { $0.contacts }
        var deletables: [DeletableContact] = []
        var seenIdentifiers: Set<String> = []

        // --- Pass 1: Name-based duplicates ---
        var nameMap: [String: [CNContact]] = [:]
        for contact in allContacts {
            let key = deduplicationKey(for: contact)
            guard !key.isEmpty else { continue }
            nameMap[key, default: []].append(contact)
        }

        for (_, group) in nameMap where group.count > 1 {
            let sorted = group.sorted { contactRichness($0) > contactRichness($1) }
            let winner = sorted[0]
            for loser in sorted.dropFirst() {
                if !seenIdentifiers.contains(loser.identifier) {
                    seenIdentifiers.insert(loser.identifier)
                    deletables.append(DeletableContact(
                        id: loser.identifier,
                        contact: loser,
                        reason: .duplicate,
                        keptContact: winner
                    ))
                }
            }
        }

        // --- Pass 2: Phone-based duplicates (catches mojibake name variants) ---
        var phoneGroups: [String: [CNContact]] = [:]
        for contact in allContacts where !seenIdentifiers.contains(contact.identifier) {
            for phoneValue in contact.phoneNumbers {
                let normalized = phoneValue.value.stringValue
                    .components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                guard normalized.count >= 7 else { continue }
                phoneGroups[normalized, default: []].append(contact)
            }
        }

        for (_, group) in phoneGroups where group.count > 1 {
            let unique = Dictionary(grouping: group, by: \.identifier).values.map(\.first!)
            guard unique.count > 1 else { continue }
            let sorted = unique.sorted { contactRichness($0) > contactRichness($1) }
            let winner = sorted[0]
            for loser in sorted.dropFirst() {
                if !seenIdentifiers.contains(loser.identifier) {
                    seenIdentifiers.insert(loser.identifier)
                    let isMojibake = hasMojibake(loser)
                    deletables.append(DeletableContact(
                        id: loser.identifier,
                        contact: loser,
                        reason: isMojibake ? .mojibake : .duplicate,
                        keptContact: winner
                    ))
                }
            }
        }

        // --- Pass 3: Email-based duplicates ---
        var emailGroups: [String: [CNContact]] = [:]
        for contact in allContacts where !seenIdentifiers.contains(contact.identifier) {
            for emailValue in contact.emailAddresses {
                let normalized = (emailValue.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                guard !normalized.isEmpty else { continue }
                emailGroups[normalized, default: []].append(contact)
            }
        }

        for (_, group) in emailGroups where group.count > 1 {
            let unique = Dictionary(grouping: group, by: \.identifier).values.map(\.first!)
            guard unique.count > 1 else { continue }
            let sorted = unique.sorted { contactRichness($0) > contactRichness($1) }
            let winner = sorted[0]
            for loser in sorted.dropFirst() {
                if !seenIdentifiers.contains(loser.identifier) {
                    seenIdentifiers.insert(loser.identifier)
                    let isMojibake = hasMojibake(loser)
                    deletables.append(DeletableContact(
                        id: loser.identifier,
                        contact: loser,
                        reason: isMojibake ? .mojibake : .duplicate,
                        keptContact: winner
                    ))
                }
            }
        }

        // --- Pass 4: Standalone mojibake (no duplicate match) ---
        for contact in allContacts where !seenIdentifiers.contains(contact.identifier) {
            if hasMojibake(contact) {
                seenIdentifiers.insert(contact.identifier)
                deletables.append(DeletableContact(
                    id: contact.identifier,
                    contact: contact,
                    reason: .mojibake,
                    keptContact: nil
                ))
            }
        }

        return deletables
    }

    private func hasMojibake(_ contact: CNContact) -> Bool {
        let fullName = "\(contact.givenName)\(contact.familyName)"
        guard !fullName.isEmpty else { return false }
        // UTF-8 Turkish chars decoded as Mac Roman: √ (C3), ƒ (C4), ≈ (C5)
        // UTF-8 Turkish chars decoded as Windows-1252: Ã (C3), Â
        // Other common mojibake artifacts: º, ¿, ½
        let mojibakeChars = CharacterSet(charactersIn: "√≈ƒº¿½ÃÂ")
        return fullName.unicodeScalars.contains { mojibakeChars.contains($0) }
    }

    func deleteContacts(_ contacts: [CNContact]) throws {
        let saveRequest = CNSaveRequest()
        for contact in contacts {
            // Need mutable copy to delete
            guard let mutable = contact.mutableCopy() as? CNMutableContact else { continue }
            saveRequest.delete(mutable)
        }
        try store.execute(saveRequest)
        // Reload after deletion
        loadAllContacts()
    }
}
