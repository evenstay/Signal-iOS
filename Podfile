platform :ios, '9.0'
source 'https://github.com/CocoaPods/Specs.git'

use_frameworks!

def shared_pods

  ###
  # OWS Pods
  ###

  pod 'SignalCoreKit', git: 'https://github.com/signalapp/SignalCoreKit.git', testspecs: ["Tests"]
  # pod 'SignalCoreKit', path: '../SignalCoreKit', testspecs: ["Tests"]

  pod 'AxolotlKit', git: 'https://github.com/signalapp/SignalProtocolKit.git', branch: 'master', testspecs: ["Tests"]
  # pod 'AxolotlKit', path: '../SignalProtocolKit', testspecs: ["Tests"]

  pod 'HKDFKit', git: 'https://github.com/signalapp/HKDFKit.git', testspecs: ["Tests"]
  # pod 'HKDFKit', path: '../HKDFKit', testspecs: ["Tests"]

  pod 'Curve25519Kit', git: 'https://github.com/signalapp/Curve25519Kit', testspecs: ["Tests"]
  # pod 'Curve25519Kit', path: '../Curve25519Kit', testspecs: ["Tests"]

  pod 'SignalMetadataKit', git: 'https://github.com/signalapp/SignalMetadataKit', testspecs: ["Tests"]
  # pod 'SignalMetadataKit', path: '../SignalMetadataKit', testspecs: ["Tests"]

  pod 'SignalServiceKit', path: '.', testspecs: ["Tests"]

  ###
  # forked third party pods
  ###

  # Includes some soon to be released "unencrypted header" changes required for the Share Extension
  pod 'SQLCipher', :git => 'https://github.com/sqlcipher/sqlcipher.git', :commit => 'd5c2bec'
  # pod 'SQLCipher', path: '../sqlcipher'

  # Forked for performance optimizations that are not likely to be upstreamed as they are specific
  # to our limited use of Mantle 
  pod 'Mantle', git: 'https://github.com/signalapp/Mantle', branch: 'signal-master'
  # pod 'Mantle', path: '../Mantle'

  # SocketRocket has some critical crash fixes on Github, but have published an official release to cocoapods in ages, so
  # we were following master
  # Forked and have an open PR with our changes, but they have not been merged.
  # pod 'SocketRocket', :git => 'https://github.com/facebook/SocketRocket.git', inhibit_warnings: true
  pod 'SocketRocket', :git => 'https://github.com/signalapp/SocketRocket.git', branch: 'mkirk/handle-sec-err', inhibit_warnings: true

  # Forked for compatibily with the ShareExtension, changes have an open PR, but have not been merged.
  pod 'YapDatabase/SQLCipher', :git => 'https://github.com/signalapp/YapDatabase.git', branch: 'signal-release'
  # pod 'YapDatabase/SQLCipher', path: '../YapDatabase'

  # Forked to incorporate our self-built binary artifact.
  pod 'GRKOpenSSLFramework', git: 'https://github.com/signalapp/GRKOpenSSLFramework'
  #pod 'GRKOpenSSLFramework', path: '../GRKOpenSSLFramework'

  ###
  # third party pods
  ####

  pod 'AFNetworking', inhibit_warnings: true
  pod 'PureLayout', :inhibit_warnings => true
  pod 'Reachability', :inhibit_warnings => true
  pod 'YYImage', :inhibit_warnings => true
end

target 'Signal' do
  shared_pods
  pod 'SSZipArchive', :inhibit_warnings => true

  target 'SignalTests' do
    inherit! :search_paths
  end
end

target 'SignalShareExtension' do
  shared_pods
end

target 'SignalMessaging' do
  shared_pods
end

post_install do |installer|
  enable_extension_support_for_purelayout(installer)
end

# PureLayout by default makes use of UIApplication, and must be configured to be built for an extension.
def enable_extension_support_for_purelayout(installer)
  installer.pods_project.targets.each do |target|
    if target.name.end_with? "PureLayout"
      target.build_configurations.each do |build_configuration|
        if build_configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] == 'YES'
          build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = ['$(inherited)', 'PURELAYOUT_APP_EXTENSIONS=1']
        end
      end
    end
  end
end

