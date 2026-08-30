#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pikafish_engine.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pikafish_engine'
  s.version          = '0.0.1'
  s.summary          = 'Pikafish Chinese Chess Engine for Flutter.'
  s.description      = <<-DESC
  Pikafish Chinese Chess Engine for Flutter.
                       DESC
  s.homepage         = 'http://mdevs.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'He Zhaoyun' => 'hezhaoyun@outlook.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*', 'Source/**/*', 'Pikafish/src/**/*.h', 'FlutterPikafish/*.h'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.11'

  s.library = 'c++'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/FlutterPikafish" "${PODS_TARGET_SRCROOT}/Pikafish/src"',
    'GCC_PREPROCESSOR_DEFINITIONS[config=Profile]' => '$(inherited) NDEBUG=1',
    'GCC_PREPROCESSOR_DEFINITIONS[config=Release]' => '$(inherited) NDEBUG=1'
  }

  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -w'
  }
end
