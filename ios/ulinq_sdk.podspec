Pod::Spec.new do |s|
  s.name             = 'ulinq_sdk'
  s.version          = '1.0.0'
  s.summary          = 'Ulinq deep link and install attribution Flutter SDK.'
  s.description      = <<-DESC
Production-ready Flutter SDK for Ulinq deep links.
                       DESC
  s.homepage         = 'https://ulinq.cc'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ulinq' => 'support@ulinq.cc' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
end
