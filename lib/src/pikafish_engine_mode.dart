/// Selects how Pikafish runs.
enum PikafishEngineMode {
  /// Uses the official universal Android executable with automatic ISA selection.
  ///
  /// Windows and Linux select the broadly compatible SSE4.1/POPCNT executable.
  /// iOS always uses the bundled FFI engine.
  auto,

  /// Legacy Android mode; now uses the universal executable.
  officialArmv8,

  /// Legacy Android mode; now uses the universal executable.
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
