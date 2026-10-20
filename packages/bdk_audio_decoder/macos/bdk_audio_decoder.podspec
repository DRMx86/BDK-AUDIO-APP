Pod::Spec.new do |s|
  s.name = 'bdk_audio_decoder'
  s.version = '0.0.1'
  s.summary = 'Offline bounded audio decoding for BDK sound imports.'
  s.description = 'Portable WAV, MP3 and FLAC decoding without playback or audio-device APIs.'
  s.homepage = 'https://github.com/mackron/miniaudio'
  s.license = { :file => '../LICENSE' }
  s.author = 'BDK Audio contributors'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.libraries = 'c++'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreMedia', 'Foundation'
  s.compiler_flags = '-std=c++17 -fno-fast-math -fobjc-arc'
end
