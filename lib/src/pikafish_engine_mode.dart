/// Selects how Pikafish runs.
enum PikafishEngineMode {
  /// Uses the official Android executable and selects DotProd when supported.
  ///
  /// Windows and Linux select the broadly compatible SSE4.1/POPCNT executable.
  /// iOS always uses the bundled FFI engine.
  auto,

  /// Uses the official generic ARMv8 Android executable.
  officialArmv8,

  /// Uses the official ARMv8 DotProd Android executable.
  officialDotProd,

  /// Uses the official SSE4.1/POPCNT desktop executable.
  officialSse41Popcnt,

  /// Uses the official BMI2 desktop executable.
  officialBmi2,

  /// Uses the official AVX2 desktop executable.
  officialAvx2,

  /// Uses the official AVX512 desktop executable.
  officialAvx512,

  /// Uses the official AVX512 Icelake desktop executable.
  officialAvx512Icl,

  /// Uses the official AVX VNNI desktop executable.
  officialAvxVnni,

  /// Uses the official VNNI512 desktop executable.
  officialVnni512,
}
