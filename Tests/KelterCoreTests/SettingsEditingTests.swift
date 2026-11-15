import XCTest
@testable import KelterCore

final class SettingsEditingTests: XCTestCase {
    func testVariableNames() throws {
        XCTAssertEqual(try SettingsEditing.variableName("  DXVK_HUD "), "DXVK_HUD")
        XCTAssertEqual(try SettingsEditing.variableName("_private1"), "_private1")
        for bad in ["", "1ABC", "MY-VAR", "A B", "ÄRGER", "X=1"] {
            XCTAssertThrowsError(try SettingsEditing.variableName(bad), bad) { error in
                XCTAssertEqual(error as? SettingsEditingError,
                               .invalidVariableName(bad.trimmingCharacters(in: .whitespaces)))
            }
        }
    }

    func testKelterOwnVariablesAreReserved() {
        XCTAssertThrowsError(try SettingsEditing.variableName("wineprefix")) { error in
            XCTAssertEqual(error as? SettingsEditingError, .reservedVariable("WINEPREFIX"))
        }
        XCTAssertThrowsError(try SettingsEditing.variableName("WINEDLLOVERRIDES"))
        // Other Wine variables are the user's to set.
        XCTAssertNoThrow(try SettingsEditing.variableName("WINEDEBUG"))
    }

    func testLibraryNamesAreNormalised() throws {
        XCTAssertEqual(try SettingsEditing.libraryName(" D3D11.dll "), "d3d11")
        XCTAssertEqual(try SettingsEditing.libraryName("Steam.exe"), "steam.exe")
        XCTAssertEqual(try SettingsEditing.libraryName("api-ms-win-core_1"), "api-ms-win-core_1")
        for bad in ["", ".dll", "d3d11=n", "a;b", "x,y", "../evil", "C:\\x.dll"] {
            XCTAssertThrowsError(try SettingsEditing.libraryName(bad), bad)
        }
    }

    func testOverrideModesReadWineSpellings() {
        XCTAssertEqual(DllOverrideMode(wineValue: "native,builtin"), .nativeThenBuiltin)
        XCTAssertEqual(DllOverrideMode(wineValue: "b, n"), .builtinThenNative)
        XCTAssertEqual(DllOverrideMode(wineValue: "N"), .native)
        XCTAssertEqual(DllOverrideMode(wineValue: ""), .disabled)
        XCTAssertEqual(DllOverrideMode(wineValue: "d"), .disabled)
        XCTAssertNil(DllOverrideMode(wineValue: "x"))
    }

    func testSettingReplacesAndKeepsOneSpellingPerVariable() throws {
        var settings = BottleSettings()
        try SettingsEditing.setVariable("dxvk_hud", value: "fps", in: &settings)
        try SettingsEditing.setVariable("DXVK_HUD", value: "full", in: &settings)
        XCTAssertEqual(settings.environment, ["DXVK_HUD": "full"])
        try SettingsEditing.setVariable("EMPTY", value: "", in: &settings)
        XCTAssertEqual(settings.environment["EMPTY"], "")

        try SettingsEditing.setOverride("D3D11.DLL", mode: .nativeThenBuiltin, in: &settings)
        try SettingsEditing.setOverride("d3d11", mode: .builtin, in: &settings)
        XCTAssertEqual(settings.dllOverrides, ["d3d11": "b"])
    }

    func testFailedEditLeavesSettingsUnchanged() {
        var settings = BottleSettings(environment: ["A": "1"])
        XCTAssertThrowsError(try SettingsEditing.setVariable("1BAD", value: "x", in: &settings))
        XCTAssertThrowsError(try SettingsEditing.setOverride("a;b", mode: .native, in: &settings))
        XCTAssertEqual(settings, BottleSettings(environment: ["A": "1"]))
    }

    func testSortedIsStable() {
        XCTAssertEqual(SettingsEditing.sorted(["b": "2", "A10": "x", "A2": "y"]).map(\.key), ["A2", "A10", "b"])
    }
}
