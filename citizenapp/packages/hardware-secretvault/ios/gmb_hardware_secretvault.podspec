Pod::Spec.new do |spec|
  spec.name             = 'gmb_hardware_secretvault'
  spec.version          = '1.0.0'
  spec.summary          = 'GMB shared hardware-bound wallet secret vault.'
  spec.description      = 'Secure Enclave and current-biometry bound wallet secret encryption.'
  spec.homepage         = 'https://gmb.org'
  spec.license          = { :type => 'Proprietary' }
  spec.author           = { 'GMB' => 'security@gmb.org' }
  spec.source           = { :path => '.' }
  spec.source_files     = 'Classes/**/*'
  spec.dependency 'Flutter'
  spec.platform = :ios, '13.0'
  spec.swift_version = '5.0'
end
