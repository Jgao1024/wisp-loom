// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "WispLoomKit",
    platforms: [.macOS(.v27)],
    products: ["ShellCore", "ShellUI", "ShellPlatform", "AppRuntime"].map { .library(name: $0, targets: [$0]) },
    targets: [
        .target(name: "ShellCore"),
        .target(name: "ShellUI", dependencies: ["ShellCore"]),
        .target(name: "ShellPlatform", dependencies: ["ShellCore"]),
        .target(name: "AppRuntime", dependencies: ["ShellCore"]),
        .testTarget(name: "ShellCoreTests", dependencies: ["ShellCore"]),
        .testTarget(name: "AppRuntimeTests", dependencies: ["AppRuntime", "ShellCore"]),
    ]
)

for target in package.targets {
    target.swiftSettings = [.treatAllWarnings(as: .error, .when(configuration: .release))]
}
