Pod::Spec.new do |s|
  s.name             = 'NetworkCore'
  s.version          = '1.0.0'
  s.summary          = 'Production-grade networking framework with request, streaming, cache, auth, observability, resilience, and background download support.'
  s.description      = <<-DESC
NetworkCore is a production-grade networking framework for Apple platforms.
It provides HTTP requests, SSE/WebSocket streaming, caching, auth extension
points, observability, resilience primitives, and background download support.
  DESC
  s.homepage         = 'https://github.com/ArcticLunar/NetworkCore'
  s.license          = { :type => 'Proprietary', :file => 'LICENSE' }
  s.author           = { 'ArcticLunar' => 'opensource@arctlunar.local' }
  s.source           = { :git => 'https://github.com/ArcticLunar/NetworkCore.git', :tag => s.version.to_s }

  s.platforms = {
    :ios => '17.0',
    :osx => '13.0'
  }
  s.swift_versions = ['5.10']
  s.requires_arc = true

  s.source_files = 'Sources/NetworkCore/**/*.swift'
  s.dependency 'Alamofire', '5.11.1'
end
