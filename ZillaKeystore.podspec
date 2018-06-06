Pod::Spec.new do |s|
  s.name         = 'ZillaKeystore'
  s.version      = '0.4.1'
  s.summary      = 'A general-purpose Ethereum keystore for managing wallets.'
  s.homepage     = 'https://github.com/zla-io/trust-keystore'
  s.license      = 'ZLA'
  s.authors      = { 'Jamal Mahfuz' => 'jamalmahfuz@outlook.com' }
  
  s.ios.deployment_target = '10.0'

  s.source       = { git: 'https://github.com/zla-io/trust-keystore.git', tag: s.version }
  s.source_files = "Sources/**/*.swift"

  s.dependency 'CryptoSwift'
  s.dependency 'ZillaCore'

  s.pod_target_xcconfig = { 'SWIFT_OPTIMIZATION_LEVEL' => '-Owholemodule' }
end
