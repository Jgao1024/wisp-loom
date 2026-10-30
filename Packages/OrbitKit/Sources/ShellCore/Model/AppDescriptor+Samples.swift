extension AppDescriptor {
    /// Placeholder apps until plugins provide real ones.
    public static let samples: [AppDescriptor] = [
        ("Notes", "note.text", AppTint.yellow, "Productivity"),
        ("Reminders", "checklist", .red, "Productivity"),
        ("Files", "folder.fill", .blue, "Tools"),
        ("Terminal", "terminal.fill", .gray, "Developer Tools"),
        ("Chat", "bubble.left.fill", .green, "Social"),
        ("Music", "music.note", .pink, "Entertainment"),
        ("Weather", "cloud.sun.fill", .teal, "Information"),
    ].map { name, symbol, tint, category in
        AppDescriptor(
            id: AppID(rawValue: "sample." + name.lowercased()), name: name, symbolName: symbol, tint: tint,
            category: category)
    }
}
