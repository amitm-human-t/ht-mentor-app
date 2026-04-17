import SwiftUI
import SwiftData

// MARK: - Main View

struct UserChooserView: View {
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \UserRecord.displayName)
    private var users: [UserRecord]

    @State private var searchText = ""
    @State private var editingUserID: UUID?
    @State private var isCreatingNew = false
    @State private var showDeleteConfirm = false

    // Form state — synced from editing user or cleared for new
    @State private var formName = ""
    @State private var formHand: DominantHand = .right

    private var filteredUsers: [UserRecord] {
        searchText.isEmpty ? Array(users) : users.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var editingUser: UserRecord? {
        users.first { $0.id == editingUserID }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
                .frame(width: 288)

            Rectangle()
                .fill(Color.hxSurfaceBorder)
                .frame(width: 1)
                .ignoresSafeArea()

            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.hxBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: editingUserID) { _, _ in syncFormFromEditing() }
        .onAppear { preselectLastActiveUser() }
        .confirmationDialog(
            "Delete Trainee?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteEditingUser() }
        } message: {
            Text("All training history for this trainee will be permanently deleted.")
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            leftPanelHeader
            Divider().background(Color.hxSurfaceBorder)
            userListContent
        }
        .background(Color.hxSurface.ignoresSafeArea())
    }

    private var leftPanelHeader: some View {
        VStack(alignment: .leading, spacing: HXSpacing.md) {
            HStack {
                Text("Trainees")
                    .font(.hxTitle2)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.hxSurfaceBorder)
                }
                .buttonStyle(.plain)
            }

            // Search field
            HStack(spacing: HXSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(Color.hxSurfaceBorder)
                TextField("Search trainees", text: $searchText)
                    .font(.hxBody)
                    .foregroundStyle(.white)
                    .tint(Color.hxCyan)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.hxSurfaceBorder)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, HXSpacing.md)
            .padding(.vertical, HXSpacing.sm)
            .background(Color.hxSurfaceRaised, in: RoundedRectangle(cornerRadius: HXRadius.sm))

            // New trainee button
            Button {
                startCreatingNew()
            } label: {
                Label("New Trainee", systemImage: "plus.circle.fill")
                    .font(.hxHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.hxCyan)
        }
        .padding(HXSpacing.lg)
    }

    private var userListContent: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredUsers) { user in
                    UserRow(
                        user: user,
                        isEditing: editingUserID == user.id,
                        isActive: appModel.selectedUser?.id == user.id
                    ) {
                        withAnimation(.hxDefault) {
                            editingUserID = user.id
                            isCreatingNew = false
                        }
                    }
                }

                if filteredUsers.isEmpty {
                    VStack(spacing: HXSpacing.sm) {
                        Image(systemName: "person.slash")
                            .font(.largeTitle)
                            .foregroundStyle(Color.hxSurfaceBorder)
                        Text(searchText.isEmpty ? "No trainees yet" : "No results")
                            .font(.hxBody)
                            .foregroundStyle(Color(white: 0.4))
                    }
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, HXSpacing.sm)
            .padding(.vertical, HXSpacing.sm)
        }
    }

    // MARK: - Right Panel

    @ViewBuilder
    private var rightPanel: some View {
        if isCreatingNew {
            userFormView(title: "New Trainee", user: nil)
                .id("new")
        } else if let user = editingUser {
            userFormView(title: user.displayName, user: user)
                .id(user.id)
        } else {
            emptyStateView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: HXSpacing.xl) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 72))
                .foregroundStyle(Color.hxSurfaceBorder)
            VStack(spacing: HXSpacing.sm) {
                Text("Select a Trainee")
                    .font(.hxTitle2)
                    .foregroundStyle(.white)
                Text("Choose an existing trainee from the list\nor create a new one to get started.")
                    .font(.hxBody)
                    .foregroundStyle(Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - User Form

    private func userFormView(title: String, user: UserRecord?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HXSpacing.xl) {

                // Top bar inside form
                HStack {
                    Text(title)
                        .font(.hxTitle2)
                        .foregroundStyle(.white)
                    Spacer()
                }

                // Avatar hero
                HStack {
                    Spacer()
                    AvatarView(
                        name: formName.isEmpty ? (user?.displayName ?? "?") : formName,
                        size: 96
                    )
                    Spacer()
                }

                // Name field
                formSection(label: "Display Name") {
                    TextField("Enter trainee name", text: $formName)
                        .font(.hxHeadline)
                        .foregroundStyle(.white)
                        .tint(Color.hxCyan)
                        .padding(HXSpacing.md)
                        .background(Color.hxSurfaceRaised, in: RoundedRectangle(cornerRadius: HXRadius.sm))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }

                // Dominant hand picker
                formSection(label: "Dominant Hand") {
                    Picker("Hand", selection: $formHand) {
                        ForEach(DominantHand.allCases, id: \.self) { hand in
                            Text(hand.rawValue.capitalized).tag(hand)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Action buttons
                VStack(spacing: HXSpacing.sm) {
                    if let user {
                        // Primary: select this trainee
                        Button {
                            appModel.selectUser(user)
                            dismiss()
                        } label: {
                            Label("Select Trainee", systemImage: "checkmark.circle.fill")
                                .font(.hxHeadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.hxCyan)

                        // Secondary: save edits
                        HStack(spacing: HXSpacing.sm) {
                            Button {
                                saveChanges(to: user)
                            } label: {
                                Text("Save Changes")
                                    .font(.hxBody)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)

                            Button {
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.hxBody)
                                    .padding(.horizontal, 4)
                            }
                            .buttonStyle(.glass)
                            .tint(Color.hxDanger)
                        }
                    } else {
                        // Create new user
                        Button {
                            createUser()
                        } label: {
                            Label("Create Trainee", systemImage: "person.badge.plus")
                                .font(.hxHeadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.hxCyan)
                        .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button {
                            withAnimation(.hxDefault) {
                                isCreatingNew = false
                                formName = ""
                                formHand = .right
                            }
                        } label: {
                            Text("Cancel")
                                .font(.hxBody)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .padding(HXSpacing.xxl)
        }
        .background(Color.hxBackground)
    }

    @ViewBuilder
    private func formSection<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HXSpacing.sm) {
            Text(label.uppercased())
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.45))
                .kerning(0.5)
            content()
        }
    }

    // MARK: - Actions

    private func preselectLastActiveUser() {
        guard editingUserID == nil, !isCreatingNew else { return }
        if let lastID = UserDefaultsStore.lastActiveUserID,
           users.contains(where: { $0.id == lastID }) {
            editingUserID = lastID
        } else if let first = users.first {
            editingUserID = first.id
        }
    }

    private func syncFormFromEditing() {
        if let user = editingUser {
            formName = user.displayName
            formHand = DominantHand(rawValue: user.dominantHandRawValue) ?? .right
        } else if !isCreatingNew {
            formName = ""
            formHand = .right
        }
    }

    private func startCreatingNew() {
        withAnimation(.hxDefault) {
            isCreatingNew = true
            editingUserID = nil
            formName = ""
            formHand = .right
        }
    }

    private func createUser() {
        let name = formName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let user = UserRecord(displayName: name, dominantHandRawValue: formHand.rawValue)
        modelContext.insert(user)
        try? modelContext.save()
        withAnimation(.hxDefault) {
            isCreatingNew = false
            editingUserID = user.id
        }
        appModel.selectUser(user)
        dismiss()
    }

    private func saveChanges(to user: UserRecord) {
        let name = formName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        user.displayName = name
        user.dominantHandRawValue = formHand.rawValue
        user.updatedAt = .now
        try? modelContext.save()
    }

    private func deleteEditingUser() {
        guard let user = editingUser else { return }
        let deletedID = user.id
        modelContext.delete(user)
        try? modelContext.save()
        withAnimation(.hxDefault) {
            editingUserID = nil
            isCreatingNew = false
        }
        appModel.userWasDeleted(id: deletedID)
    }
}

// MARK: - UserRow

private struct UserRow: View {
    let user: UserRecord
    let isEditing: Bool
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: HXSpacing.md) {
                AvatarView(name: user.displayName, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: HXSpacing.xs) {
                        Text(user.displayName)
                            .font(.hxHeadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.hxCyan)
                        }
                    }
                    Text((DominantHand(rawValue: user.dominantHandRawValue)?.rawValue.capitalized ?? "Unknown") + " hand")
                        .font(.hxCaption)
                        .foregroundStyle(Color(white: 0.45))
                }

                Spacer()

                if isEditing {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(Color.hxCyan)
                }
            }
            .padding(.horizontal, HXSpacing.md)
            .padding(.vertical, HXSpacing.md)
            .background(
                isEditing
                    ? Color.hxCyan.opacity(0.10)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: HXRadius.sm)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.hxDefault, value: isEditing)
    }
}

// MARK: - AvatarView

struct AvatarView: View {
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let palette: [Color] = [
            Color(red: 0.0,  green: 0.72, blue: 0.85),  // cyan
            Color(red: 0.55, green: 0.32, blue: 0.90),  // purple
            Color(red: 0.95, green: 0.58, blue: 0.04),  // amber
            Color(red: 0.10, green: 0.78, blue: 0.38),  // green
            Color(red: 0.95, green: 0.22, blue: 0.42),  // pink-red
            Color(red: 0.10, green: 0.75, blue: 0.65),  // teal
            Color(red: 0.22, green: 0.52, blue: 0.95),  // blue
        ]
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: UserRecord.self, configurations: config)
    let ctx = container.mainContext
    ctx.insert(UserRecord(displayName: "Alice Chen", dominantHandRawValue: "right"))
    ctx.insert(UserRecord(displayName: "Bob Martinez", dominantHandRawValue: "left"))
    ctx.insert(UserRecord(displayName: "Dr. Sarah K.", dominantHandRawValue: "right"))
    return NavigationStack {
        UserChooserView(appModel: AppModel())
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
