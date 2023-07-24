Pod::Spec.new do |s|
  s.name             = 'TwitterImagePipeline'
  s.version          = '2.25.0'
  s.compiler_flags   = '-DTIP_PROJECT_VERSION=2.25'
  s.summary          = 'Twitter Image Pipeline is a robust and performant image loading and caching framework for iOS'
  s.description      = 'Twitter created a framework for image loading/caching in order to fulfill the numerous needs of Twitter for iOS including being fast, safe, modular and versatile.'
  s.homepage         = 'https://github.com/twitter/ios-twitter-image-pipeline'
  s.license          = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.author           = { 'Twitter' => 'opensource@twitter.com' }
  s.source           = { :git => 'https://github.com/twitter/ios-twitter-image-pipeline.git', :tag => s.version.to_s }
  s.ios.deployment_target = '10.0'
  s.swift_versions   = [ 5.0 ]

  s.subspec 'Default' do |sp|
    sp.source_files = 'TwitterImagePipeline/**/*.{h,m}'
    sp.public_header_files = 'TwitterImagePipeline/*.h'
  end

  s.subspec 'WebPCodec' do |sp|
    sp.subspec 'Default' do |ssp|
      ssp.source_files = 'Extended/TIPXWebPCodec.{h,m}', 'Extended/TIPXUtils.{h,m}'
      ssp.public_header_files = 'Extended/TIPXWebPCodec.h'
      ssp.vendored_frameworks = 'Extended/WebP.xcframework'
      ssp.dependency 'TwitterImagePipeline/Default'
    end

    sp.subspec 'Animated' do |ssp|
      ssp.xcconfig = { 'GCC_PREPROCESSOR_DEFINITIONS' => 'TIPX_WEBP_ANIMATION_DECODING_ENABLED=1' }
      ssp.vendored_frameworks = 'Extended/WebPDemux.xcframework'
      ssp.dependency 'TwitterImagePipeline/WebPCodec/Default'
    end
  end

  s.subspec 'MP4Codec' do |sp|
    sp.source_files = 'Extended/TIPXMP4Codec.{h,m}', 'Extended/TIPXUtils.{h,m}'
    sp.public_header_files = 'Extended/TIPXMP4Codec.h'
    sp.dependency 'TwitterImagePipeline/Default'
  end

  s.default_subspec = 'Default'
end
