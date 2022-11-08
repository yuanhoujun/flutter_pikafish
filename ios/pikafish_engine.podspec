#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pikafish_engine.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pikafish_engine'
  s.version          = '0.0.1'
  s.summary          = 'Pikafish Chinese Chess Engine for flutter.'
  s.description      = <<-DESC
  Pikafish Chinese Chess Engine for flutter.
                       DESC
  s.homepage         = 'http://mdevs.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'He Zhaoyun' => 'hezhaoyun@outlook.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*', 'Pikafish/src/**/*', 'FlutterPikafish/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '9.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }

  s.library = 'c++'

  # s.script_phase = {
  #   :execution_position => :before_compile,
  #   :name => 'Download nnue',
  #   :script => "[ -e 'nn-3475407dc199.nnue' ] || curl --location --remote-name 'https://tests.stockfishchess.org/api/nn/nn-3475407dc199.nnue'"
  # }
  
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -w'
  }
end
