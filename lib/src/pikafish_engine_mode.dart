/// Selects how Pikafish runs.
enum PikafishEngineMode {
  /// Uses the official Android executable and selects DotProd when supported.
  ///
  /// iOS always uses the bundled FFI engine.
  auto,

  /// Uses the official generic ARMv8 Android executable.
  officialArmv8,

  /// Uses the official ARMv8 DotProd Android executable.
  officialDotProd,
}
