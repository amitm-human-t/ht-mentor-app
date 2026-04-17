import SwiftUI
import SwiftData

// MARK: - UserManagementView
// Landscape split: left = user list, right = edit form
// No "Select Trainee" primary action — pure management (edit name, hand, delete).

struct UserManagementView: View {
    let appModel: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \UserRecord.displayName)
    private var users: [UserRecord]

    @State private var searchText = ""
    @State private var editingUserID: UUID?
    @State private var isCreatingNew = false
    @State private var showDeleteConfirm = false

    // Form state
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
        .onAppear {
            if editingUserID == nil, let first = users.first {
                editingUserID = first.id
            }
        }
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
            leftHeader
            Divider().background(Color.hxSurfaceBorder)
            userListContent
        }
        .background(Color.hxSurface.ignoresSafeArea())
    }

    private var leftHeader: some View {
        VStack(alignment: .leading, spacing: HXSpacing.md) {
            HStack {
                HStack(spacing: HXSpacing.sm) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(Color.hxCyan)
                    Text("Trainees")
                        .font(.hxTitle2)
                        .foregroundStyle(.white)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.hxSurfaceBorder)
                }
                .buttonStyle(.plain)
            }

            // Search
            HStack(spacing: HXSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(Color.hxSurfaceBorder)
                TextField("Search trainees", text: $searchText)
                    .font(.hxBody)
                    .foregroundStyle(.white)
                    .tint(Color.hxCyan)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.hxSurfaceBorder)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, HXSpacing.md)
            .padding(.vertical, HXSpacing.sm)
            .background(Color.hxSurfaceRaised, in: RoundedRectangle(cornerRadius: HXRadius.sm))

            // Add button
            Button { startCreatingNew() } label: {
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
                    MgmtUserRow(
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
            editFormView(title: "New Trainee", user: nil)
                .id("new")
        } else if let user = editingUser {
            editFormView(title: user.displayName, user: user)
                .id(user.id)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: HXSpacing.xl) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 72))
                .foregroundStyle(Color.hxSurfaceBorder)
            VStack(spacing: HXSpacing.sm) {
                Text("Select a Trainee")
                    .font(.hxTitle2)
                    .foregroundStyle(.white)
                Text("Choose a trainee from the list to edit their profile,\nor create a new one.")
                    .font(.hxBody)
                    .foregroundStyle(Color(white: 0.45))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Edit Form

    private func editFormView(title: String, user: UserRecord?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HXSpacing.xl) {

                HStack {
                    Text(title)
                        .font(.hxTitle2)
                        .foregroundStyle(.white)
                    Spacer()
                    // Active badge if this is the selected trainee
                    if let user, appModel.selectedUser?.id == user.id {
                        HStack(spacing: 4) {
                            StatusDot(color: Color.hxCyan, isActive: true)
                            Text("Active")
                                .font(.hxCaption)
                                .foregroundStyle(Color.hxCyan)
                        }
                        .padding(.horizontal, HXSpacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.hxCyan.opacity(0.10), in: Capsule())
                    }
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

                // Dominant hand
                formSection(label: "Dominant Hand") {
                    Picker("Hand", selection: $formHand) {
                        ForEach(DominantHand.allCases, id: \.self) { hand in
                            Text(hand.rawValue.capitalized).tag(hand)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Stats summary if editing existing
                if let user {
                    formSection(label: "Profile") {
                        VStack(spacing: HXSpacing.xs) {
                            infoRow("Created", value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
                            infoRow("Last Updated", value: user.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                // Actions
                VStack(spacing: HXSpacing.sm) {
                    if let user {
                        // Save changes
                        Button {
                            saveChanges(to: user)
                        } label: {
                            Label("Save Changes", systemImage: "checkmark.circle.fill")
                                .font(.hxHeadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color.hxCyan)
                        .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)

                        // Destructive: delete
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Trainee", systemImage: "trash")
                                .font(.hxBody)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(Color.hxDanger)
                    } else {
                        // Create
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

    // MARK: - Reusable Form Helpers

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

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.45))
            Spacer()
            Text(value)
                .font(.hxCaption)
                .foregroundStyle(Color(white: 0.55))
        }
        .padding(.horizontal, HXSpacing.md)
        .padding(.vertical, HXSpacing.sm)
        .background(Color.hxSurfaceRaised, in: RoundedRectangle(cornerRadius: HXRadius.xs))
    }

    // MARK: - Actions

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

// MARK: - Management User Row
// Same layout as UserChooserView's UserRow but without selection semantics.

private struct MgmtUserRow: View {
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
                isEditing ? Color.hxCyan.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: HXRadius.sm)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.hxDefault, value: isEditing)
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
        UserManagementView(appModel: AppModel())
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
